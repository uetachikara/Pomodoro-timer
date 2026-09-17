import AppKit
import Foundation

/// 既に開いているタブへブロックを波及させる。
///
/// /etc/hosts はこれから行う名前解決を止めるだけで、
/// 読み込み済みのページや確立済みの接続には効かない。
///
/// 当初は対象タブを再読み込みしていたが、それでは足りなかった。
/// X のような PWA は Service Worker がアプリシェルをキャッシュから返すため、
/// 再読み込みしてもネットワークに出ず画面が出続ける。
///
/// そこでタブごとローカルの退避ページへ飛ばす。
/// 元の URL はそのページに表示するので、解除後に戻れる。
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

    /// タブ再読み込みの結果。UI への表示と原因追跡に使う。
    struct Outcome: Sendable {
        /// 起動していた対応ブラウザ名
        var runningBrowsers: [String] = []
        /// 実際に再読み込みしたタブ数
        var reloadedTabCount = 0
        /// AppleScript が失敗したブラウザ名。自動化の許可が無い場合にここへ入る。
        var failedBrowsers: [String] = []

        /// 退避ページを設置できなかったか
        var pageInstallFailed = false

        /// UI に出す一行の要約。問題が無ければ nil。
        var warning: String? {
            if pageInstallFailed {
                return "ブロック用ページを設置できませんでした。開いているタブは手動で閉じてください。"
            }
            if !failedBrowsers.isEmpty {
                return "\(failedBrowsers.joined(separator: " / ")) のタブを操作できません。システム設定 > プライバシーとセキュリティ > 自動化 で Pomoblock を許可してください。"
            }
            return nil
        }
    }

    /// ブロック対象ドメインのタブを退避ページへ飛ばす。
    /// - Parameter domains: 遮断中のドメイン
    /// - Returns: 実行結果
    @discardableResult
    static func refreshTabs(matching domains: [String]) -> Outcome {
        var outcome = Outcome()
        guard !domains.isEmpty else { return outcome }

        guard let pageURL = BlockedPage.ensureInstalled() else {
            outcome.pageInstallFailed = true
            log(outcome)
            return outcome
        }

        let targets = Set(domains.map { $0.lowercased() })

        for browser in browsers {
            let name = browser.applicationName
            guard isRunning(name) else { continue }
            outcome.runningBrowsers.append(name)

            guard let tabs = listTabs(in: browser) else {
                // AppleScript が失敗した。自動化の許可が無い場合がほとんど。
                outcome.failedBrowsers.append(name)
                continue
            }

            // 退避ページ自身は対象外。二重に飛ばさないため。
            let matched = tabs.filter { matches(url: $0.url, targets: targets) }
            guard !matched.isEmpty else { continue }
            divert(matched, in: browser, to: pageURL)
            outcome.reloadedTabCount += matched.count
        }

        // 監視は数秒ごとに走るため、退避が起きた時と失敗した時だけ記録する
        if outcome.reloadedTabCount > 0 || !outcome.failedBrowsers.isEmpty {
            log(outcome)
        }
        return outcome
    }

    /// 結果をログへ残す。UI に出ない失敗を後から追えるようにする。
    private static func log(_ outcome: Outcome) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] "
            + "起動中=\(outcome.runningBrowsers.joined(separator: ",")) "
            + "退避=\(outcome.reloadedTabCount) "
            + "失敗=\(outcome.failedBrowsers.joined(separator: ","))\n"

        let logURL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Logs/Pomoblock.log")
        guard let data = line.data(using: .utf8) else { return }

        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logURL)
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
    /// AppleScript が失敗した場合は nil を返し、「タブが 0 件」と区別する。
    private static func listTabs(in browser: Browser) -> [TabReference]? {
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

        guard let raw = runAppleScript(script) else { return nil }

        return raw.components(separatedBy: recordSeparator).compactMap { record in
            let fields = record.components(separatedBy: fieldSeparator)
            guard fields.count == 3,
                  let windowIndex = Int(fields[0].trimmingCharacters(in: .whitespacesAndNewlines)),
                  let tabIndex = Int(fields[1].trimmingCharacters(in: .whitespacesAndNewlines))
            else { return nil }
            return TabReference(windowIndex: windowIndex, tabIndex: tabIndex, url: fields[2])
        }
    }

    // MARK: - 退避

    /// 該当タブを退避ページへ飛ばす。
    /// - Parameter pageURL: 退避先のローカルページ
    private static func divert(_ tabs: [TabReference], in browser: Browser, to pageURL: URL) {
        // タブ指定の文が長くなるため、1 本のスクリプトにまとめて往復を減らす
        let statements = tabs.map { tab in
            let destination = BlockedPage.destination(for: tab.url, pageURL: pageURL)
            // Chromium 系も Safari も URL の代入で遷移できる
            return "    try\n        set URL of tab \(tab.tabIndex) of window \(tab.windowIndex) to \"\(destination)\"\n    end try"
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
    ///
    /// System Events 経由で調べると、その System Events 自体に自動化の許可が要る。
    /// 許可が無いと黙って失敗し、全ブラウザが読み飛ばされるため、
    /// 許可の要らない NSWorkspace で判定する。
    private static func isRunning(_ applicationName: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.localizedName == applicationName }
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
