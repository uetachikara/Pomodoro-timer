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

            // 自動化が許可されていない等でタブを操作できない場合に知らせる。
            // これを出さないと「ブロック中なのに見えている」原因が分からない。
            if let warning = model.blocker.tabWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("開いているタブを今すぐ退避") {
                Task { await model.refreshOpenTabs() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

        }
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

            Button(model.loginItem.isEnabled ? "終了（自動復帰）" : "終了") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.link)
            .help(model.loginItem.isEnabled
                ? "自動起動が有効なため、終了しても数秒で起動し直します。"
                : "アプリを終了します。")
        }
        .font(.callout)
    }
}
