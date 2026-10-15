import SwiftUI

// MARK: Where you are in the Devices tab

/// The three sections that share the Devices tab.
enum DeviceSection: String, CaseIterable, Identifiable {
    case energy, vehicles, gadgets, speakers
    var id: String { rawValue }

    var title: String {
        switch self {
        case .energy: "Energy"
        case .vehicles: "Vehicles"
        case .gadgets: "Gadgets"
        case .speakers: "Speakers"
        }
    }

    /// The sample home a section's demo plays, if it has one.
    var demoKind: DemoEngine.Kind? {
        switch self {
        case .energy: .energy
        case .vehicles: .vehicles
        case .gadgets: .gadgets
        case .speakers: nil
        }
    }
}

/// The Devices tab's state, kept by the panel so tapping the tab again can return to the grid.
@MainActor
final class DevicesHub: ObservableObject {
    @Published var section: DeviceSection?
    @Published var gadgetDevice: String?
    @Published var vehicleDevice: String?
    /// The home open in the tab, yours or the demo home.
    @Published var home: HomeRoute?
    /// The demo playing in the open section, if any. Leaving the section ends it.
    @Published private(set) var demo: DemoEngine?
    /// Today's totals for the homes, shared by the strip and each home's page.
    let homesFeed = HomesFeed()

    init() {
        // Development: `-demo energy|vehicles|gadgets` opens straight into a demo.
        if let raw = UserDefaults.standard.string(forKey: "demo"), let s = DeviceSection(rawValue: raw), let kind = s.demoKind {
            section = s
            demo = DemoEngine(kind)
        }
        // Development: `-openHome main|demo` opens the main home or the demo home.
        if let raw = UserDefaults.standard.string(forKey: "openHome") {
            home = raw == "demo" ? .demo : .real(HomeList.shared.main.id)
            if raw == "demo" { demo = DemoEngine(.energy) }
        }
    }

    func open(_ s: DeviceSection) {
        withAnimation(.glide) {
            section = s
            gadgetDevice = nil
            vehicleDevice = nil
        }
    }

    /// Opens a home; the demo home plays the energy demo's sample house.
    func openHome(_ route: HomeRoute) {
        withAnimation(.glide) {
            section = nil
            home = route
            demo = route == .demo ? DemoEngine(.energy) : nil
        }
    }

    /// Back to the grid, ending any demo.
    func showGrid() {
        withAnimation(.glide) {
            section = nil
            home = nil
            demo = nil
            gadgetDevice = nil
            vehicleDevice = nil
        }
    }

    func toggleDemo() {
        if home == .demo { return showGrid() }
        guard let section, let kind = section.demoKind else { return }
        withAnimation(.glide) {
            demo = demo == nil ? DemoEngine(kind) : nil
            gadgetDevice = nil
            vehicleDevice = nil
        }
    }
}

// MARK: Section chrome

/// What a section page shows in its header when it sits inside the Devices tab: a way back to
/// the grid, and the demo switch.
struct SectionChrome {
    var back: () -> Void
    var demoOn: Bool
    var toggleDemo: () -> Void
    /// False for a section without a sample home (Speakers), so it shows no demo switch.
    var hasDemo = true
}

private struct SectionChromeKey: EnvironmentKey {
    static let defaultValue: SectionChrome? = nil
}

extension EnvironmentValues {
    var sectionChrome: SectionChrome? {
        get { self[SectionChromeKey.self] }
        set { self[SectionChromeKey.self] = newValue }
    }
}

/// A route owns the demo it draws until its exit transition finishes. The hub can end
/// the live demo immediately without emptying the departing page or switching its data source.
struct DevicesRoute: Equatable {
    let home: HomeRoute?
    let section: DeviceSection?
    let demo: DemoEngine?

    var isDemo: Bool { demo != nil }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.home == rhs.home && lhs.section == rhs.section && lhs.demo === rhs.demo
    }
}

// MARK: The tab

/// Energy, Vehicles and Gadgets: a grid of three tiles, each opening its own page.
struct DevicesPage: View {
    @EnvironmentObject var store: HomeStore
    @ObservedObject var hub: DevicesHub
    let shown: Bool
    let visible: Bool

