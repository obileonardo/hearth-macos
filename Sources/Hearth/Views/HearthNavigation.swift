import AppKit
import Combine
import SwiftUI

/// Desktop and live-pill links navigate the existing panel, including its
/// Devices subpages, whether the panel has already been constructed or not.
@MainActor
enum HearthNavigation {
    static let pageRequested = Notification.Name("Hearth.pageRequested")
    static let panelVisibilityChanged = Notification.Name("Hearth.panelVisibilityChanged")
    static weak var panel: NSWindow?

    static func open(_ page: String) {
        UserDefaults.standard.set(page, forKey: "page")
        HearthMenuController.shared.open()
        NotificationCenter.default.post(name: pageRequested, object: page)
    }
}

/// Own the menu button and its one anchored panel. Widget links can open this
/// directly without searching private SwiftUI status-window implementation types.
@MainActor
final class HearthMenuController: NSObject {
    static let shared = HearthMenuController()
    private(set) var statusItem: NSStatusItem?
    private var panel: HearthMenuPanel?
    private weak var store: HomeStore?
    private weak var log: ActivityLog?
    private var subscriptions = Set<AnyCancellable>()
    private var ticker: StatusTicker?
    private(set) var windowAction: OpenWindowAction?
    private var statusView: HearthStatusView?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var positioningTimer: Timer?
    private var refreshQueued = false
    private var openingPanel = false
    private var openStatusSlotWidth: CGFloat?
    private var anchorSession = MenuPanelAnchorSession()
    private let layout = HearthPanelLayout()

    var button: NSStatusBarButton? { statusItem?.button }
    var anchorView: NSView? { statusView ?? button }

    /// The drawn capsule, not the status window's reserved slot or extra insets.
    /// Flash notifications follow this live rectangle; an open main panel keeps
    /// its separate opening-anchor session and fixed-width status reservation.
    var liveStatusPillFrame: CGRect? {
        guard let view = statusView, let window = view.window, view.image != nil else { return nil }
        return window.convertToScreen(view.convert(view.imageFrame, to: nil))
    }

    func attach(store: HomeStore, log: ActivityLog) {
        guard statusItem == nil else { return }
        self.store = store
        self.log = log
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "Hearth.status"
        statusItem = item
        let view = HearthStatusView(frame: NSRect(x: 0, y: 0, width: 80,
                                                  height: NSStatusBar.system.thickness))
        view.press = { [weak self] in self?.toggle(nil) }
        view.didFinishMove = { [weak self] in
            guard let self else { return }
            self.anchorSession.reset()
            if self.panel?.isVisible == true { self.positionPanel() }
        }
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel("Hearth")
        item.view = view
        statusView = view
        makePanelIfReady()
        let ticker = StatusTicker()
        self.ticker = ticker
        ticker.$tick.sink { [weak self] _ in self?.requestRefresh() }.store(in: &subscriptions)
        store.objectWillChange.sink { [weak self] _ in self?.requestRefresh() }.store(in: &subscriptions)
        log.objectWillChange.sink { [weak self] _ in self?.requestRefresh() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.requestRefresh() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: AppearanceChoice.didChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyAppearance() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.positionPanel() }.store(in: &subscriptions)
        refresh()
    }

    func captureOpenWindow(_ action: OpenWindowAction) {
        guard windowAction == nil else { return }
        windowAction = action
        makePanelIfReady()
    }

