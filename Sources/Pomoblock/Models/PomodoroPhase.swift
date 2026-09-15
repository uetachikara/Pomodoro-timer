import Foundation

/// ポモドーロの進行フェーズ。
enum PomodoroPhase: String, CaseIterable, Sendable {
    /// 停止中
    case idle
    /// 作業中
    case work
    /// 短い休憩
    case shortBreak
    /// 長い休憩
    case longBreak

    /// メニューに表示する名称
    var displayName: String {
        switch self {
        case .idle: "待機中"
        case .work: "作業中"
        case .shortBreak: "小休憩"
        case .longBreak: "長い休憩"
        }
    }

    /// このフェーズでサイトをブロックするか。作業中だけ遮断する。
    var shouldBlock: Bool {
        self == .work
    }

    /// メニューバーに表示する SF Symbols 名
    var symbolName: String {
        switch self {
        case .idle: "timer"
        case .work: "brain.head.profile"
        case .shortBreak: "cup.and.saucer"
        case .longBreak: "figure.walk"
        }
    }
}
