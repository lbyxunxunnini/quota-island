import AppKit
import SwiftUI

@main
struct AIQuotaIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandMenu("额度") {
                    Button("打开刘海详情") { appDelegate.openExpanded() }
                        .keyboardShortcut("o", modifiers: .command)
                    Button("显示 / 隐藏桌面面板") { appDelegate.toggleDesktop() }
                        .keyboardShortcut("d", modifiers: .command)
                }
            }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: QuotaCoordinator?
    private var windows: WindowCoordinator?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let coordinator = QuotaCoordinator(adapters: [CodexAdapter(), OpenCodeGoAdapter(), SparkAdapter()])
        self.coordinator = coordinator
        let windows = WindowCoordinator(coordinator: coordinator)
        self.windows = windows
        windows.showInitialWindows()
        coordinator.start()
        installStatusMenu()
    }

    private func installStatusMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "circle.hexagongrid.fill", accessibilityDescription: "AI 额度")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示 / 隐藏桌面面板", action: #selector(toggleDesktop), keyEquivalent: "d"))
        menu.addItem(NSMenuItem(title: "打开刘海详情", action: #selector(openExpanded), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "立即刷新", action: #selector(refresh), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "显示设置", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        for entry in menu.items { entry.target = self }
        item.menu = menu
        statusItem = item
    }

    @objc func toggleDesktop() { windows?.toggleDesktop() }
    @objc func openExpanded() { windows?.openExpanded() }
    @objc private func refresh() { Task { await coordinator?.refreshAll(force: true) } }
    @objc private func showSettings() { windows?.showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}
