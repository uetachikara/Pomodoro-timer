import Foundation
import Observation

/// ユーザー設定。UserDefaults に永続化する。
@MainActor
@Observable
final class AppSettings {

    /// UserDefaults のキー。値の意味が分かる名前を付ける。
    private enum Key {
        static let workMinutes = "workMinutes"
        static let shortBreakMinutes = "shortBreakMinutes"
        static let longBreakMinutes = "longBreakMinutes"
        static let sessionsUntilLongBreak = "sessionsUntilLongBreak"
        static let blockedDomains = "blockedDomains"
        static let playSound = "playSound"
        static let autoStartNextPhase = "autoStartNextPhase"
        static let alwaysBlock = "alwaysBlock"
    }

    private let defaults = UserDefaults.standard

    /// 作業フェーズの長さ（分）
    var workMinutes: Int { didSet { defaults.set(workMinutes, forKey: Key.workMinutes) } }

    /// 短い休憩の長さ（分）
    var shortBreakMinutes: Int { didSet { defaults.set(shortBreakMinutes, forKey: Key.shortBreakMinutes) } }

    /// 長い休憩の長さ（分）
    var longBreakMinutes: Int { didSet { defaults.set(longBreakMinutes, forKey: Key.longBreakMinutes) } }

    /// 長い休憩までの作業セッション数
    var sessionsUntilLongBreak: Int { didSet { defaults.set(sessionsUntilLongBreak, forKey: Key.sessionsUntilLongBreak) } }

    /// ブロック対象ドメイン
    var blockedDomains: [String] { didSet { defaults.set(blockedDomains, forKey: Key.blockedDomains) } }

    /// フェーズ切り替え時に音を鳴らすか
    var playSound: Bool { didSet { defaults.set(playSound, forKey: Key.playSound) } }

    /// フェーズ終了時に次のフェーズを自動開始するか
    var autoStartNextPhase: Bool { didSet { defaults.set(autoStartNextPhase, forKey: Key.autoStartNextPhase) } }

    /// タイマーの状態に関わらず常にブロックするか。
    /// 「今日はもう見ない」という使い方のための手動スイッチ。
    var alwaysBlock: Bool { didSet { defaults.set(alwaysBlock, forKey: Key.alwaysBlock) } }

    init() {
        // UserDefaults に値が無い場合は 0 や nil が返るため、既定値へフォールバックする
        let storedWork = defaults.integer(forKey: Key.workMinutes)
        workMinutes = storedWork > 0 ? storedWork : Int(AppConstants.defaultWorkDuration / 60)

        let storedShort = defaults.integer(forKey: Key.shortBreakMinutes)
        shortBreakMinutes = storedShort > 0 ? storedShort : Int(AppConstants.defaultShortBreakDuration / 60)

        let storedLong = defaults.integer(forKey: Key.longBreakMinutes)
        longBreakMinutes = storedLong > 0 ? storedLong : Int(AppConstants.defaultLongBreakDuration / 60)

        let storedSessions = defaults.integer(forKey: Key.sessionsUntilLongBreak)
        sessionsUntilLongBreak = storedSessions > 0 ? storedSessions : AppConstants.defaultSessionsUntilLongBreak

        let storedDomains = defaults.stringArray(forKey: Key.blockedDomains)
        blockedDomains = storedDomains ?? AppConstants.defaultBlockedDomains

        // Bool は未設定でも false が返るため、キーの存在で判定する
        playSound = defaults.object(forKey: Key.playSound) as? Bool ?? true
        autoStartNextPhase = defaults.object(forKey: Key.autoStartNextPhase) as? Bool ?? true
        alwaysBlock = defaults.object(forKey: Key.alwaysBlock) as? Bool ?? false
    }

    /// 指定フェーズの長さを秒で返す。
    func duration(for phase: PomodoroPhase) -> TimeInterval {
        switch phase {
        case .idle: 0
        case .work: TimeInterval(workMinutes * 60)
        case .shortBreak: TimeInterval(shortBreakMinutes * 60)
        case .longBreak: TimeInterval(longBreakMinutes * 60)
        }
    }

    /// ドメインを追加する。前後の空白と scheme を取り除き、重複は無視する。
    func addDomain(_ raw: String) {
        let normalized = Self.normalizeDomain(raw)
        guard !normalized.isEmpty, !blockedDomains.contains(normalized) else { return }
        blockedDomains.append(normalized)
    }

    /// ドメインを削除する。
    func removeDomains(at offsets: IndexSet) {
        blockedDomains.remove(atOffsets: offsets)
    }

    /// 入力文字列をドメイン名だけに正規化する。
    /// 例: "https://x.com/home" -> "x.com"
    static func normalizeDomain(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for scheme in ["https://", "http://"] where value.hasPrefix(scheme) {
            value.removeFirst(scheme.count)
        }
        if let slashIndex = value.firstIndex(of: "/") {
            value = String(value[value.startIndex..<slashIndex])
        }
        // hosts ファイルに書ける文字だけを許可する
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        return value.unicodeScalars.filter { allowed.contains($0) }.map(String.init).joined()
    }
}
