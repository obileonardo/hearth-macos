import SwiftUI
import UserNotifications

@main
struct HearthApp: App {
    @NSApplicationDelegateAdaptor private var app: AppDelegate

    var body: some Scene {
        // A headless menu scene keeps this a menu-only SwiftUI app on macOS 14.
        // The actual status item and its popover are owned by HearthMenuController.
        MenuBarExtra("Hearth", systemImage: "house", isInserted: .constant(false)) { EmptyView() }
            .commands { HearthWindowBridgeCommands() }

        Window("Familiar faces", id: "faces") {
            FacesWindow().environmentObject(app.log)
        }
        .defaultSize(width: 480, height: 640)

        WindowGroup(id: "camera", for: String.self) { $entityID in
            if let entityID {
                CameraWindow(entityID: entityID).environmentObject(app.store)
            }
        }
        .defaultSize(width: 720, height: 450)

        // Home Assistant's setup drawn natively, and its own pages signed in (HAAdminViews, HAWebWindow).
        Window("Home Assistant", id: "ha-admin") {
            HAAdminWindow().environmentObject(app.store)
        }
        .defaultSize(width: 980, height: 680)

        Window("Home Assistant pages", id: "homeassistant") {
            HAWebWindow().environmentObject(app.store)
        }
        .defaultSize(width: 1100, height: 760)

        WindowGroup("3D map", id: "map") {
            MapWindow().environmentObject(app.store)
        }
        .defaultSize(width: 1180, height: 760)
    }
}

/// The app's own menu bar glyph, rendered once as a template image so macOS tints it.
@MainActor
enum MenuBarIcon {
    static let image: NSImage = {
        let renderer = ImageRenderer(content: MenuBarGlyph(size: 18).foregroundStyle(.black))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "house", accessibilityDescription: nil)!
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    @MainActor let store = HomeStore()
    @MainActor let log = ActivityLog()
    private var debugWindow: NSWindow?
    private var pendingWidgetPage: String?

