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

    /// 直近のエラー。UI に表示する。
    var lastError: String?

    /// 直近の成功メッセージ。UI に表示する。
    var lastStatus: String?

    /// タブ再読み込みの警告。自動化の許可が無い場合などに入る。
    var tabWarning: String?

    /// 直近に再読み込みしたタブ数。動作確認用。
    private(set) var lastReloadedTabCount = 0

    private let fileManager = FileManager.default

    init() {
        refresh()
    }

    // MARK: - 状態の読み直し

    /// ディスク上の状態を読み直す。
    func refresh() {
        isGuardInstalled = fileManager.fileExists(atPath: AppConstants.guardPlistPath)
            && fileManager.fileExists(atPath: AppConstants.guardScriptPath)
        isBlocking = readDesiredBlocking()
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
            if blocked {
                refreshOpenTabsAfterGuardApplies(domains: domains)
            }
        } catch {
            lastError = "ブロック状態の書き込みに失敗しました: \(error.localizedDescription)"
        }
    }

    /// 開いたままのタブへ遮断を波及させる。
    ///
    /// hosts を書き換えても読み込み済みのページは動き続けるため、
    /// ガードが反映を終えるのを待ってから対象タブを再読み込みする。
    private func refreshOpenTabsAfterGuardApplies(domains: [String]) {
        Task {
            try? await Task.sleep(for: .seconds(AppConstants.tabRefreshDelaySeconds))
            await refreshOpenTabsNow(domains: domains)
        }
    }

    /// 待たずに即座にタブを再読み込みする。動作確認用に UI からも呼べる。
    func refreshOpenTabsNow(domains: [String]) async {
        // AppleScript の往復で UI を止めないよう、メインアクターの外で実行する
        let outcome = await Task.detached(priority: .utility) {
            BrowserTabRefresher.refreshTabs(matching: domains)
        }.value

        lastReloadedTabCount = outcome.reloadedTabCount
        tabWarning = outcome.warning
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
        rm -f \(PrivilegedRunner.shellQuote(AppConstants.obsoleteLockStatePath))
        touch \(PrivilegedRunner.shellQuote(AppConstants.desiredStatePath))
        chown \(PrivilegedRunner.shellQuote(currentUser)) \(PrivilegedRunner.shellQuote(AppConstants.desiredStatePath))
        chmod 644 \(PrivilegedRunner.shellQuote(AppConstants.desiredStatePath))
        launchctl bootout system/\(AppConstants.guardLabel) 2>/dev/null || true
        launchctl bootstrap system \(PrivilegedRunner.shellQuote(AppConstants.guardPlistPath))
        """

        run(script, onSuccess: "常駐ガードを導入しました。")
    }

    /// 常駐ガードを撤去し、hosts を元に戻す。
    func uninstallGuard() {
        let script = """
        launchctl bootout system/\(AppConstants.guardLabel) 2>/dev/null || true
        rm -f \(PrivilegedRunner.shellQuote(AppConstants.guardPlistPath))
        rm -f \(PrivilegedRunner.shellQuote(AppConstants.guardScriptPath))
        rm -f \(PrivilegedRunner.shellQuote(AppConstants.obsoleteLockStatePath))
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