    var body: some View {
        let route = DevicesRoute(home: hub.home, section: hub.section, demo: hub.demo)
        ScreenFlow(route: route, depth: route.home == nil && route.section == nil ? 0 : 1) { current in
            Group {
                if let home = current.home {
                    HomeHost(hub: hub, route: home, demo: current.demo, visible: visible)
                        .id(home == .demo ? "home-demo" : "home")
                } else if let section = current.section {
                    SectionHost(hub: hub, section: section, demo: current.demo, shown: shown, visible: visible)
                        .id(section.rawValue + (current.isDemo ? "-demo" : ""))
                } else {
                    DevicesGrid(hub: hub, shown: shown) { hub.open($0) }
                }
            }
            // Keep this inset with the displayed page during the route swap.
            .padding(.bottom, current.isDemo ? 44 : 0)
        }
    }
}

/// A home's page: one of yours from Home Assistant, or the demo home from the energy demo's sample house.
private struct HomeHost: View {
    @ObservedObject var hub: DevicesHub
    @ObservedObject private var list = HomeList.shared
    @StateObject private var demoFeed = HomesFeed()
    let route: HomeRoute
    let demo: DemoEngine?
    let visible: Bool

    var body: some View {
        switch route {
        case .real(let id):
            if let home = list.homes.first(where: { $0.id == id }) {
                HomeDetail(feed: hub.homesFeed, home: home) { hub.showGrid() }
            }
        case .demo:
            if let demo {
                VStack(alignment: .leading, spacing: 14) {
                    DemoBanner(engine: demo) { hub.showGrid() }
                    HomeDetail(feed: demoFeed, home: Home(name: "Demo home", isMain: true), demo: true) { hub.showGrid() }
                        .environmentObject(demo.store)
                        .task(id: visible && hub.demo === demo) {
                            guard visible, hub.demo === demo else { return }
                            await demo.run()
                        }
                }
            }
        }
    }
}

/// One section's page, played from Home Assistant or, in a demo, from the sample home.
private struct SectionHost: View {
    @EnvironmentObject var store: HomeStore
    @ObservedObject var hub: DevicesHub
    let section: DeviceSection
    let demo: DemoEngine?
    let shown: Bool
    let visible: Bool

    var body: some View {
        let chrome = SectionChrome(back: { hub.showGrid() }, demoOn: demo != nil, toggleDemo: { hub.toggleDemo() },
                                   hasDemo: section.demoKind != nil)
        VStack(alignment: .leading, spacing: 14) {
            if let demo {
                DemoBanner(engine: demo) { hub.toggleDemo() }
                    .reveal(shown, 0)
                page
                    .environmentObject(demo.store)
                    .task(id: visible && hub.demo === demo) {
                        guard visible, hub.demo === demo else { return }
                        await demo.run()
                    }
            } else {
                page
            }
        }
        .environment(\.sectionChrome, chrome)
    }

    @ViewBuilder
    private var page: some View {
        switch section {
        case .energy: EnergyPage(shown: shown, visible: visible)
        case .vehicles: VehiclesPage(shown: shown, visible: visible, openDevice: $hub.vehicleDevice)
        case .gadgets: GadgetsPage(shown: shown, visible: visible, openDevice: $hub.gadgetDevice)
        case .speakers: MediaPage(players: store.players, shown: shown)
        }
    }
}

// MARK: The grid

private struct DevicesGrid: View {
    @EnvironmentObject var store: HomeStore
    @ObservedObject private var list = GadgetStore.shared
    @ObservedObject var hub: DevicesHub
    let shown: Bool
    let open: (DeviceSection) -> Void

