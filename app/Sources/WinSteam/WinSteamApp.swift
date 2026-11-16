import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 直接執行（未組成 .app）時也要有 Dock 圖示與選單列
        NSApp.setActivationPolicy(.regular)
        // 開發用：WINSTEAM_APPEARANCE=dark|light 強制外觀（預設跟隨系統）
        switch ProcessInfo.processInfo.environment["WINSTEAM_APPEARANCE"] {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
    }
}

@main
struct WinSteamApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("WinSteam", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 620, minHeight: 520)
                .task { await model.refresh() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    guard model.loaded, !model.isBusy, !model.checking else { return }
                    Task { await model.refresh() }
                }
        }
        .defaultSize(width: 720, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("操作") {
                Button("進階…") { model.path = [.advanced] }
                    .keyboardShortcut(",", modifiers: [.command, .shift])
                Button("重新檢查") { Task { await model.refresh() } }
                    .keyboardShortcut("r")
                    .disabled(model.checking)
                Divider()
                Button("停止目前的動作") { model.stop() }
                    .keyboardShortcut(".")
                    .disabled(!model.isBusy)
            }
        }
    }
}