    private func makePanelIfReady() {
        guard panel == nil, let store, let log, windowAction != nil else { return }
        let panel = HearthMenuPanel(contentRect: NSRect(origin: .zero, size: Theme.panelSize),
                                    styleMask: [.borderless, .nonactivatingPanel],
                                    backing: .buffered, defer: false)
        panel.title = "Hearth"
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView:
            HearthPanelSurface(layout: layout).environmentObject(store).environmentObject(log))
        panel.cancel = { [weak self] in self?.close() }
        self.panel = panel
        applyAppearance()
    }

    /// One entity update can invalidate many publishers. Coalesce the resulting
    /// status scans instead of rendering/repositioning repeatedly in one turn.
    private func requestRefresh() {
        guard !refreshQueued else { return }
        refreshQueued = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
            guard let self else { return }
            self.refreshQueued = false
            self.refresh()
        }
    }

    private func applyAppearance() {
        let appearance: NSAppearance? = switch AppearanceChoice.saved {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        panel?.appearance = appearance
        panel?.contentView?.appearance = appearance
        panel?.contentView?.needsDisplay = true
    }

    private func refresh() {
        applyAppearance()
        guard let store, let log, let view = statusView, let item = statusItem else { return }
        let lines = StatusFeed.lines(store: store, log: log)
        let line = lines.first(where: \.urgent) ?? (lines.isEmpty ? nil : lines[(ticker?.tick ?? 0) % lines.count])
        let showsName = UserDefaults.standard.object(forKey: "pill.showsName") as? Bool ?? true
        if openingPanel && openStatusSlotWidth == nil {
            let widths = (lines.map { Optional($0) } + [line]).map {
                MenuBarPill.image(line: $0, showsName: showsName).size.width
            }
            let screenWidth = view.window?.screen?.frame.width ?? NSScreen.main?.frame.width ?? 1024
            openStatusSlotWidth = MenuStatusSlotGeometry.width(imageWidths: widths, screenWidth: screenWidth)
        }
        let image = MenuBarPill.image(line: line, showsName: showsName, maximumWidth: openStatusSlotWidth)
        let slotWidth = openStatusSlotWidth ?? image.size.width
        if view.image !== image { view.image = image }
        if abs(item.length - slotWidth) > 0.5 {
            item.length = slotWidth
            view.setFrameSize(NSSize(width: slotWidth, height: NSStatusBar.system.thickness))
        }
        view.setAccessibilityLabel(line.map { "Hearth, \($0.text)" } ?? "Hearth")
        view.toolTip = line.map { "Hearth · \($0.text)" } ?? "Open Hearth"
        if LivePill.shared.statusLine != line { LivePill.shared.statusLine = line }
        if panel?.isVisible == true { positionPanel() }
        // Width changes are laid out by AppKit after item.length is assigned.
        // Recheck the toast after that layout without moving the main panel.
        DispatchQueue.main.async { LivePill.shared.refreshAnchor() }
    }

    @objc private func toggle(_ sender: Any?) {
        if openingPanel || panel?.isVisible == true { close() } else { open() }
    }

    func open() {
        guard let panel, !openingPanel, !panel.isVisible else { return }
        openingPanel = true
        anchorSession.reset()
        applyAppearance()
        refresh()
        // Let AppKit lay out the reserved status slot before capturing its
        // center. No panel is shown at an intermediate, stale position.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.openingPanel else { return }
            self.positionPanel()
            panel.makeKeyAndOrderFront(nil)
            self.openingPanel = false
            HearthNavigation.panel = panel
            NotificationCenter.default.post(name: HearthNavigation.panelVisibilityChanged, object: true)
            self.installDismissal()
            // Recheck display bounds without following changing status text.
            self.positioningTimer?.invalidate()
            self.positioningTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.positionPanel() }
            }
        }
    }

    func close() {
        openingPanel = false
        openStatusSlotWidth = nil
        anchorSession.reset()
        NotificationCenter.default.post(name: HearthNavigation.panelVisibilityChanged, object: false)
        panel?.orderOut(nil)
        positioningTimer?.invalidate()
        positioningTimer = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        requestRefresh()
    }

    private func positionPanel() {
        guard let anchor = anchorView, let statusWindow = anchor.window, let panel else { return }
        let rect = statusWindow.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        guard let screen = statusWindow.screen ?? NSScreen.screens.first(where: { $0.frame.intersects(rect) }) else { return }
        let stableAnchor = anchorSession.resolve(liveAnchor: rect, screenFrame: screen.frame)
        let frame = MenuPanelGeometry.frame(anchor: stableAnchor, visibleFrame: screen.visibleFrame, panelSize: Theme.panelSize)
        if layout.size != frame.size { layout.size = frame.size }
        if abs(frame.origin.x - panel.frame.origin.x) > 0.5 || abs(frame.origin.y - panel.frame.origin.y) > 0.5 || panel.frame.size != frame.size {
            panel.setFrame(frame, display: true)
        }
    }

    private func installDismissal() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown && event.keyCode == 53 && event.window === self.panel {
                self.close()
                return nil
            }
            if event.type != .keyDown {
                let insidePanel = self.panel?.frame.contains(NSEvent.mouseLocation) == true
                let insideStatus = self.anchorView?.window?.frame.contains(NSEvent.mouseLocation) == true
                var ancestor = event.window
                var child = false
                while let window = ancestor {
                    if window === self.panel { child = true; break }
                    ancestor = window.parent
                }
                // Native popup menus and child popovers belong to the current flow.
                let nativeMenu = event.window.map { $0.level.rawValue >= NSWindow.Level.popUpMenu.rawValue } ?? true
                if !insidePanel && !insideStatus && !child && !nativeMenu { self.close() }
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }
}