    var body: some View {
        let devices = store.devices.values.filter { !$0.isService }.compactMap { store.homeDevice($0.id) }
        let summary = HubSummary(store: store, devices: devices, manual: list.gadgets)
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(eyebrow: summary.eyebrow, title: "Assets") { EmptyView() }
                .reveal(shown, 0)

            HomesStrip(feed: hub.homesFeed) { hub.openHome($0) }
                .reveal(shown, 1)
                .task(id: store.status == .connected) {
                    guard store.status == .connected else { return }
                    await hub.homesFeed.refresh(store, list: HomeList.shared)
                }

            // Two rows of two, so every section is in view without scrolling.
            let speakers = SpeakerSummary(store.players)
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    HubTile(section: .energy, art: [.solarPanel, .battery], line: summary.energy,
                            live: summary.energyLive, tint: Theme.homeEnergy) { open(.energy) }
                    HubTile(section: .vehicles, art: [.electricCar], line: summary.vehicles, live: summary.vehiclesLive,
                            tint: HomeDevice.vehicleAccent(.electricCar)) { open(.vehicles) }
                }
                HStack(alignment: .top, spacing: 12) {
                    HubTile(section: .gadgets, art: [.printer3D, .gameConsole], line: summary.gadgets, live: summary.gadgetsLive,
                            tint: HomeDevice.gadgetAccent(.printer3D)) { open(.gadgets) }
                    HubTile(section: .speakers, art: [.smartSpeaker, .meshSpeaker], line: speakers.line, live: speakers.playing,
                            tint: Color(red: 0.36, green: 0.8, blue: 1.0)) { open(.speakers) }
                }
            }
            .reveal(shown, 2)

            Text("Nothing connected yet? Open a section and try its demo to see how it works.")
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
                .opacity(summary.anything ? 0 : 1)
                .reveal(shown, 3)
        }
    }
}

/// One line per section, from what Home Assistant has right now.
@MainActor
private struct HubSummary {
    nonisolated static let idle = "Not connected yet"
    var energy = HubSummary.idle
    var vehicles = HubSummary.idle
    var gadgets = HubSummary.idle
    var energyLive = false, vehiclesLive = false, gadgetsLive = false
    var anything = false
    var eyebrow = "Energy, vehicles, gadgets, speakers"

    init(store: HomeStore, devices: [HomeDevice], manual: [Gadget]) {
        let sys = EnergySystem.read(store, prefs: nil)
        if !sys.isEmpty {
            var parts: [String] = []
            if let w = sys.solarWatts { parts.append("\(EnergyUnits.power(w)) solar") }
            if let p = sys.chargePercent { parts.append("battery \(Int(p.rounded()))%") }
            if parts.isEmpty, let w = sys.loadWatts { parts.append("home \(EnergyUnits.power(w))") }
            energy = parts.isEmpty ? "Connected" : parts.joined(separator: " · ")
            energyLive = (sys.solarWatts ?? 0) > 20
        }

        let vehicles = devices.filter { DeviceKind.vehicles.contains($0.kind) && !$0.entities.isEmpty }
        let handVehicles = manual.filter { Gadget.Kind.vehicleKinds.contains($0.kind) }
        if let car = vehicles.first(where: { $0.kind == .electricCar }) {
            let s = VehicleStatus(car)
            self.vehicles = [car.name, s.percent, s.isCharging ? "charging" : nil].compactMap { $0 }.joined(separator: " · ")
            vehiclesLive = s.isCharging
        } else if !vehicles.isEmpty || !handVehicles.isEmpty {
            let n = vehicles.count + handVehicles.count
            self.vehicles = "\(n) vehicle\(n == 1 ? "" : "s")"
        }

        let gadgetKinds: [DeviceKind] = [.printer3D, .gameConsole, .computer]
        let fromHome = devices.filter { gadgetKinds.contains($0.kind) && !$0.entities.isEmpty }
        let handGadgets = manual.filter { Gadget.Kind.gadgetKinds.contains($0.kind) }
        let printers = fromHome.filter { $0.kind == .printer3D }
        let printing = printers.filter { PrintJob($0).isPrinting }.count
        if !printers.isEmpty {
            gadgets = "\(printers.count) printer\(printers.count == 1 ? "" : "s")" + (printing > 0 ? " · \(printing) printing" : "")
            gadgetsLive = printing > 0
        } else if !fromHome.isEmpty || !handGadgets.isEmpty {
            let n = fromHome.count + handGadgets.count
            gadgets = "\(n) gadget\(n == 1 ? "" : "s")"
        }

        anything = !sys.isEmpty || !vehicles.isEmpty || !handVehicles.isEmpty || !fromHome.isEmpty || !handGadgets.isEmpty
        if anything {
            let n = vehicles.count + handVehicles.count + fromHome.count + handGadgets.count + sys.devices.count
            eyebrow = "\(n) asset\(n == 1 ? "" : "s")"
        }
    }
}

