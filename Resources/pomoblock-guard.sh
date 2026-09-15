#!/bin/sh
#
# Pomoblock 常駐ガード
#
# launchd（LaunchDaemon）から root 権限で起動され、以下を行う。
#   1. アプリが書いた desired.conf と、root 所有の lock.conf を読む
#   2. どちらかがブロックを要求していれば /etc/hosts にブロック領域を書き込む
#   3. どちらも要求していなければブロック領域を取り除く
#
# Locked Mode 中は lock.conf の期限が優先されるため、
# アプリを終了しても Mac を再起動してもブロックは解除されない。
#
set -u

HOSTS="/etc/hosts"
BEGIN_MARK="# >>> pomoblock begin >>>"
END_MARK="# <<< pomoblock end <<<"
DESIRED_FILE="/Library/Application Support/Pomoblock/desired.conf"
LOCK_FILE="/Library/Application Support/Pomoblock/lock.conf"

# hosts に書き込むループバックアドレス（IPv4 / IPv6）
IPV4_SINK="0.0.0.0"
IPV6_SINK="::"

now=$(date +%s)

# ---- ロック状態の読み取り -------------------------------------------------
# lock.conf の 1 行目は locked_until=<epoch>、2 行目以降はロック時点のドメイン一覧。
locked_until=0
if [ -f "$LOCK_FILE" ]; then
    locked_until=$(sed -n 's/^locked_until=//p' "$LOCK_FILE" | head -1)
    case "$locked_until" in
        '' | *[!0-9]*) locked_until=0 ;;
    esac
fi

# 期限切れのロックファイルは残さない
if [ "$locked_until" -gt 0 ] && [ "$now" -ge "$locked_until" ]; then
    rm -f "$LOCK_FILE"
    locked_until=0
fi

# ---- アプリ側の要求の読み取り ---------------------------------------------
# desired.conf の 1 行目は blocked=0|1、2 行目以降はドメイン一覧。
desired_blocked=0
if [ -f "$DESIRED_FILE" ]; then
    value=$(sed -n 's/^blocked=//p' "$DESIRED_FILE" | head -1)
    [ "$value" = "1" ] && desired_blocked=1
fi

# ---- 最終的なブロック要否とドメイン一覧の決定 -----------------------------
# ロック中はロック時点のドメイン一覧を使う。
# アプリ側の一覧を空にして抜け道を作られるのを防ぐため。
if [ "$locked_until" -gt "$now" ]; then
    should_block=1
    domains=$(grep -v '^locked_until=' "$LOCK_FILE")
elif [ "$desired_blocked" -eq 1 ]; then
    should_block=1
    domains=$(grep -v '^blocked=' "$DESIRED_FILE")
else
    should_block=0
    domains=""
fi

# ---- hosts の再構築 -------------------------------------------------------
tmp_file=$(mktemp /tmp/pomoblock.XXXXXX) || exit 1
trap 'rm -f "$tmp_file"' EXIT

# 既存のブロック領域を取り除いた内容を出力する
sed "/^${BEGIN_MARK}$/,/^${END_MARK}$/d" "$HOSTS" > "$tmp_file"

if [ "$should_block" -eq 1 ]; then
    {
        echo "$BEGIN_MARK"
        echo "$domains" | while IFS= read -r domain; do
            # 空行とコメント行は飛ばす
            case "$domain" in
                '' | '#'*) continue ;;
            esac
            printf '%s %s\n' "$IPV4_SINK" "$domain"
            printf '%s %s\n' "$IPV6_SINK" "$domain"
        done
        echo "$END_MARK"
    } >> "$tmp_file"
fi

# 内容が変わったときだけ書き戻す。不要な DNS フラッシュを避けるため。
if ! cmp -s "$tmp_file" "$HOSTS"; then
    # inode を保持したいので cp ではなくリダイレクトで上書きする
    cat "$tmp_file" > "$HOSTS"
    chmod 644 "$HOSTS"
    dscacheutil -flushcache 2>/dev/null || true
    killall -HUP mDNSResponder 2>/dev/null || true
fi

exit 0
