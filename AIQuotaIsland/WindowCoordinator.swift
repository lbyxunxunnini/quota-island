import AppKit
import Combine
import CoreGraphics
import SwiftUI

private final class QuotaPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class QuotaPanelHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class WindowCoordinator: NSObject, NSWindowDelegate {
    private let boardScale: CGFloat = 0.75
    private let notchLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
    private let coordinator: QuotaCoordinator
    private var compactLeft: NSPanel?
    private var compactRight: NSPanel?
    private var expanded: NSPanel?
    private var desktop: NSPanel?
    private var credentialWindow: NSWindow?
    private var credentialProvider: UUID?
    private var settingsWindow: NSWindow?
    private var hideTask: Task<Void, Never>?
    private var observers: [AnyCancellable] = []
    private var screenObserver: NSObjectProtocol?

    init(coordinator: QuotaCoordinator) {
        self.coordinator = coordinator
        super.init()
        coordinator.settings.$providers
            .sink { [weak self] _ in
                Task { @MainActor in self?.rebuildCompact() }
            }
            .store(in: &observers)
        coordinator.settings.$desktopVisible
            .sink { [weak self] visible in
                Task { @MainActor in self?.setDesktopVisible(visible) }
            }
            .store(in: &observers)
        coordinator.$states
            .map { states in
                states.mapValues { state in
                    state.snapshot.map { $0.balance == nil && $0.totalQuota == nil && $0.isLargeCard }
                }
            }
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in self?.positionExpanded() }
            }
            .store(in: &observers)
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rebuildCompact(); self?.positionExpanded() }
        }
    }

    func showInitialWindows() {
        rebuildCompact()
        setDesktopVisible(coordinator.settings.desktopVisible)
    }

    func setDesktopVisible(_ visible: Bool) {
        guard visible else { desktop?.orderOut(nil); return }
        if desktop == nil {
            let frame = desktopFrame()
            let panel = makePanel(frame: frame,
                                  level: NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1),
                                  shadow: true)
            panel.title = "AI 额度桌面面板"
            panel.delegate = self
            panel.isMovableByWindowBackground = true
            panel.contentView = QuotaPanelHostingView(rootView: AnyView(board(title: "AI 额度")))
            desktop = panel
        }
        desktop?.orderFrontRegardless()
    }

    func toggleDesktop() {
        coordinator.settings.desktopVisible.toggle()
    }

    func openExpanded() {
        hideTask?.cancel()
        let opening = expanded?.isVisible != true
        if opening { coordinator.didExpand() }
        if expanded == nil {
            let panel = makePanel(frame: expandedFrame(), level: notchLevel, shadow: true)
            panel.title = "AI 额度刘海展开"
            panel.contentView = QuotaPanelHostingView(rootView: AnyView(board(title: "AI 额度详情", expanded: true)
                .onHover { [weak self] inside in
                    if inside { self?.hideTask?.cancel() } else { self?.scheduleHideExpanded() }
                }))
            expanded = panel
        } else {
            positionExpanded()
        }
        expanded?.makeKeyAndOrderFront(nil)
    }

    func scheduleHideExpanded() {
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            let pointer = NSEvent.mouseLocation
            let overQuotaUI = [self.compactLeft, self.compactRight, self.expanded].contains {
                $0?.isVisible == true && $0?.frame.contains(pointer) == true
            }
            if !overQuotaUI { self.expanded?.orderOut(nil) }
        }
    }

    func showCredentialEditor(for provider: UUID) {
        guard let config = coordinator.settings.config(provider), config.provider != .codex else { return }
        if let credentialWindow {
            if credentialProvider == provider {
                credentialWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
            credentialWindow.close()
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 720),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "编辑 \(config.displayName)"
        window.center()
        window.contentView = NSHostingView(rootView: ProviderEditorView(coordinator: coordinator, initial: config, isNew: false) { [weak self] _ in
            self?.credentialWindow?.close()
        })
        window.delegate = self
        window.isReleasedWhenClosed = false
        credentialWindow = window
        credentialProvider = provider
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func showSettings() {
        if let settingsWindow { settingsWindow.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 1000, height: 680)
        window.title = "AI 额度设置"
        window.center()
        window.contentView = NSHostingView(rootView: DisplaySettingsView(coordinator: coordinator, settings: coordinator.settings) { [weak self] in
            self?.settingsWindow?.close()
        })
        window.delegate = self
        window.isReleasedWhenClosed = false
        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === desktop else { return }
        UserDefaults.standard.set([window.frame.origin.x, window.frame.origin.y], forKey: "desktopOrigin")
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === credentialWindow {
            credentialWindow = nil
            credentialProvider = nil
        }
        if window === settingsWindow { settingsWindow = nil }
    }

    private func board(title: String, expanded: Bool = false) -> some View {
        QuotaBoardView(coordinator: coordinator, settings: coordinator.settings,
                       title: title, isExpanded: expanded,
                       onEdit: { [weak self] in self?.showCredentialEditor(for: $0) },
                       onSettingsClick: { [weak self] in self?.showSettings() })
            .frame(width: boardWidth(), height: boardHeight())
            .scaleEffect(boardScale, anchor: .topLeading)
            .frame(width: boardWidth() * boardScale,
                   height: boardHeight() * boardScale,
                   alignment: .topLeading)
    }

    private func rebuildCompact() {
        compactLeft?.orderOut(nil)
        compactRight?.orderOut(nil)
        compactLeft = nil
        compactRight = nil
        let configs = coordinator.settings.compactProviders
        guard !configs.isEmpty else { positionExpanded(); return }
        let sides = LayoutPlanner.compactSides(configs)
        let left = sides.left
        let right = sides.right
        let screen = notchScreen()
        let menuHeight: CGFloat = 38
        let y = screen.frame.maxY - menuHeight

        func add(_ items: [ProviderConfig], leftSide: Bool) -> NSPanel? {
            guard !items.isEmpty else { return nil }
            let width = CGFloat(items.count) * 42 + 6
            let notchEdge = leftSide
                ? (screen.auxiliaryTopLeftArea?.maxX ?? screen.frame.midX - 86)
                : (screen.auxiliaryTopRightArea?.minX ?? screen.frame.midX + 86)
            let x = leftSide ? notchEdge - width - 2 : notchEdge + 2
            let panel = makePanel(frame: NSRect(x: x, y: y, width: width, height: 37), level: notchLevel, shadow: false)
            panel.contentView = QuotaPanelHostingView(rootView: AnyView(CompactNotchView(
                coordinator: coordinator, settings: coordinator.settings, providers: items,
                onOpen: { [weak self] in self?.openExpanded() },
                onLeave: { [weak self] in self?.scheduleHideExpanded() }
            )))
            panel.orderFrontRegardless()
            return panel
        }
        compactLeft = add(left, leftSide: true)
        compactRight = add(right, leftSide: false)
        positionExpanded()
    }

    private func makePanel(frame: NSRect, level: NSWindow.Level, shadow: Bool) -> NSPanel {
        let panel = QuotaPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = shadow
        panel.level = level
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func notchScreen() -> NSScreen {
        NSScreen.screens.first { $0.auxiliaryTopLeftArea != nil && $0.auxiliaryTopRightArea != nil }
            ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func boardHeight() -> CGFloat {
        let visible = coordinator.settings.visibleProviders
        let count = visible.count
        if count == 0 { return 260 }
        if count == 1 { return 352 }
        let pairs = count / 2
        let lastLarge = visible.last.map { config in
            let snapshot = coordinator.states[config.id]?.snapshot
            if snapshot?.balance != nil || snapshot?.totalQuota != nil { return false }
            return config.template != .single
        } ?? false
        let leftover: CGFloat = count.isMultiple(of: 2) ? 0 : (lastLarge ? 184 : 140)
        return min(690, 101 + CGFloat(pairs) * 260 + leftover)
    }

    private func boardWidth() -> CGFloat { coordinator.settings.visibleProviders.count == 1 ? 226 : 450 }

    private func expandedFrame() -> NSRect {
        let screen = notchScreen()
        let height = boardHeight() * boardScale
        let width = boardWidth() * boardScale
        return NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - 39 - height,
                      width: width, height: height)
    }

    private func positionExpanded() {
        if let host = expanded?.contentView as? NSHostingView<AnyView> {
            host.rootView = AnyView(board(title: "AI 额度详情", expanded: true)
                .onHover { [weak self] inside in
                    if inside { self?.hideTask?.cancel() } else { self?.scheduleHideExpanded() }
                })
        }
        expanded?.setFrame(expandedFrame(), display: true)
        let frame = desktopFrame()
        if let host = desktop?.contentView as? NSHostingView<AnyView> {
            host.rootView = AnyView(board(title: "AI 额度"))
        }
        desktop?.setFrame(frame, display: true)
    }

    private func desktopFrame() -> NSRect {
        let screen = notchScreen()
        let width = boardWidth() * boardScale
        let height = boardHeight() * boardScale
        let visible = screen.visibleFrame
        if let values = UserDefaults.standard.array(forKey: "desktopOrigin") as? [CGFloat], values.count == 2 {
            let x = min(max(values[0], visible.minX), visible.maxX - width)
            let y = min(max(values[1], visible.minY), visible.maxY - height)
            return NSRect(x: x, y: y, width: width, height: height)
        }
        return NSRect(x: visible.maxX - width - 24, y: visible.maxY - height - 24,
                      width: width, height: height)
    }
}
