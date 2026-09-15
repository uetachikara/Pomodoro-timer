import AppKit
import Foundation
import Observation
import UserNotifications

/// タイマーとブロック制御をつなぐ調停役。
/// 「作業中はブロック、休憩中は解除」という方針をここだけで決める。
@MainActor
@Observable
final class AppModel {

    let settings: AppSettings
    let engine: PomodoroEngine
    let blocker: BlockController

    /// ロック時間の選択値（分）
    var lockDurationMinutes = AppConstants.defaultLockDurationMinutes

    init() {
        let settings = AppSettings()
        self.settings = settings
        self.engine = PomodoroEngine(settings: settings)
        self.blocker = BlockController()

        engine.onPhaseChanged = { [weak self] phase in
            self?.handlePhaseChange(phase)
        }

        requestNotificationPermission()
    }

    // MARK: - フェーズ変化への追従

    /// フェーズが変わったらブロック状態を合わせ、ユーザーへ知らせる。
    private func handlePhaseChange(_ phase: PomodoroPhase) {
        applyBlockingPolicy(for: phase)
        notifyPhaseChange(phase)
        if settings.playSound {
            NSSound(named: phase == .work ? "Ping" : "Glass")?.play()
        }
    }

    /// 作業中だけブロックする。
    /// ロック中はガード側が期限まで強制ブロックするため、ここでの解除要求は効かない。
    private func applyBlockingPolicy(for phase: PomodoroPhase) {
        blocker.setBlocking(phase.shouldBlock, domains: settings.blockedDomains)
    }

    /// 設定変更を即座に反映する。ブロック中にドメインを足した場合に使う。
    func reapplyCurrentPolicy() {
        applyBlockingPolicy(for: engine.phase)
    }

    // MARK: - 操作

    func start() {
        engine.start()
    }

    func stop() {
        engine.stop()
    }

    func togglePause() {
        engine.isPaused ? engine.resume() : engine.pause()
    }

    func skip() {
        engine.skip()
    }

    /// 選択中の時間だけブロックをロックする。
    func lockNow() {
        let expiry = Date().addingTimeInterval(TimeInterval(lockDurationMinutes * 60))
        blocker.lock(until: expiry, domains: settings.blockedDomains)
    }

    // MARK: - 通知

    private func requestNotificationPermission() {
        // 未署名ビルドでは失敗しうるため、結果は無視して音での通知にフォールバックする
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notifyPhaseChange(_ phase: PomodoroPhase) {
        guard phase != .idle else { return }

        let content = UNMutableNotificationContent()
        content.title = phase.displayName + "を開始します"
        content.body = switch phase {
        case .work: "サイトをブロックしました。集中しましょう。"
        case .shortBreak, .longBreak: "ブロックを解除しました。離席して休みましょう。"
        case .idle: ""
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
