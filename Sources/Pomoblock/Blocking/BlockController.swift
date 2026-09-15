import Foundation
import Observation

/// サイトブロックの状態管理。
///
/// 実際に /etc/hosts を書き換えるのは root 権限の常駐ガードで、
/// このクラスはガードが読む状態ファイルを更新する役目に徹する。
@MainActor
@Observable
final class BlockController {

    /// 常駐ガードが導入済みか
    private(set) var isGuardInstalled = false

    /// 現在ブロック中か（アプリが要求している状態）
    private(set) var isBlocking = false

    /// Locked Mode の期限。nil ならロックされていない。
    private(set) var lockedUntil: Date?

    /// 直近のエラー。UI に表示する。
    var lastError: String?

    /// 直近の成功メッセージ。UI に表示する。
    var lastStatus: String?

    private let fileManager = FileManager.default

    init() {
        refresh()
    }

    /// ロック中か
    var isLocked: Bool {
        guard let lockedUntil else { return false }
        return lockedUntil > Date()
    }

    /// ロック残り時間の表示文字列
    var lockRemainingText: String? {
        guard let lockedUntil, lockedUntil > Date() else { return nil }
        let seconds = Int(lockedUntil.timeIntervalSinceNow)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "残り \(hours) 時間 \(minutes) 分" : "残り \(minutes) 分"
    }

    // MARK: - 状態の読み直し

    /// ディスク上の状態を読み直す。
    func refresh() {
        isGuardInstalled = fileManager.fileExists(atPath: AppConstants.guardPlistPath)
            && fileManager.fileExists(atPath: AppConstants.guardScriptPath)
        lockedUntil = readLockExpiry()
        isBlocking = readDesiredBlocking()
    }

    /// lock.conf から期限を読む。
    private func readLockExpiry() -> Date? {
        guard let content = try? String(contentsOfFile: AppConstants.lockStatePath, encoding: .utf8) else {
            return nil
        }
        for line in content.split(separator: "\n") where line.hasPrefix("locked_until=") {
            let raw = line.dropFirst("locked_until=".count)
            guard let epoch = TimeInterval(raw) else { return nil }
            let date = Date(timeIntervalSince1970: epoch)
            return date > Date() ? date : nil
        }
        return nil
    }

    /// desired.conf から現在の要求状態を読む。
    private func readDesiredBlocking() -> Bool {
        guard let content = try? String(contentsOfFile: AppConstants.desiredStatePath, encoding: .utf8) else {
            return false
        }
        return content.split(separator: "\n").contains { $0 == "blocked=1" }
    }

    // MARK: - ブロックの ON/OFF（管理者認証なし）

    /// ブロックの要求状態を書き込む。ガードが検知して hosts に反映する。
    /// - Parameters:
    ///   - blocked: ブロックしたいか
    ///   - domains: ブロック対象ドメイン
    func setBlocking(_ blocked: Bool, domains: [String]) {
        guard isGuardInstalled else { return }

        var lines = ["blocked=\(blocked ? 1 : 0)"]
        lines.append(contentsOf: domains)
        let body = lines.joined(separator: "\n") + "\n"

        do {
            // launchd の WatchPaths を確実に発火させるため、inode を保つ非アトミック書き込みにする
            try body.write(toFile: AppConstants.desiredStatePath, atomically: false, encoding: .utf8)
            isBlocking = blocked
        } catch {
            lastError = "ブロック状態の書き込みに失敗しました: \(error.localizedDescription)"
        }
    }

    // MARK: - Locked Mode（管理者認証あり）

    /// 指定時刻までブロックを解除不能にする。
    func lock(until expiry: Date, domains: [String]) {
        guard isGuardInstalled else {
            lastError = "先に常駐ガードを導入してください。"
            return
        }

        var lines = ["locked_until=\(Int(expiry.timeIntervalSince1970))"]
        lines.append(contentsOf: domains)
        let body = lines.joined(separator: "\n") + "\n"

        // root 所有で書き込む。ユーザー権限では書き換えられないことがロックの根拠になる。
        let script = """
        umask 022
        cat > \(PrivilegedRunner.shellQuote(AppConstants.lockStatePath)) <<'POMOBLOCK_LOCK_EOF'
        \(body)POMOBLOCK_LOCK_EOF
        chown root:wheel \(PrivilegedRunner.shellQuote(AppConstants.lockStatePath))
        chmod 644 \(PrivilegedRunner.shellQuote(AppConstants.lockStatePath))
        launchctl kickstart -k system/\(AppConstants.guardLabel)
        """

        run(script, onSuccess: "ロックを設定しました。")
    }

