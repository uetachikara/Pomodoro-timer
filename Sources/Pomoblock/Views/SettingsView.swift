import SwiftUI

/// 設定ウィンドウ。タイマー設定とブロック対象の管理を行う。
struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            TimerSettingsTab(settings: model.settings)
                .tabItem { Label("タイマー", systemImage: "timer") }

            BlocklistTab(model: model)
                .tabItem { Label("ブロック対象", systemImage: "hand.raised") }

            GuardTab(model: model)
                .tabItem { Label("常駐ガード", systemImage: "shield") }
        }
        .frame(width: 440, height: 380)
    }
}

/// タイマーの長さと挙動の設定。
private struct TimerSettingsTab: View {
    @Bindable var settings: AppSettings

    private var range: ClosedRange<Int> {
        AppConstants.minimumDurationMinutes...AppConstants.maximumDurationMinutes
    }

    var body: some View {
        Form {
            Section("時間（分）") {
                Stepper("作業: \(settings.workMinutes)", value: $settings.workMinutes, in: range)
                Stepper("小休憩: \(settings.shortBreakMinutes)", value: $settings.shortBreakMinutes, in: range)
                Stepper("長い休憩: \(settings.longBreakMinutes)", value: $settings.longBreakMinutes, in: range)
            }

            Section("進行") {
                Stepper(
                    "長い休憩までの作業回数: \(settings.sessionsUntilLongBreak)",
                    value: $settings.sessionsUntilLongBreak,
                    in: 2...8
                )
                Toggle("次のフェーズを自動で開始する", isOn: $settings.autoStartNextPhase)
                Toggle("フェーズ切り替え時に音を鳴らす", isOn: $settings.playSound)
            }
        }
        .formStyle(.grouped)
    }
}

/// ブロック対象ドメインの編集。
private struct BlocklistTab: View {
    @Bindable var model: AppModel

    @State private var newDomain = ""
    @State private var selection = Set<String>()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("追加するドメイン（例: x.com）", text: $newDomain)
                    .onSubmit(addDomain)
                Button("追加", action: addDomain)
                    .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            List(selection: $selection) {
                ForEach(model.settings.blockedDomains, id: \.self) { domain in
                    Text(domain).monospaced()
                }
            }
            .border(.separator)

            HStack {
                Button("選択を削除", action: removeSelected)
                    .disabled(selection.isEmpty || model.blocker.isLocked)
                Spacer()
                if model.blocker.isLocked {
                    Text("ロック中は現在のリストが適用され続ける")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding()
    }

    private func addDomain() {
        model.settings.addDomain(newDomain)
        newDomain = ""
        model.reapplyCurrentPolicy()
    }

    private func removeSelected() {
        model.settings.blockedDomains.removeAll { selection.contains($0) }
        selection.removeAll()
        model.reapplyCurrentPolicy()
    }
}

/// 常駐ガードの導入・撤去。
private struct GuardTab: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: model.blocker.isGuardInstalled ? "checkmark.shield.fill" : "xmark.shield")
                    .foregroundStyle(model.blocker.isGuardInstalled ? .green : .secondary)
                Text(model.blocker.isGuardInstalled ? "導入済み" : "未導入")
                    .font(.headline)
            }

            Text("""
            常駐ガードは root 権限の LaunchDaemon として動き、/etc/hosts のブロック領域を管理する。
            アプリを終了してもブロックの ON/OFF は維持され、Locked Mode 中は期限まで解除できない。
            """)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                if model.blocker.isGuardInstalled {
                    Button("撤去する") { model.blocker.uninstallGuard() }
                        .disabled(model.blocker.isLocked)
                } else {
                    Button("導入する") { model.blocker.installGuard() }
                        .buttonStyle(.borderedProminent)
                }
                Button("状態を再読み込み") { model.blocker.refresh() }
            }

            if model.blocker.isLocked, let remaining = model.blocker.lockRemainingText {
                Label("ロック中のため撤去できない（\(remaining)）", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let status = model.blocker.lastStatus {
                Label(status, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if let error = model.blocker.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding()
    }
}
