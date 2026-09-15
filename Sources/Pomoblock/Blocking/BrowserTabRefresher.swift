import Foundation

/// 既に開いているタブへブロックを波及させる。
///
/// /etc/hosts はこれから行う名前解決を止めるだけで、
/// 読み込み済みのページや確立済みの接続には効かない。
/// そのため遮断を開始した時点で、対象ドメインのタブを再読み込みして
/// ブロック済みの状態（接続エラー）へ落とす。
///
/// タブを閉じるのではなく再読み込みにしているのは、URL を残して
/// 解除後に戻れるようにするため。
enum BrowserTabRefresher {

    /// 対応ブラウザ。AppleScript の語彙が異なるため系統で分けている。
    private enum Browser {
        case chromium(name: String)
        case safari

        var applicationName: String {
            switch self {
            case let .chromium(name): name
            case .safari: "Safari"
            }
        }
    }

    /// 対象とするブラウザ。起動していないものは自動的に読み飛ばす。
    private static let browsers: [Browser] = [
        .chromium(name: "Google Chrome"),
        .chromium(name: "Brave Browser"),
        .chromium(name: "Microsoft Edge"),
        .safari,
    ]

    /// AppleScript が返す一覧の区切り文字。URL に現れない文字を選ぶ。
    private static let fieldSeparator = "\u{001F}"
    private static let recordSeparator = "\u{001E}"

    /// ブロック対象ドメインのタブを再読み込みする。
    /// - Parameter domains: 遮断中のドメイン
    static func refreshTabs(matching domains: [String]) {
        guard !domains.isEmpty else { return }
        let targets = Set(domains.map { $0.lowercased() })

        for browser in browsers {
            guard isRunning(browser.applicationName) else { continue }
            let tabs = listTabs(in: browser)
            let matched = tabs.filter { matches(url: $0.url, targets: targets) }
            guard !matched.isEmpty else { continue }
            reload(matched, in: browser)
        }
    }

    // MARK: - タブの一覧取得

    /// ウィンドウ番号・タブ番号・URL の組
    private struct TabReference {
        let windowIndex: Int
        let tabIndex: Int
        let url: String
    }

    /// 起動中のブラウザからタブ一覧を取得する。
    private static func listTabs(in browser: Browser) -> [TabReference] {
        let tabCollection = switch browser {
        case .chromium: "tabs"
        case .safari: "tabs"
        }

        let script = """
        tell application "\(browser.applicationName)"
            set output to ""
            set windowIndex to 0
            repeat with w in windows
                set windowIndex to windowIndex + 1
                set tabIndex to 0
                repeat with t in \(tabCollection) of w
                    set tabIndex to tabIndex + 1
                    try
                        set output to output & windowIndex & "\(fieldSeparator)" & tabIndex & "\(fieldSeparator)" & (URL of t) & "\(recordSeparator)"
                    end try
                end repeat
            end repeat
            return output
        end tell
        """

        guard let raw = runAppleScript(script) else { return [] }

        return raw.components(separatedBy: recordSeparator).compactMap { record in
            let fields = record.components(separatedBy: fieldSeparator)
            guard fields.count == 3,
                  let windowIndex = Int(fields[0].trimmingCharacters(in: .whitespacesAndNewlines)),
                  let tabIndex = Int(fields[1].trimmingCharacters(in: .whitespacesAndNewlines))
            else { return nil }
            return TabReference(windowIndex: windowIndex, tabIndex: tabIndex, url: fields[2])
        }
    }

    // MARK: - 再読み込み

    /// 該当タブを再読み込みする。
    private static func reload(_ tabs: [TabReference], in browser: Browser) {
        // タブ指定の文が長くなるため、1 本のスクリプトにまとめて往復を減らす
        let statements = tabs.map { tab in
            switch browser {
            case .chromium:
                // Chromium 系は reload コマンドを持つ
                "    try\n        reload tab \(tab.tabIndex) of window \(tab.windowIndex)\n    end try"
            case .safari:
                // Safari には reload が無いため、同じ URL を設定し直して読み込ませる
                "    try\n        set URL of tab \(tab.tabIndex) of window \(tab.windowIndex) to (URL of tab \(tab.tabIndex) of window \(tab.windowIndex))\n    end try"
            }
        }

        let script = """
        tell application "\(browser.applicationName)"
        \(statements.joined(separator: "\n"))
        end tell
        """
        _ = runAppleScript(script)
    }

    // MARK: - 補助

    /// URL のホスト名がブロック対象と一致するか。
    /// 単純な部分一致だと box.com が x.com に引っかかるため、ホスト名で厳密に比べる。
    private static func matches(url: String, targets: Set<String>) -> Bool {
        guard let host = URLComponents(string: url)?.host?.lowercased() else { return false }
        return targets.contains(host)
    }

    /// 指定アプリが起動中か。起動していないアプリへ AppleScript を送ると
    /// 勝手に起動してしまうため、事前に確認する。
    private static func isRunning(_ applicationName: String) -> Bool {
        let script = """
        tell application "System Events" to return (exists (processes where name is "\(applicationName)"))
        """
        return runAppleScript(script)?.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    /// AppleScript を実行して標準出力を返す。失敗時は nil。
    private static func runAppleScript(_ source: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
