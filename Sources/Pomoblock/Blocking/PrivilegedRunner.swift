import Foundation

/// 管理者権限が必要な処理を実行するためのヘルパー。
///
/// osascript の `do shell script ... with administrator privileges` を使う。
/// macOS 標準の認証ダイアログが表示され、コード署名の有無に依存せず動作する。
/// 認証が必要なのはガードの導入・撤去とロックの設定だけで、
/// 通常のブロック ON/OFF ではパスワードを求めない。
enum PrivilegedRunner {

    enum RunError: LocalizedError {
        /// ユーザーが認証ダイアログをキャンセルした
        case cancelled
        /// スクリプトが非ゼロ終了した
        case failed(status: Int32, message: String)

        var errorDescription: String? {
            switch self {
            case .cancelled:
                "管理者認証がキャンセルされました。"
            case let .failed(status, message):
                "管理者権限での処理に失敗しました（終了コード \(status)）。\n\(message)"
            }
        }
    }

    /// AppleScript のユーザーキャンセルを示すエラー番号
    private static let userCancelledErrorNumber = "-128"

    /// シェルスクリプトを root 権限で実行する。
    /// - Parameter script: /bin/sh に渡すスクリプト本文
    static func runAsRoot(_ script: String) throws {
        let appleScript = """
        do shell script "\(escapeForAppleScript(script))" with administrator privileges
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()

        try process.run()
        // 認証ダイアログの応答待ちでパイプが詰まらないよう、先に読み切る
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus != 0 else { return }

        let message = String(decoding: errorData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if message.contains(userCancelledErrorNumber) {
            throw RunError.cancelled
        }
        throw RunError.failed(status: process.terminationStatus, message: message)
    }

    /// シェルスクリプトを AppleScript の文字列リテラルに埋め込める形へ変換する。
    /// バックスラッシュと二重引用符のみエスケープすればよい。
    private static func escapeForAppleScript(_ script: String) -> String {
        script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// シェルスクリプトに単一引用符で埋め込める形へ変換する。
    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