    // MARK: - 常駐ガードの導入と撤去

    /// 常駐ガードを導入する。管理者認証が一度だけ必要。
    func installGuard() {
        guard let scriptURL = Bundle.main.url(forResource: "pomoblock-guard", withExtension: "sh"),
              let plistURL = Bundle.main.url(forResource: AppConstants.guardLabel, withExtension: "plist")
        else {
            lastError = "アプリに同梱されたガードのファイルが見つかりません。"
            return
        }

        let currentUser = NSUserName()
        let script = """
        set -e
        mkdir -p /usr/local/libexec
        mkdir -p \(PrivilegedRunner.shellQuote(AppConstants.sharedDirectory))
        chown root:wheel \(PrivilegedRunner.shellQuote(AppConstants.sharedDirectory))
        chmod 755 \(PrivilegedRunner.shellQuote(AppConstants.sharedDirectory))
        install -m 755 -o root -g wheel \(PrivilegedRunner.shellQuote(scriptURL.path)) \(PrivilegedRunner.shellQuote(AppConstants.guardScriptPath))
        install -m 644 -o root -g wheel \(PrivilegedRunner.shellQuote(plistURL.path)) \(PrivilegedRunner.shellQuote(AppConstants.guardPlistPath))
        touch \(PrivilegedRunner.shellQuote(AppConstants.desiredStatePath))
        chown \(PrivilegedRunner.shellQuote(currentUser)) \(PrivilegedRunner.shellQuote(AppConstants.desiredStatePath))
        chmod 644 \(PrivilegedRunner.shellQuote(AppConstants.desiredStatePath))
        launchctl bootout system/\(AppConstants.guardLabel) 2>/dev/null || true
        launchctl bootstrap system \(PrivilegedRunner.shellQuote(AppConstants.guardPlistPath))
        """

        run(script, onSuccess: "常駐ガードを導入しました。")
    }

    /// 常駐ガードを撤去し、hosts を元に戻す。ロック中は実行できない。
    func uninstallGuard() {
        guard !isLocked else {
            lastError = "ロック中は撤去できません。期限まで待ってください。"
            return
        }

        let script = """
        launchctl bootout system/\(AppConstants.guardLabel) 2>/dev/null || true
        rm -f \(PrivilegedRunner.shellQuote(AppConstants.guardPlistPath))
        rm -f \(PrivilegedRunner.shellQuote(AppConstants.guardScriptPath))
        rm -f \(PrivilegedRunner.shellQuote(AppConstants.lockStatePath))
        rm -f \(PrivilegedRunner.shellQuote(AppConstants.desiredStatePath))
        tmp=$(mktemp /tmp/pomoblock.XXXXXX)
        sed '/^# >>> pomoblock begin >>>$/,/^# <<< pomoblock end <<<$/d' \(AppConstants.hostsPath) > "$tmp"
        cat "$tmp" > \(AppConstants.hostsPath)
        rm -f "$tmp"
        dscacheutil -flushcache 2>/dev/null || true
        killall -HUP mDNSResponder 2>/dev/null || true
        """

        run(script, onSuccess: "常駐ガードを撤去しました。")
    }

    /// 管理者権限スクリプトを実行し、結果を状態へ反映する。
    private func run(_ script: String, onSuccess message: String) {
        do {
            try PrivilegedRunner.runAsRoot(script)
            lastError = nil
            lastStatus = message
        } catch PrivilegedRunner.RunError.cancelled {
            lastStatus = nil
            lastError = "管理者認証がキャンセルされました。"
        } catch {
            lastStatus = nil
            lastError = error.localizedDescription
        }
        refresh()
    }
}