private struct HubTile: View {
    let section: DeviceSection
    let art: [DeviceKind]
    let line: String
    let live: Bool
    let tint: Color
    let action: () -> Void

    private var idle: Bool { line == HubSummary.idle }

    var body: some View {
        Button(action: action) {
            Bezel(radius: 24, inset: 4, lit: live, tint: tint) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        artwork
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.faint)
                            .padding(.top, 4)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.title).font(.system(size: 16, weight: .semibold)).tracking(-0.2)
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            if live { PulseDot(color: tint, size: 5) }
                            Text(line)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(live ? tint : Theme.muted)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(height: 32, alignment: .topLeading)
                        }
                    }
                    HStack {
                      if idle, section.demoKind != nil {
                        HStack(spacing: 5) {
                            Image(systemName: "play.fill").font(.system(size: 8.5, weight: .bold))
                            Text("Try the demo").font(.system(size: 11.5, weight: .semibold))
                        }
                        .foregroundStyle(DemoBanner.tint)
                        .padding(.horizontal, 9).frame(height: 22)
                        .background(Capsule().fill(DemoBanner.tint.opacity(0.12))
                            .overlay(Capsule().strokeBorder(DemoBanner.tint.opacity(0.3), lineWidth: 0.75)))
                      }
                      Spacer(minLength: 0)
                    }
                    .frame(height: 22)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(section.title). \(line)")
        .accessibilityHint("Opens \(section.title)")
    }

    /// One illustration at full size, or a pair side by side, drawn at their own size in a frame
    /// that fits them, so nothing is squeezed or cut.
    @ViewBuilder
    private var artwork: some View {
        if art.count == 1 {
            DeviceArtView(kind: art[0], active: true, accent: tint, size: 68)
                .frame(width: 68, height: 68)
        } else {
            HStack(alignment: .bottom, spacing: -2) {
                ForEach(Array(art.enumerated()), id: \.offset) { i, kind in
                    DeviceArtView(kind: kind, active: true, accent: EnergyPalette.accent(kind), size: i == 0 ? 62 : 54)
                        .zIndex(Double(art.count - i))
                }
            }
            .frame(height: 68, alignment: .bottom)
        }
    }
}

// MARK: Demo banner

/// Unmistakable while a demo plays: what it is, how fast it runs, which car, and the way out.
private struct DemoBanner: View {
    @ObservedObject var engine: DemoEngine
    let exit: () -> Void

    static let tint = Theme.brand
    private var surfaceTint: Color { engine.kind == .energy ? Theme.homeEnergy : Self.tint }

    var body: some View {
        Bezel(radius: 20, inset: 3, lit: true, tint: surfaceTint) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text("DEMO")
                        .font(.system(size: 11, weight: .heavy)).tracking(1.4)
                        .foregroundStyle(engine.kind == .energy ? Theme.onAccent : Theme.onBrand)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(engine.kind == .energy ? surfaceTint : Theme.brandFill))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Sample data, nothing is connected").font(.system(size: 13, weight: .semibold))
                        Text(detail).font(.system(size: 12)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 6)
                    Button(action: exit) {
                        Text("Exit demo").font(.system(size: 12.5, weight: .semibold))
                            .padding(.horizontal, 11).frame(height: 28)
                            .background(Capsule().fill(Theme.fg.opacity(0.1)).overlay(Capsule().strokeBorder(Theme.hairline)))
                    }
                    .buttonStyle(PressStyle())
                }

                HStack(spacing: 8) {
                    if engine.kind == .vehicles {
                        Button {
                            PopupMenu.show(DemoCar.all.map(\.id), selected: engine.car.id,
                                           label: { id in DemoCar.all.first { $0.id == id }?.title ?? id }) { id in
                                if let car = DemoCar.all.first(where: { $0.id == id }) { engine.choose(car) }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "car.side").font(.system(size: 11.5))
                                Text(engine.car.title).font(.system(size: 12.5, weight: .medium))
                                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Theme.muted)
                            }
                            .padding(.horizontal, 10).frame(height: 28)
                            .background(Capsule().fill(Theme.fg.opacity(0.07)))
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("Demo car: \(engine.car.title)")
                    }
                    if engine.kind == .energy {
                        HStack(spacing: 5) {
                            Image(systemName: "clock").font(.system(size: 11))
                            Text(engine.clock.formatted(date: .omitted, time: .shortened)).font(.system(size: 12.5, weight: .medium)).monospacedDigit()
                        }
                        .foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                    SpeedPicker(speed: $engine.speed)
                }
            }
            .padding(12)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Demo. Sample data, nothing is connected.")
    }

    private var detail: String {
        switch engine.kind {
        case .energy: "A sunny day on a house with solar, a 10 kWh battery and the grid."
        case .vehicles: "Pick a car and watch it charge. Every button works on the sample."
        case .gadgets: "A printer mid-print, a console and a Mac."
        }
    }
}

