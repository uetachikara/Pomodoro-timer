import Foundation

/// アプリ全体で共有する定数。マジックナンバーはすべてここに集約する。
enum AppConstants {

    // MARK: - 識別子

    /// バンドル識別子。ビルドスクリプトが生成する Info.plist と一致させること。
    static let bundleIdentifier = "jp.havas.pomoblock"

    /// 常駐ガード（LaunchDaemon）のラベル。
    static let guardLabel = "jp.havas.pomoblock.guard"

    // MARK: - ポモドーロ既定値（単位:秒）

    /// 作業フェーズの既定の長さ
    static let defaultWorkDuration: TimeInterval = 25 * 60

    /// 短い休憩の既定の長さ
    static let defaultShortBreakDuration: TimeInterval = 5 * 60

    /// 長い休憩の既定の長さ
    static let defaultLongBreakDuration: TimeInterval = 15 * 60

    /// 長い休憩を挟むまでに消化する作業セッション数
    static let defaultSessionsUntilLongBreak = 4

    /// 設定画面で許容する各フェーズ長の範囲（分）
    static let minimumDurationMinutes = 1
    static let maximumDurationMinutes = 120

    /// 残り時間表示を更新する間隔（秒）
    static let tickInterval: TimeInterval = 1.0

    // MARK: - Locked Mode

    /// ロック時間の選択肢（分）
    static let lockDurationChoicesMinutes = [30, 60, 90, 120, 180, 240]

    /// ロック時間の既定値（分）
    static let defaultLockDurationMinutes = 60

    // MARK: - ファイル配置

    /// ガードが書き換える hosts ファイル
    static let hostsPath = "/etc/hosts"

    /// ガードとユーザーアプリが共有する状態ディレクトリ
    static let sharedDirectory = "/Library/Application Support/Pomoblock"

    /// アプリ側が書き込む「ブロックしたい状態」。所有者はインストールしたユーザー。
    static let desiredStatePath = sharedDirectory + "/desired.conf"

    /// ロック状態を保持するファイル。root 所有なのでアプリ単体では書き換えられない。
    static let lockStatePath = sharedDirectory + "/lock.conf"

    /// 常駐ガード本体の設置先
    static let guardScriptPath = "/usr/local/libexec/pomoblock-guard.sh"

    /// LaunchDaemon の plist 設置先
    static let guardPlistPath = "/Library/LaunchDaemons/jp.havas.pomoblock.guard.plist"

    // MARK: - 既定のブロック対象

    /// 初期状態でブロックするドメイン。X 本体と短縮 URL、代表的な SNS を含める。
    static let defaultBlockedDomains = [
        "x.com",
        "www.x.com",
        "mobile.x.com",
        "twitter.com",
        "www.twitter.com",
        "mobile.twitter.com",
        "t.co",
        "www.instagram.com",
        "instagram.com",
        "www.youtube.com",
        "youtube.com",
        "www.reddit.com",
        "reddit.com",
    ]
}
