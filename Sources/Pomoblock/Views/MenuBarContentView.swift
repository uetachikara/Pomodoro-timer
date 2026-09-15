import SwiftUI

/// メニューバーから開くパネルの中身。
struct MenuBarContentView: View {
    @Bindable var model: AppModel

    /// パネルの横幅
    private let panelWidth: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()

            if model.blocker.isGuardInstalled {
                timerSection
                Divider()
                blockingSection
            } else {
                setupSection
            }

            if let message = model.blocker.lastError {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            footer
        }
        .padding(16)
        .frame(width: panelWidth)
        .onAppear { model.blocker.refresh() }
    }

    // MARK: - 見出し

    private var header: some View {
        HStack {
            Image(systemName: model.engine.phase.symbolName)
                .foregroundStyle(.tint)
            Text(model.engine.phase.displayName)
                .font(.headline)
            Spacer()
            if model.engine.isRunning {
                Text("\(model.engine.completedWorkSessions) / \(model.settings.sessionsUntilLongBreak)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - タイマー

    private var timerSection: some View {
        VStack(spacing: 10) {
            Text(model.engine.remainingText)
                .font(.system(size: 44, weight: .medium, design: .rounded))
                .monospacedDigit()

            ProgressView(value: model.engine.progress)
                .progressViewStyle(.linear)

            HStack(spacing: 8) {
                if model.engine.isRunning {
                    Button(model.engine.isPaused ? "再開" : "一時停止") {
                        model.togglePause()
                    }
                    Button("スキップ") { model.skip() }
                    Button("停止") { model.stop() }
                } else {
                    Button("ポモドーロを開始") { model.start() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - ブロック状態

    private var blockingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: model.blocker.isBlocking ? "lock.fill" : "lock.open")
                    .foregroundStyle(model.blocker.isBlocking ? .red : .secondary)
                Text(model.blocker.isBlocking ? "ブロック中" : "ブロック解除中")
                    .font(.subheadline)
                Spacer()
                Text("\(model.settings.blockedDomains.count) 件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let remaining = model.blocker.lockRemainingText {
                Label("ロック中・\(remaining)", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                HStack(spacing: 8) {
                    Picker("", selection: $model.lockDurationMinutes) {
                        ForEach(AppConstants.lockDurationChoicesMinutes, id: \.self) { minutes in
                            Text(label(forMinutes: minutes)).tag(minutes)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 96)

                    Button("ロックする") { model.lockNow() }
                        .buttonStyle(.bordered)
                    Spacer()
                }
                Text("ロック中はアプリを終了しても再起動してもブロックが続く。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 分数を「1 時間」「30 分」のように整形する。
    private func label(forMinutes minutes: Int) -> String {
        let minutesPerHour = 60
        guard minutes >= minutesPerHour else { return "\(minutes) 分" }
        let hours = minutes / minutesPerHour
        let rest = minutes % minutesPerHour
        return rest == 0 ? "\(hours) 時間" : "\(hours) 時間 \(rest) 分"
    }

    // MARK: - 初回セットアップ

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("常駐ガードが未導入")
                .font(.subheadline.bold())
            Text("サイトを遮断するには /etc/hosts を書き換える常駐ガードが必要。導入時に一度だけ管理者パスワードを求める。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("常駐ガードを導入") { model.blocker.installGuard() }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - フッター

    private var footer: some View {
        HStack {
            SettingsLink {
                Text("設定…")
            }
            .buttonStyle(.link)

            Spacer()

            Button("終了") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.link)
        }
        .font(.callout)
    }
}
