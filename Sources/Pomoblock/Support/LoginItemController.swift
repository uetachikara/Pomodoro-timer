import AppKit
import Foundation
import Observation

/// ログイン時の自動起動と、終了されても復帰する常駐を管理する。
///
/// LaunchAgent（ユーザー領域）として登録するため、管理者パスワードは要らない。
/// `KeepAlive` を有効にしているので、メニューから終了しても launchd が数秒で起動し直す。
@MainActor
@Observable
final class LoginItemController {

    /// 登録済みか
    private(set) var isEnabled = false

    /// 直近のエラー。UI に表示する。
    var lastError: String?

    private let fileManager = FileManager.default

    init() {
        refresh()
    }

    /// LaunchAgent の plist の場所
    private var plistURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appending(path: "Library/LaunchAgents/\(AppConstants.loginAgentLabel).plist")
    }

    /// ディスク上の状態を読み直す。
    func refresh() {
        isEnabled = fileManager.fileExists(atPath: plistURL.path)
    }

    /// 自動起動を有効・無効にする。
    func setEnabled(_ enabled: Bool) {
        enabled ? enable() : disable()
        refresh()
    }

    // MARK: - 登録

    private func enable() {
        // 実行ファイルの実体を指す。.app ごと移動された場合は登録し直す必要がある。
        let executablePath = Bundle.main.bundleURL
            .appending(path: "Contents/MacOS/\(AppConstants.executableName)")
            .path

        guard fileManager.fileExists(atPath: executablePath) else {
            lastError = "実行ファイルが見つかりません: \(executablePath)"
            return
        }

        do {
            try fileManager.createDirectory(
                at: plistURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try plistBody(executablePath: executablePath).write(to: plistURL, atomically: true, encoding: .utf8)
        } catch {
            lastError = "自動起動の設定に失敗しました: \(error.localizedDescription)"
            return
        }

        // 登録済みなら一度外してから入れ直す。パスが変わった場合に追従させるため。
        _ = runLaunchctl(["bootout", "gui/\(getuid())/\(AppConstants.loginAgentLabel)"])
        if runLaunchctl(["bootstrap", "gui/\(getuid())", plistURL.path]) {
            lastError = nil
        } else {
            lastError = "launchd への登録に失敗しました。"
        }
    }

    private func disable() {
        _ = runLaunchctl(["bootout", "gui/\(getuid())/\(AppConstants.loginAgentLabel)"])
        try? fileManager.removeItem(at: plistURL)
        lastError = nil
    }

    /// LaunchAgent の定義。
    private func plistBody(executablePath: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(AppConstants.loginAgentLabel)</string>

            <key>ProgramArguments</key>
            <array>
                <string>\(executablePath)</string>
            </array>

            <!-- ログイン時に起動する -->
            <key>RunAtLoad</key>
            <true/>

            <!-- 終了されても起動し直す -->
            <key>KeepAlive</key>
            <true/>

            <key>StandardErrorPath</key>
            <string>\(fileManager.homeDirectoryForCurrentUser.path)/Library/Logs/Pomoblock-agent.log</string>
        </dict>
        </plist>
        """
    }

    /// launchctl を実行し、成功したかを返す。
    private func runLaunchctl(_ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
