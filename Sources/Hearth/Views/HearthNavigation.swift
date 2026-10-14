import AppKit
import Combine
import SwiftUI

/// Desktop and live-pill links navigate the existing panel, including its
/// Devices subpages, whether the panel has already been constructed or not.
@MainActor
enum HearthNavigation {
    static let pageRequested = Notification.Name("Hearth.pageRequested")
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
final class HearthMenuController: NSObject, NSPopoverDelegate {
    static let shared = HearthMenuController()
    private(set) var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private weak var store: HomeStore?
    private weak var log: ActivityLog?
    private var subscriptions = Set<AnyCancellable>()
    private var ticker: StatusTicker?
    private(set) var windowAction: OpenWindowAction?
    private var statusView: HearthStatusView?

    var button: NSStatusBarButton? { statusItem?.button }
    var anchorView: NSView? { statusView ?? button }

    func attach(store: HomeStore, log: ActivityLog) {
        guard statusItem == nil else { return }
        self.store = store
        self.log = log
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "Hearth.status"
        statusItem = item
        // Own the drawing as well as the input. Disabling a button cell's
        // highlight leaves the system's outer glass surface on recent macOS.
        // The public custom-view path displays only our single capsule. It is
        // deprecated in the 26 SDK and restored in 27; supported on our older OSes.
        let view = HearthStatusView(frame: NSRect(x: 0, y: 0, width: 80,
                                                  height: NSStatusBar.system.thickness))
        view.press = { [weak self] in self?.toggle(nil) }
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel("Hearth")
        item.view = view
        statusView = view
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = Theme.panelSize
        popover.delegate = self
        makePanelIfReady()
        let ticker = StatusTicker()
        self.ticker = ticker
        ticker.$tick.sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        // objectWillChange precedes the new values, so read on the next main turn.
        store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }.store(in: &subscriptions)
        log.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        refresh()
    }

    /// Capture the action inside SwiftUI's scene/commands environment, then
    /// use it for actions originating in the AppKit host. Camera, map and setup windows
    /// continue to be created by their original SwiftUI scenes.
    func captureOpenWindow(_ action: OpenWindowAction) {
        guard windowAction == nil else { return }
        windowAction = action
        makePanelIfReady()
    }

    private func makePanelIfReady() {
        guard popover.contentViewController == nil,
              let store, let log, windowAction != nil else { return }
        popover.contentViewController = NSHostingController(rootView:
            PanelView().environmentObject(store).environmentObject(log))
    }

    private func refresh() {
        guard let store, let log, let view = statusView, let item = statusItem else { return }
        let lines = StatusFeed.lines(store: store, log: log)
        let line = lines.first(where: \.urgent) ?? (lines.isEmpty ? nil : lines[(ticker?.tick ?? 0) % lines.count])
        let showsName = UserDefaults.standard.object(forKey: "pill.showsName") as? Bool ?? true
        let image = MenuBarPill.image(line: line, showsName: showsName)
        view.image = image
        item.length = image.size.width
        view.setFrameSize(NSSize(width: image.size.width, height: NSStatusBar.system.thickness))
        view.setAccessibilityLabel(line.map { "Hearth, \($0.text)" } ?? "Hearth")
        view.toolTip = line.map { "Hearth · \($0.text)" } ?? "Open Hearth"
        LivePill.shared.statusLine = line
    }

    @objc private func toggle(_ sender: Any?) {
        if popover.isShown { popover.performClose(sender) } else { open() }
    }

    func open() {
        guard let anchor = anchorView, popover.contentViewController != nil else { return }
        if !popover.isShown {
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
    }
}

/// Draws exactly one image; there is no NSStatusBarButton bezel or glass layer.
/// Command-drag is passed through to the native status window's responder chain.
private final class HearthStatusView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    var press: (() -> Void)?
    private var trackingPress = false

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }
        let rect = NSRect(x: (bounds.width - image.size.width) / 2,
                          y: (bounds.height - image.size.height) / 2,
                          width: image.size.width, height: image.size.height)
        image.draw(in: rect, from: .zero, operation: .sourceOver,
                   fraction: trackingPress ? 0.88 : 1, respectFlipped: true, hints: nil)
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            trackingPress = false
            super.mouseDown(with: event)
        } else {
            trackingPress = true
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
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