@MainActor
private final class HearthPanelLayout: ObservableObject {
    @Published var size = Theme.panelSize
}

private struct HearthPanelSurface: View {
    @ObservedObject var layout: HearthPanelLayout
    var body: some View {
        PanelView()
            .environment(\.hearthPanelSize, layout.size)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.fg.opacity(0.12), lineWidth: 0.5))
    }
}

private struct HearthPanelSizeKey: EnvironmentKey {
    static let defaultValue: CGSize? = nil
}

extension EnvironmentValues {
    var hearthPanelSize: CGSize? {
        get { self[HearthPanelSizeKey.self] }
        set { self[HearthPanelSizeKey.self] = newValue }
    }
}

private final class HearthMenuPanel: NSPanel {
    var cancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { cancel?() }
}

/// Draws exactly one image; there is no NSStatusBarButton bezel or glass layer.
/// Command-drag is passed through to the native status window's responder chain.
private final class HearthStatusView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    var press: (() -> Void)?
    var didFinishMove: (() -> Void)?
    private var movingStatus = false
    private var trackingPress = false

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var imageFrame: CGRect {
        guard let image else { return bounds }
        return CGRect(x: bounds.midX - image.size.width / 2,
                      y: bounds.midY - image.size.height / 2,
                      width: image.size.width, height: image.size.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }
        image.draw(in: imageFrame, from: .zero, operation: .sourceOver,
                   fraction: trackingPress ? 0.88 : 1, respectFlipped: true, hints: nil)
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            movingStatus = true
            trackingPress = false
            super.mouseDown(with: event)
        } else {
            trackingPress = true
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        if movingStatus {
            movingStatus = false
            super.mouseUp(with: event)
            didFinishMove?()
            return
        }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if trackingPress && inside { press?() }
        trackingPress = false
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 { press?() }
        else { super.keyDown(with: event) }
    }

    override func accessibilityPerformPress() -> Bool {
        guard let press else { return false }
        press()
        return true
    }
}

/// Apple's openWindow environment property is read-only. Keep its native action
/// in scene-hosted views and use the captured scene action from AppKit hosts.
struct HearthWindowAction {
    let fallback: OpenWindowAction

    @MainActor func callAsFunction(id: String) {
        (HearthMenuController.shared.windowAction ?? fallback)(id: id)
    }

    @MainActor func callAsFunction<Value: Codable & Hashable>(id: String, value: Value) {
        (HearthMenuController.shared.windowAction ?? fallback)(id: id, value: value)
    }
}

extension EnvironmentValues {
    var hearthOpenWindow: HearthWindowAction { HearthWindowAction(fallback: openWindow) }
}

/// Commands are evaluated in the app's SwiftUI scene environment even before an
/// auxiliary window is opened. This empty group adds no menu item.
struct HearthWindowBridgeCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        let _ = HearthMenuController.shared.captureOpenWindow(openWindow)
        CommandGroup(after: .appInfo) { EmptyView() }
    }
}

struct PanelWindowReader: NSViewRepresentable {
    func makeNSView(context: Context) -> Reader { Reader() }
    func updateNSView(_ view: Reader, context: Context) {}

    final class Reader: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { HearthNavigation.panel = window }
        }
    }
}
