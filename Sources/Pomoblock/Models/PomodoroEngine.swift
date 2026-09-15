import Foundation
import Observation

/// ポモドーロタイマー本体。フェーズの進行と残り時間の管理だけを担当する。
/// サイトのブロック制御は AppModel 側で行う。
@MainActor
@Observable
final class PomodoroEngine {

    /// 現在のフェーズ
    private(set) var phase: PomodoroPhase = .idle

    /// 残り時間（秒）
    private(set) var remaining: TimeInterval = 0

    /// 一時停止中か
    private(set) var isPaused = false

    /// 今回の連続セッションで完了した作業フェーズ数
    private(set) var completedWorkSessions = 0

    /// フェーズが切り替わったときに呼ばれる。ブロック制御と通知の起点。
    var onPhaseChanged: ((PomodoroPhase) -> Void)?

    /// 各フェーズの長さを問い合わせるための設定参照
    private let settings: AppSettings

    /// 現在のフェーズの終了予定時刻。スリープ復帰後もずれないよう時刻で保持する。
    private var deadline: Date?

    /// 表示更新用のタイマー
    private var ticker: Timer?

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// 稼働中（待機中でない）か
    var isRunning: Bool {
        phase != .idle
    }

    /// 残り時間を mm:ss 形式で返す。
    var remainingText: String {
        guard phase != .idle else { return "--:--" }
        let total = max(0, Int(remaining.rounded(.up)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// 現在のフェーズの進捗（0.0〜1.0）
    var progress: Double {
        let total = settings.duration(for: phase)
        guard total > 0 else { return 0 }
        return min(1, max(0, 1 - remaining / total))
    }

    // MARK: - 操作

    /// 作業フェーズから開始する。
    func start() {
        completedWorkSessions = 0
        transition(to: .work)
    }

    /// 一時停止する。残り時間はそのまま保持する。
    func pause() {
        guard isRunning, !isPaused else { return }
        isPaused = true
        remaining = deadline?.timeIntervalSinceNow ?? remaining
        deadline = nil
        stopTicker()
    }

    /// 一時停止から再開する。
    func resume() {
        guard isRunning, isPaused else { return }
        isPaused = false
        deadline = Date().addingTimeInterval(remaining)
        startTicker()
    }

    /// 完全に停止して待機中に戻す。
    func stop() {
        completedWorkSessions = 0
        transition(to: .idle)
    }

    /// 現在のフェーズを飛ばして次へ進む。
    func skip() {
        guard isRunning else { return }
        advanceToNextPhase()
    }

    // MARK: - 内部処理

    /// 指定フェーズへ遷移し、タイマーを張り直す。
    private func transition(to next: PomodoroPhase) {
        phase = next
        isPaused = false

        if next == .idle {
            remaining = 0
            deadline = nil
            stopTicker()
        } else {
            remaining = settings.duration(for: next)
            deadline = Date().addingTimeInterval(remaining)
            startTicker()
        }

        onPhaseChanged?(next)
    }

    /// 現在のフェーズを完了扱いにして、次のフェーズを決める。
    private func advanceToNextPhase() {
        switch phase {
        case .work:
            completedWorkSessions += 1
            let needsLongBreak = completedWorkSessions % settings.sessionsUntilLongBreak == 0
            transition(to: needsLongBreak ? .longBreak : .shortBreak)
        case .shortBreak, .longBreak:
            transition(to: .work)
        case .idle:
            break
        }

        // 自動継続が無効なら、次フェーズは開始直後に一時停止して待たせる
        if !settings.autoStartNextPhase, phase != .idle {
            pause()
        }
    }

    private func startTicker() {
        stopTicker()
        let timer = Timer.scheduledTimer(withTimeInterval: AppConstants.tickInterval, repeats: true) { [weak self] _ in
            // メインランループ上で発火するため、メインアクター隔離を前提にしてよい
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        // メニュー操作中もタイマーを止めないよう common モードで登録する
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    /// 1 秒ごとの更新。残り時間が尽きたら次フェーズへ進む。
    private func tick() {
        guard let deadline else { return }
        remaining = deadline.timeIntervalSinceNow
        if remaining <= 0 {
            advanceToNextPhase()
        }
    }
}