    @MainActor
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let page = urls.compactMap(HearthWidgetLink.destination).last else { return }
        if HearthMenuController.shared.anchorView == nil { pendingWidgetPage = page }
        else { HearthNavigation.open(page) }
    }

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Offline previews exit before sign-in, notifications or device subscriptions.
        if let i = CommandLine.arguments.firstIndex(of: "--render-preview"), i + 1 < CommandLine.arguments.count {
            do { try PreviewExporter.export(to: CommandLine.arguments[i + 1]) }
            catch { fputs("Hearth preview failed: \(error.localizedDescription)\n", stderr); exit(1) }
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--render-cars"), i + 1 < CommandLine.arguments.count {
            CarSheet.export(to: CommandLine.arguments[i + 1])
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--render-art"), i + 1 < CommandLine.arguments.count {
            ArtExporter.export(to: CommandLine.arguments[i + 1])
            exit(0)
        }
        // Settings: Appearance, or `-appearance light|dark` for renders while building.
        if let forced = UserDefaults.standard.string(forKey: "appearance").flatMap(AppearanceChoice.init(rawValue:)),
           CommandLine.arguments.contains("-appearance") {
            forced.apply()
        } else {
            AppearanceChoice.saved.apply()
        }
        _ = AccessibilityDisplay.shared

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        log.attach(store)
        store.onStateChange = { [weak self] new, old in
            self?.log.handle(new, old)
            LivePill.shared.handle(new, old)
        }
        store.onConnected = { [weak self] in Task { await self?.log.backfill() } }
        store.connect()
        HearthMenuController.shared.attach(store: store, log: log)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { MenuBarPill.styleStatusButton() }
        LivePill.shared.attach(store: store, log: log)
        DesktopWidgets.shared.attach(store: store, log: log)
        WidgetSnapshotPublisher.shared.attach(store: store, log: log)
        if let page = pendingWidgetPage {
            pendingWidgetPage = nil
            DispatchQueue.main.async { HearthNavigation.open(page) }
        }

        // `-demoPill doorbell|person|charge|alarm|climate` drops the Live pill with a sample, for checking it.
        if let demo = UserDefaults.standard.string(forKey: "demoPill") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                guard let self else { return }
                let picture = self.log.items.first { $0.imageFile != nil && [.person, .doorbell].contains($0.kind) }?.imageFile
                let event: PillEvent = switch demo {
                case "person":
                    PillEvent(kind: .people, place: "Kitchen", detail: "Someone's here", symbol: "person.fill", tint: Theme.sand,
                              imagePath: picture, page: "security", actionSymbol: "video.fill", actionLabel: "See cameras")
                case "charge":
                    PillEvent(kind: .vehicles, place: "Model Y", detail: "Finished charging", symbol: "bolt.car.fill", tint: Theme.ok,
                              page: "vehicles", actionSymbol: "car.side.fill", actionLabel: "See vehicles")
                case "alarm":
                    PillEvent(kind: .alarm, place: "Home", detail: "The alarm is going off", symbol: "exclamationmark.shield.fill",
                              tint: Theme.live, page: "security", actionSymbol: "video.fill", actionLabel: "See cameras", urgent: true)
                case "climate":
                    PillEvent(kind: .climate, place: "Workspace", detail: "Reached 24°", symbol: "snowflake", tint: Theme.air("cool"),
                              page: "climate", actionSymbol: "thermometer.medium", actionLabel: "Open climate")
                default:
                    PillEvent(kind: .doorbell, place: "Front Door", detail: "Someone's at the door", symbol: "bell.fill", tint: Theme.sand,
                              imagePath: picture, page: "security", actionSymbol: "video.fill", actionLabel: "See the door", urgent: true)
                }
                LivePill.shared.present(event, force: true)
            }
        }

        // `--probe "<steps>"` checks the real Home Assistant through this connection, then quits.
        if let i = CommandLine.arguments.firstIndex(of: "--probe"), i + 1 < CommandLine.arguments.count {
            DebugProbe.run(CommandLine.arguments[i + 1], store: store)
        }

        // `--window` shows the panel in an ordinary window, for screenshots while building.
        if CommandLine.arguments.contains("--window") {
            let open = UserDefaults.standard.string(forKey: "open")
            let host = NSHostingView(rootView: PanelView(page: open).environmentObject(store).environmentObject(log))
            let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: Theme.panelSize.width, height: Theme.panelSize.height),
                                  styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.title = "Hearth"
            window.contentView = host
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            debugWindow = window
            snapshotForDebugging(climate: open)
            // `-scrollBy 600` scrolls the page after it loads, to check what pins while scrolling.
            let scrollBy = UserDefaults.standard.double(forKey: "scrollBy")
            if scrollBy != 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    func find(_ v: NSView) -> NSScrollView? { (v as? NSScrollView) ?? v.subviews.lazy.compactMap(find).first }
                    guard let scroll = window.contentView.flatMap(find) else { return }
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: scrollBy))
                    scroll.reflectScrolledClipView(scroll.contentView)
                }
            }
        }

        // `--map-window` opens the full 3D map on its own, for screenshots while building.
        if CommandLine.arguments.contains("--map-window") {
            let window = NSWindow(contentRect: NSRect(x: 160, y: 120, width: 1180, height: 760),
                                  styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.title = "3D map"
            window.contentView = NSHostingView(rootView: MapWindow().environmentObject(store))
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            debugWindow = window
        }

        // `--ha-admin <section>` and `--ha-web` open those windows on their own, for checking them.
        if let section = LiveDebug.value(after: "--ha-admin") {
            HAAdmin.shared.section = HAAdmin.Section(rawValue: section) ?? .integrations
            let window = NSWindow(contentRect: NSRect(x: 160, y: 120, width: 980, height: 680),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Home Assistant"
            window.contentView = NSHostingView(rootView: HAAdminWindow().environmentObject(store))
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            debugWindow = window
        }
        if CommandLine.arguments.contains("--ha-web") {
            let window = NSWindow(contentRect: NSRect(x: 160, y: 120, width: 1100, height: 760),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Home Assistant pages"
            window.contentView = NSHostingView(rootView: HAWebWindow().environmentObject(store))
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            debugWindow = window
        }

        // `--map-panel` shows the panel's map page on its own, at the panel's size.
        if CommandLine.arguments.contains("--map-panel") {
            let page = ScrollView { MapPage(shown: true, visible: true).padding(22) }
                .frame(width: Theme.panelSize.width, height: Theme.panelSize.height)
                .background(Theme.base)
                .foregroundStyle(Theme.ink)
                .environmentObject(store)
            let window = NSWindow(contentRect: NSRect(x: 220, y: 160, width: Theme.panelSize.width, height: Theme.panelSize.height),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Map panel"
            window.contentView = NSHostingView(rootView: page)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            debugWindow = window
        }

        // `--live <entity_id>` shows one camera's LiveVideoView on its own. See LiveDebug.
        if let camera = LiveDebug.value(after: "--live") {
            let view = LiveVideoView(entityID: camera) { LiveDebug.log("onState \($0)") }.environmentObject(store)
            let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 640, height: 360),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = camera
            window.contentView = NSHostingView(rootView: view)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            debugWindow = window
        }
    }

    /// `--snapshot <path>` renders the panel to a PNG a few seconds after launch,
    /// so the design can be checked without screen recording permission.
    @MainActor
    private func snapshotForDebugging(climate: String?) {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        let path = args[i + 1]
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            let scheme: ColorScheme = NSApp.effectiveAppearance.isDark ? .dark : .light
            let renderer = ImageRenderer(content: PanelView(page: climate).environmentObject(store).environmentObject(log)
                .environment(\.colorScheme, scheme))
            renderer.scale = 2
            guard let cg = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
                NSLog("Hearth: snapshot failed")
                return
            }
            try? png.write(to: URL(fileURLWithPath: path))
            NSLog("Hearth: snapshot written to \(path)")
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound] }
}
