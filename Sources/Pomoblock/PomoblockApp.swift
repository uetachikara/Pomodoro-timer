import AppKit
import SwiftUI

/// アプリのエントリポイント。Dock には出さずメニューバーだけに常駐する。
@main
struct PomoblockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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

/// 多重起動を防ぐ。
///
/// 自動起動を有効にすると launchd が実行ファイルを直接起動するため、
/// Finder や `open` から重ねて起動されるとメニューバーにアイコンが 2 つ並ぶ。
/// 後から起動した側を終了させて 1 つに保つ。
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminateIfDuplicate()
    }

    private func terminateIfDuplicate() {
        let current = NSRunningApplication.current
        let myLaunchDate = current.launchDate ?? Date()

        let hasOlderInstance = NSWorkspace.shared.runningApplications.contains { app in
            guard app.bundleIdentifier == AppConstants.bundleIdentifier,
                  app.processIdentifier != current.processIdentifier
            else { return false }
            // 起動時刻が不明なものは先行しているとみなし、自分が譲る
            guard let otherLaunchDate = app.launchDate else { return true }
            return otherLaunchDate < myLaunchDate
        }

        if hasOlderInstance {
            NSApp.terminate(nil)
        }
    }
}
