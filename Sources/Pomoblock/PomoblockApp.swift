import SwiftUI

/// アプリのエントリポイント。Dock には出さずメニューバーだけに常駐する。
@main
struct PomoblockApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(model: model)
        } label: {
            // 稼働中は残り時間、待機中はアイコンのみを表示する
            HStack(spacing: 4) {
                Image(systemName: model.engine.phase.symbolName)
                if model.engine.isRunning {
                    Text(model.engine.remainingText)
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}