/// How fast the demo's clock runs.
private struct SpeedPicker: View {
    @Binding var speed: DemoEngine.Speed

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(DemoEngine.Speed.allCases.enumerated()), id: \.element) { index, s in
                Button { withAnimation(.selectionSlide) { speed = s } } label: {
                    Text(s.label)
                        .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(speed == s ? Color.black : Theme.muted)
                        .padding(.horizontal, 9).frame(height: 24)
                        .selectionFrame(index)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Speed \(s.label)")
                .accessibilityAddTraits(speed == s ? .isSelected : [])
            }
        }
        .slidingSelection(DemoEngine.Speed.allCases.firstIndex(of: speed), radius: 14)
        .padding(2)
        .background(Capsule().fill(Theme.fg.opacity(0.06)).overlay(Capsule().strokeBorder(Theme.hairline)))
    }
}

/// Stays above the dock while a demo plays, however far the page is scrolled.
struct DemoPill: View {
    @ObservedObject var hub: DevicesHub

    var body: some View {
        if hub.demo != nil {
            HStack(spacing: 8) {
                Circle().fill(Theme.brand).frame(width: 6, height: 6)
                Text("Demo · sample data").font(.system(size: 12, weight: .semibold))
                Button { hub.toggleDemo() } label: {
                    Text("Exit").font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 9).frame(height: 22)
                        .background(Capsule().fill(Theme.fg.opacity(0.12)))
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Exit demo")
            }
            .padding(.leading, 12).padding(.trailing, 4).frame(height: 30)
            .liquidGlass(in: Capsule())
            .padding(.bottom, 8)
            .transition(.opacity.combined(with: .offset(y: 8)))
        }
    }
}

// MARK: Trying a demo from an empty section

/// The invitation at the top of an empty section's setup guide.
struct TryDemoCard: View {
    @Environment(\.sectionChrome) private var chrome
    let message: String

    var body: some View {
        if let chrome, chrome.hasDemo, !chrome.demoOn {
            Button(action: chrome.toggleDemo) {
                HStack(spacing: 12) {
                    Image(systemName: "play.fill").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.onBrand)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Theme.brandFill))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Try the demo").font(.system(size: 13.5, weight: .semibold))
                        Text(message).font(.system(size: 12)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.faint)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.fg.opacity(0.045))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.brand.opacity(0.35), lineWidth: 0.75)))
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Try the demo. \(message)")
        }
    }
}

/// What the speakers are doing, in one line.
private struct SpeakerSummary {
    let line: String
    let playing: Bool

    init(_ players: [Entity]) {
        let on = players.filter { $0.state == "playing" }
        playing = !on.isEmpty
        if let first = on.first {
            let title = first.str("media_title") ?? "Playing"
            line = on.count > 1 ? "\(on.count) playing · \(title)" : "\(title) · \(first.name)"
        } else if players.isEmpty {
            line = HubSummary.idle
        } else {
            line = "\(players.count) speaker\(players.count == 1 ? "" : "s") · nothing playing"
        }
    }
}

extension HomeStore {
    /// Every speaker and player that isn't hidden in Home Assistant.
    var players: [Entity] {
        entities.values
            .filter { $0.domain == "media_player" }
            .filter { e in
                guard let reg = registry[e.id] else { return true }
                return !reg.hidden && reg.category == nil
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
