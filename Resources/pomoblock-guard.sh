#!/bin/sh
#
# Pomoblock 常駐ガード
#
# launchd（LaunchDaemon）から root 権限で起動され、以下を行う。
#   1. アプリが書いた desired.conf を読む
#   2. ブロックが要求されていれば /etc/hosts にブロック領域を書き込む
#   3. 要求されていなければブロック領域を取り除く
#
# 遮断するのはポモドーロの作業フェーズ中だけで、その判断はアプリ側が持つ。
# ガードは要求どおりに hosts を保つことと、手で書き換えられた場合の復旧に徹する。
#
set -u

HOSTS="/etc/hosts"
BEGIN_MARK="# >>> pomoblock begin >>>"
END_MARK="# <<< pomoblock end <<<"
DESIRED_FILE="/Library/Application Support/Pomoblock/desired.conf"

# hosts に書き込むループバックアドレス（IPv4 / IPv6）
IPV4_SINK="0.0.0.0"
IPV6_SINK="::"

# ---- アプリ側の要求の読み取り ---------------------------------------------
# desired.conf の 1 行目は blocked=0|1、2 行目以降はドメイン一覧。
should_block=0
domains=""
if [ -f "$DESIRED_FILE" ]; then
    value=$(sed -n 's/^blocked=//p' "$DESIRED_FILE" | head -1)
    if [ "$value" = "1" ]; then
        should_block=1
        domains=$(grep -v '^blocked=' "$DESIRED_FILE")
    fi
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
