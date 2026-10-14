import ServiceManagement
import SwiftUI

/// What the dock can show: one page per air conditioner, then security, then everything else.
enum Page: Hashable {
    case climate(String)
    case security
    case rooms
    /// Energy, vehicles and gadgets, behind one tab.
    case devices
    case map
    case media
    case activity

    var key: String {
        switch self {
        case .climate(let id): id
        case .security: "security"
        case .rooms: "rooms"
        case .devices: "devices"
        case .map: "map"
        case .media: "media"
        case .activity: "activity"
        }
    }
}

/// The panel that drops down from the menu bar. It keeps one fixed size, so moving
/// between devices never resizes the window or leaves gaps.
struct PanelView: View {
    @EnvironmentObject var store: HomeStore
    @EnvironmentObject var log: ActivityLog
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.hearthPanelSize) private var nativePanelSize
    @AppStorage("page") private var savedPage = ""
    @State private var showSettings = UserDefaults.standard.bool(forKey: "openSettings")
    @State private var shown = false
    /// Whether the panel is on screen; live video only runs while it is.
    @State private var visible = true
    @State private var roomPath: [RoomRoute] = []
    @StateObject private var hub: DevicesHub

    init(page: String? = nil) {
        if let page { UserDefaults.standard.set(page, forKey: "page") }
        // Energy, Vehicles and Gadgets used to be tabs of their own; a saved one opens the Devices tab on it.
        let hub = DevicesHub()
        // Now playing joined them as Speakers.
        if UserDefaults.standard.string(forKey: "page") == "media" { UserDefaults.standard.set("speakers", forKey: "page") }
        if let saved = UserDefaults.standard.string(forKey: "page"), let section = DeviceSection(rawValue: saved) {
            if hub.section == nil { hub.section = section }
            UserDefaults.standard.set(Page.devices.key, forKey: "page")
        }
        if hub.section != nil, UserDefaults.standard.string(forKey: "demo") != nil {
            UserDefaults.standard.set(Page.devices.key, forKey: "page")
        }
        _hub = StateObject(wrappedValue: hub)
        // Development: `-openDevice <id>` opens a device page in the Rooms tab.
        if CommandLine.arguments.contains("-openDevice"), let device = UserDefaults.standard.string(forKey: "openDevice") {
            UserDefaults.standard.set("rooms", forKey: "page")
            _roomPath = State(initialValue: [.device(device)])
        }
        // Snapshots render once, with no time for the entrance to play.
        _shown = State(initialValue: Self.snapshotMode)
    }

    // MARK: What's in the house

    private func visible(_ domains: Set<String>) -> [Entity] {
        store.entities.values
            .filter { domains.contains($0.domain) }
            .filter { e in
                guard let reg = store.registry[e.id] else { return true }
                return !reg.hidden && reg.category == nil
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Air conditioners and heating. A car's cabin climate belongs on its Vehicles card, not as a page.
    private var climates: [Entity] {
        visible(["climate"]).filter { e in
            guard let id = store.registry[e.id]?.deviceID, let device = store.homeDevice(id) else { return true }
            return !DeviceKind.vehicles.contains(device.kind)
        }
    }
    private var alarms: [Entity] { visible(["alarm_control_panel"]) }
    private var cameras: [Entity] { visible(["camera"]) }
    /// Every speaker and player Home Assistant knows about.
    private var players: [Entity] { visible(["media_player"]) }
    /// Sections turned off in Settings, by key.
    @AppStorage("hiddenSections") private var hiddenSections = ""
    private var pages: [Page] {
        var hidden = Set(hiddenSections.split(separator: ",").map(String.init))
        // Settings from before the Devices tab: all three hidden meant none of them wanted.
        if Set(DeviceSection.allCases.map(\.rawValue)).isSubset(of: hidden) { hidden.insert(Page.devices.key) }
        let all: [Page] = climates.map { .climate($0.id) }
            + (alarms.isEmpty && cameras.isEmpty ? [] : [.security])
            + (store.devices.isEmpty ? [] : [.rooms])
            + [.devices]
            + [.map]
            + [.activity]
        let shown = all.filter { !hidden.contains($0.key) }
        return shown.isEmpty ? all : shown
    }

    private var page: Page? { pages.first { $0.key == savedPage } ?? pages.first }

    /// The light in the room: the running AC's air colour, or nothing.
    private var ambient: (Color, Double) {
        if case .climate(let id) = page, let e = store.entities[id] {
            let c = Climate(e: e)
            return (Theme.air(c.mode), c.on ? 1 : 0)
        }
        return (.white, 0)
    }

    private enum SurfaceRoute: Equatable {
        case settings
        case page(Page)
        case empty
    }

    private var surfaceRoute: SurfaceRoute {
        if showSettings || store.status == .needsSetup || store.status == .rejected { return .settings }
        if let page { return .page(page) }
        return .empty
    }

    // MARK: Layout

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                ScreenFlow(route: surfaceRoute, depth: surfaceRoute == .settings ? 1 : 0) { surface in
                    switch surface {
                    case .settings:
                        scrolling { SettingsView { showSettings = false } }
                    case .page(let page):
                        content(page).id(page.key)
                    case .empty:
                        emptyState
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // Text and controls end above the dock, at full contrast. A
                // gradient over the timeline was dimming entire readable rows.
                .clipped()
                .padding(.bottom, Self.footerHeight + 8)
            }
            .overlay(alignment: .bottom) { footer }
        }
        .frame(width: nativePanelSize?.width ?? Theme.panelSize.width,
               height: Self.snapshotHeight ?? nativePanelSize?.height ?? Theme.panelSize.height)
        // Figures that change (temperatures, watts, times) keep their width, so nothing jitters.
        .monospacedDigit()
        .foregroundStyle(Theme.ink)
        .modifier(HearthAppearancePreference())
        .background(PanelWindowReader())
        .alert("Couldn’t complete action", isPresented: Binding(
            get: { store.actionError != nil },
            set: { if !$0 { store.actionError = nil } }
        )) {
            Button("OK") { store.actionError = nil }
        } message: {
            Text(store.actionError ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: HearthNavigation.pageRequested)) { note in
            guard let requested = note.object as? String else { return }
            showSettings = false
            if let section = DeviceSection(rawValue: requested) {
                hub.open(section)
                savedPage = Page.devices.key
            } else {
                savedPage = requested
            }
        }
        .onAppear(perform: replayEntrance)
        // `-cycleTabs YES` walks the dock on its own, for checking how the lens moves.
        .task {
            guard UserDefaults.standard.bool(forKey: "cycleTabs") else { return }
            let jumps = [0, 3, 1, 5, 2, 0]
            for j in jumps.cycled() {
                try? await Task.sleep(for: .seconds(1.6))
                guard pages.indices.contains(j) else { continue }
                savedPage = pages[j].key
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            // Widget windows must not replay or suspend the menu panel's content.
            if let window = note.object as? NSWindow, window === HearthNavigation.panel {
                if !visible { replayEntrance() }
                visible = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: HearthNavigation.panelVisibilityChanged)) { note in
            guard let onscreen = note.object as? Bool else { return }
            if onscreen && !visible { replayEntrance() }
            visible = onscreen
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { note in
            if let window = note.object as? NSWindow, window === HearthNavigation.panel, !window.isVisible { visible = false }
        }
    }

    private func replayEntrance() {
        guard !Self.snapshotMode else { return }
        shown = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { shown = true }
    }

    @ViewBuilder
    private func content(_ page: Page) -> some View {
        switch page {
        case .climate(let id):
            ClimatePage(entityID: id, shown: shown)
        case .security:
            scrolling { SecurityPage(alarms: alarms, cameras: cameras, shown: shown, visible: visible) }
        case .rooms:
            scrolling { RoomsPage(shown: shown, path: $roomPath) }
        case .devices:
            scrolling { DevicesPage(hub: hub, shown: shown, visible: visible) }
                .overlay(alignment: .bottom) { DemoPill(hub: hub) }
                .animation(.glide, value: hub.demo == nil)
        case .map:
            scrolling { MapPage(shown: shown, visible: visible) }
        case .media:
            scrolling { MediaPage(players: players, shown: shown) }
        case .activity:
            scrolling { ActivityPage(shown: shown) }
        }
    }

    @ViewBuilder
    private func scrolling<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if Self.snapshotMode {
            content()
        } else {
            ScrollView { content().padding(.bottom, 8) }
                .scrollIndicators(.never)
                .coordinateSpace(name: PinnedTitleBar.space)
                .overlayPreferenceValue(PinnedTitleKey.self, alignment: .top) { PinnedTitleBar(info: $0) }
        }
    }

    /// The dock's band at the bottom; pages leave this much room so their last row can scroll clear.
    static let footerHeight: CGFloat = 64

    /// Image snapshots can't draw scroll views, so `--snapshot` lays pages out flat.
    private static let snapshotMode = CommandLine.arguments.contains("--snapshot")
    /// `-snapshotHeight 1400` makes a snapshot tall enough to show a whole page.
    private static let snapshotHeight: CGFloat? = snapshotMode
        ? (UserDefaults.standard.double(forKey: "snapshotHeight")).nonZero : nil

    private var background: some View {
        let (glow, strength) = ambient
        // On paper the colour of the air is deeper, so its spill is kept gentler, and the grain finer.
        let light = colorScheme == .light
        return ZStack {
            Theme.base
            // Light spilling from the unit, and a cooler pool where the air settles.
            RadialGradient(colors: [glow.opacity((light ? 0.12 : 0.22) * strength), .clear], center: UnitPoint(x: 0.5, y: 0.2),
                           startRadius: 0, endRadius: 280)
            RadialGradient(colors: [glow.opacity((light ? 0.05 : 0.08) * strength), .clear], center: UnitPoint(x: 0.5, y: 0.62),
                           startRadius: 0, endRadius: 220)
            LinearGradient(colors: [light ? Color.white.opacity(0.55) : Theme.fg.opacity(0.035), .clear], startPoint: .top, endPoint: .center)
            Image(nsImage: Grain.image)
                .resizable(resizingMode: .tile)
                .opacity(light ? 0.025 : 0.05)
                .blendMode(.overlay)
                .allowsHitTesting(false)
        }
        .animation(.glide, value: strength)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(eyebrow: "Hearth", title: "Nothing here yet") { EmptyView() }
            Text("Connect a brand in Home Assistant, under Settings, Devices and services, and it appears here.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .reveal(shown, 0)
    }

    // MARK: Footer and dock

    private var footer: some View {
        // Everything in one pill: the pages, then settings after a hairline, with the
        // connection shown as a small light on the gear.
        Dock(pages: pages.count > 1 ? pages : [], selected: showSettings ? nil : page,
             badge: { $0 == .activity ? log.unread : 0 }, label: label(for:),
             settingsOn: showSettings, status: connection,
             onSettings: { withAnimation(.settle) { showSettings.toggle() } }) { p in
            withAnimation(.glide) {
                if showSettings { showSettings = false }
                // Tapping Rooms again goes back to all rooms.
                if p == .rooms, page == .rooms { roomPath.removeAll() }
                if p == .devices, page == .devices { hub.showGrid() }
                savedPage = p.key
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.footerHeight)
        .padding(.horizontal, 18)
    }

    /// How the link to Home Assistant is doing, for the light on the gear.
    private var connection: (color: Color, text: String) {
        switch store.status {
        case .connected: store.inFlight > 0 ? (Theme.sand, "Syncing") : (Theme.ok, "Live")
        case .connecting: (Theme.sand, "Connecting")
        case .needsSetup: (Theme.faint, "Not set up")
        case .rejected: (Theme.live, "Token not accepted")
        case .failed: (Theme.live, "Can't reach Home Assistant")
        }
    }

    private func label(for page: Page) -> (symbol: String, title: String) {
        switch page {
        case .climate(let id):
            let e = store.entities[id]
            let on = e.map { Climate(e: $0).on } ?? false
            return (on ? "air.conditioner.horizontal.fill" : "air.conditioner.horizontal",
                    Climate.shortName(e?.name ?? "AC"))
        case .security: return ("video", "Security")
        case .rooms: return ("square.grid.2x2", "Rooms")
        case .devices: return ("powerplug", "Devices")
        case .map: return ("cube.transparent", "3D map")
        case .media:
            let playing = players.contains { $0.state == "playing" }
            return (playing ? "music.note" : "hifispeaker", "Playing")
        case .activity: return ("bell", "Activity")
        }
    }
}

/// A floating glass island: icons for every page, the current one opening into a labelled pill.
// MARK: Settings

private enum SettingsRoute: Equatable {
    case settings, account, help
}

struct SettingsView: View {
    @EnvironmentObject var store: HomeStore
    /// Offline guides can render either state without evaluating the Keychain-backed store.
    var previewSignedIn: Bool? = nil
    var onDone: () -> Void
    @State private var url = UserDefaults.standard.string(forKey: "ha.url") ?? "http://localhost:8123"
    @State private var username = UserDefaults.standard.string(forKey: "ha.username") ?? ""
    @State private var password = ""
    @State private var working = false
    @State private var problem: String?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("camera.refresh") private var refresh = 60.0

    private var signedIn: Bool { previewSignedIn ?? (store.isSignedIn && store.status != .rejected) }
    /// Existing Account renders remain available; Help can be rendered with `-openHelp YES`.
    @State private var route: SettingsRoute = UserDefaults.standard.bool(forKey: "openHelp") ? .help
        : UserDefaults.standard.bool(forKey: "openAccount") ? .account : .settings

    private var activeRoute: SettingsRoute { route == .account && !signedIn ? .settings : route }

    var body: some View {
        ScreenFlow(route: activeRoute, depth: activeRoute == .settings ? 0 : 1) { destination in
            switch destination {
            case .account:
                AccountPage { route = .settings }
            case .help:
                HelpAndSupport { route = .settings }
            case .settings:
                settings
            }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(eyebrow: "Hearth", title: signedIn ? "Settings" : "Sign in") { EmptyView() }

            if let note = problem ?? (store.status == .rejected ? "Home Assistant signed Hearth out. Sign in again." : nil) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.circle").font(.system(size: 14, weight: .light)).foregroundStyle(Theme.live)
                    Text(note).font(.system(size: 13, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.live.opacity(0.1))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.live.opacity(0.25), lineWidth: 0.75)))
                .transition(.dissolve)
            }

            if signedIn {
                // Opens the live Account page: who's signed in, the server, integrations and more.
                Button { withAnimation(.glide) { route = .account } } label: {
                    Bezel(radius: 18, inset: 3) {
                        HStack(spacing: 10) {
                            PulseDot(color: Theme.ok, size: 6, live: store.status == .connected)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(username.isEmpty ? "Signed in" : "Signed in as \(username)").font(.system(size: 13, weight: .semibold))
                                Text("Account, server and integrations").font(.system(size: 12)).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.faint)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 50)
                    }
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Account, server and integrations")
            } else {
                LabeledField(label: "Home Assistant address", placeholder: "http://homeassistant.local:8123", text: $url)
                LabeledField(label: "Username", placeholder: "The one you use for Home Assistant", text: $username, contentType: .username)
                LabeledField(label: "Password", placeholder: "Password", text: $password, secure: true, contentType: .password, onSubmit: signIn)
                signInButton.frame(maxWidth: .infinity, alignment: .trailing)
            }

            Button { route = .help } label: {
                Bezel(radius: 18, inset: 3) {
                    HStack(spacing: 10) {
                        Image(systemName: "questionmark.circle").font(.system(size: 18, weight: .light))
                            .foregroundStyle(Theme.muted).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Help & Support").font(.system(size: 13, weight: .semibold))
                            Text("Get help or report a problem").font(.system(size: 12)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.faint)
                    }
                    .padding(.horizontal, 12).frame(height: 50)
                }
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Help and Support")

            Bezel(radius: 18, inset: 3) {
                HStack {
                    Text("Refresh camera pictures").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Button {
                        PopupMenu.show(["30", "60", "90", "120"], selected: String(Int(refresh)), label: { "Every \($0) seconds" }) { refresh = Double($0) ?? 60 }
                    } label: {
                        Text("Every \(Int(refresh))s").font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(Theme.fg.opacity(0.07)))
                    }
                    .buttonStyle(PressStyle())
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
            }

            AppearanceSettings()

            MenuBarSettings()

            // The menu bar pill, the Live pill and desktop widgets (LivePill.swift, DesktopWidgets.swift).
            PillAndWidgetSettings()

            SectionSettings()

            FacesSettingsRow()

            Bezel(radius: 18, inset: 3) {
                HStack {
                    Text("Open at login").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Toggle("Open at login", isOn: $launchAtLogin).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
            }
            .onChange(of: launchAtLogin) { _, on in
                do {
                    if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }

            Button { NSApp.terminate(nil) } label: {
                Text("Quit Hearth").font(.system(size: 13, weight: .medium)).underline()
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 12).frame(height: 24)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Quit Hearth")
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
            .padding(.bottom, 10)
        }
        .animation(.glide, value: problem)
        .animation(.glide, value: signedIn)
    }

    private var signInButton: some View {
        Button(action: signIn) {
            HStack(spacing: 10) {
                Text(working ? "Signing in" : "Sign in").font(.system(size: 13.5, weight: .semibold))
                ZStack {
                    if working {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.right").font(.system(size: 11.5, weight: .semibold))
                    }
                }
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.onCTA.opacity(0.1)))
            }
            .foregroundStyle(Theme.onCTA)
            .padding(.leading, 16).padding(.trailing, 4)
            .frame(height: 30)
            .background(Capsule().fill(Theme.cta))
        }
        .buttonStyle(PressStyle())
        .disabled(working || username.isEmpty || password.isEmpty)
        .opacity(username.isEmpty || password.isEmpty ? 0.5 : 1)
    }

    private func signIn() {
        guard !username.isEmpty, !password.isEmpty, !working else { return }
        working = true
        problem = nil
        Task {
            do {
                try await store.signIn(url: url, username: username, password: password)
                UserDefaults.standard.set(username, forKey: "ha.username")
                password = ""
                onDone()
            } catch let error as ProviderError {
                problem = error.message
            } catch {
                problem = "Couldn't reach Home Assistant at that address."
            }
            working = false
        }
    }
}

private extension Double {
    var nonZero: CGFloat? { self == 0 ? nil : CGFloat(self) }
}

private extension Array {
    /// The elements over and over.
    func cycled() -> AnySequence<Element> {
        AnySequence { () -> AnyIterator<Element> in
            var i = 0
            return AnyIterator { guard !isEmpty else { return nil }; defer { i += 1 }; return self[i % count] }
        }
    }
}

/// What the menu bar rotates through, and how often.
private struct MenuBarSettings: View {
    @AppStorage("status.interval") private var interval = 6.0
    @AppStorage("status.climate") private var climate = true
    @AppStorage("status.cameras") private var cameras = true
    @AppStorage("status.vehicles") private var vehicles = true
    @AppStorage("status.energy") private var energy = true
    @AppStorage("status.home") private var homeUse = true
    @AppStorage("status.media") private var media = true
    @AppStorage("status.alarm") private var alarm = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MENU BAR").eyebrow().padding(.leading, 4)
            Bezel(radius: 18, inset: 3) {
                VStack(spacing: 0) {
                    row("Air conditioning", "snowflake", $climate)
                    row("Camera events", "person.fill", $cameras)
                    row("Vehicle charge", "car.side.fill", $vehicles)
                    row("Battery and solar", "battery.75percent", $energy)
                    row("Home use", "bolt.house", $homeUse)
                    row("Now playing", "music.note", $media)
                    row("Alarm", "exclamationmark.shield.fill", $alarm)
                    HStack {
                        Text("Change every").font(.system(size: 13, weight: .medium))
                        Spacer()
                        Button {
                            PopupMenu.show(["4", "6", "10", "20"], selected: String(Int(interval)), label: { "\($0) seconds" }) { interval = Double($0) ?? 6 }
                        } label: {
                            Text("\(Int(interval))s").font(.system(size: 13, weight: .medium))
                                .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(Theme.fg.opacity(0.07)))
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("Change every \(Int(interval)) seconds")
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                }
            }
            Text("The menu bar takes turns showing these. A doorbell ring or someone at a camera shows straight away.")
                .font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ title: String, _ symbol: String, _ on: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(Theme.muted).frame(width: 18)
            Text(title).font(.system(size: 13, weight: .medium))
            Spacer()
            Toggle(title, isOn: on).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
    }
}

/// Which sections have a tab in the dock.
private struct SectionSettings: View {
    @AppStorage("hiddenSections") private var hiddenSections = ""

    private static let sections: [(key: String, title: String, symbol: String)] = [
        ("security", "Security", "video"),
        ("rooms", "Rooms", "square.grid.2x2"),
        ("devices", "Devices: energy, vehicles, gadgets, speakers", "powerplug"),
        ("map", "3D map", "cube.transparent"),
        ("activity", "Activity", "bell"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SECTIONS").eyebrow().padding(.leading, 4)
            Bezel(radius: 18, inset: 3) {
                VStack(spacing: 0) {
                    ForEach(Self.sections, id: \.key) { section in
                        HStack(spacing: 10) {
                            Image(systemName: section.symbol).font(.system(size: 12)).foregroundStyle(Theme.muted).frame(width: 18)
                            Text(section.title).font(.system(size: 13, weight: .medium))
                            Spacer()
                            Toggle(section.title, isOn: binding(section.key)).labelsHidden().toggleStyle(.switch).controlSize(.small)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                    }
                }
            }
            Text("Turn off what you don't use and its tab leaves the dock. Air conditioners always have one.")
                .font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func binding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { !hiddenSections.split(separator: ",").contains(Substring(key)) },
            set: { on in
                var set = Set(hiddenSections.split(separator: ",").map(String.init))
                if on { set.remove(key) } else { set.insert(key) }
                hiddenSections = set.sorted().joined(separator: ",")
            }
        )
    }
}
