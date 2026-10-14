import AppKit
import SwiftUI

/// The widgets Hearth can put on the desktop.
///
/// These are Hearth's own windows at desktop level rather than WidgetKit widgets.
/// Claude's gallery experiment remains unfinished (see docs/widgets.md). Being
/// in-process, these observe live values instead of timeline snapshots.
enum DesktopWidgetKind: String, CaseIterable, Identifiable {
    case overview, climate, door, energy
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .climate: "Climate"
        case .door: "Recent activity"
        case .energy: "Energy"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "rectangle.3.group"
        case .climate: "snowflake"
        case .door: "bell"
        case .energy: "bolt.fill"
        }
    }

    /// Sized like macOS's own widget families: small, medium and extra large.
    var size: CGSize {
        switch self {
        case .overview: CGSize(width: 664, height: 170)
        case .climate: CGSize(width: 170, height: 170)
        case .door, .energy: CGSize(width: 344, height: 170)
        }
    }

    var minimumSize: CGSize {
        switch self {
        case .overview: CGSize(width: 360, height: 170)
        case .climate: CGSize(width: 170, height: 170)
        case .door, .energy: CGSize(width: 280, height: 170)
        }
    }

    /// Where a new widget first appears: a neat column down the left of the desktop.
    var defaultOrigin: CGPoint {
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let top = screen.maxY - 24
        switch self {
        case .overview: return CGPoint(x: screen.minX + 24, y: top - 170)
        case .door: return CGPoint(x: screen.minX + 24, y: top - 170 * 2 - 16)
        case .energy: return CGPoint(x: screen.minX + 24, y: top - 170 * 3 - 32)
        case .climate: return CGPoint(x: screen.minX + 24 + 344 + 16, y: top - 170 * 2 - 16)
        }
    }

    /// The panel page a click opens.
    var page: String {
        switch self {
        case .overview: "rooms"
        case .door: "activity"
        case .climate: "rooms"
        case .energy: "energy"
        }
    }
}

/// Opens, closes and keeps the desktop widgets.
@MainActor
final class DesktopWidgets {
    static let shared = DesktopWidgets()

    private var windows: [DesktopWidgetKind: NSWindow] = [:]
    private var gestureFrames: [DesktopWidgetKind: NSRect] = [:]
    private weak var store: HomeStore?
    private weak var log: ActivityLog?

    func attach(store: HomeStore, log: ActivityLog) {
        self.store = store
        self.log = log
        refresh()
    }

    private var wanted: [DesktopWidgetKind] {
        guard UserDefaults.standard.bool(forKey: "desktopWidgets") || CommandLine.arguments.contains("--desktop-widgets") else { return [] }
        let off = Set((UserDefaults.standard.string(forKey: "desktopWidgets.off") ?? "").split(separator: ",").map(String.init))
        return DesktopWidgetKind.allCases.filter { !off.contains($0.rawValue) }
    }

    func refresh() {
        guard let store, let log else { return }
        let want = Set(wanted)
        for (kind, window) in windows where !want.contains(kind) {
            window.orderOut(nil)
            windows[kind] = nil
            gestureFrames[kind] = nil
        }
        for kind in DesktopWidgetKind.allCases where want.contains(kind) && windows[kind] == nil {
            windows[kind] = makeWindow(kind, store: store, log: log)
        }
    }

    private func makeWindow(_ kind: DesktopWidgetKind, store: HomeStore, log: ActivityLog) -> NSWindow {
        let window = DesktopWidgetWindow(contentRect: NSRect(origin: kind.defaultOrigin, size: kind.size),
                                         styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        // Just above the desktop icons, beneath every app window, on every Space.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovableByWindowBackground = false
        window.minSize = kind.minimumSize
        window.overview = kind == .overview
        window.delegate = window
        window.maxSize = CGSize(width: 1100, height: 700)
        window.acceptsMouseMovedEvents = true
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("Hearth.widget.\(kind.rawValue)")
        window.setFrameUsingName("Hearth.widget.\(kind.rawValue)")
        let restored = WidgetWindowGeometry.constrainedSize(window.frame.size, minimum: kind.minimumSize, overview: window.overview)
        if restored != window.frame.size {
            var frame = window.frame
            frame.origin.y = frame.maxY - restored.height
            frame.size = restored
            window.setFrame(frame, display: false)
        }
        window.contentView = WidgetHostingView(rootView:
            DesktopWidgetCard(kind: kind).environmentObject(store).environmentObject(log))
        window.orderFront(nil)
        return window
    }

    /// Keep the top left corner steady while resizing, using the whole gesture's
    /// translation rather than adding every event to the previous window frame.
    func manipulate(_ kind: DesktopWidgetKind, translation: CGSize, resizing: Bool, finished: Bool) {
        guard let window = windows[kind] else { return }
        let start = gestureFrames[kind] ?? window.frame
        gestureFrames[kind] = start
        let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? start
        let frame = WidgetWindowGeometry.frame(start: start, translation: translation, resizing: resizing,
                                               minimum: kind.minimumSize, overview: kind == .overview, screen: screen)
        window.setFrame(frame, display: true)
        if finished {
            gestureFrames[kind] = nil
            window.saveFrame(usingName: "Hearth.widget.\(kind.rawValue)")
        }
    }

    /// Assistive actions stay on the current display. Mouse dragging keeps its
    /// existing ability to move a widget between displays.
    func moveAccessibly(_ kind: DesktopWidgetKind, translation: CGSize) {
        guard let window = windows[kind] else { return }
        gestureFrames[kind] = nil
        let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
        var frame = WidgetWindowGeometry.frame(start: window.frame, translation: translation, resizing: false,
                                               minimum: kind.minimumSize, overview: kind == .overview, screen: screen)
        frame.origin.x = min(max(frame.origin.x, screen.minX), max(screen.minX, screen.maxX - frame.width))
        frame.origin.y = min(max(frame.origin.y, screen.minY), max(screen.minY, screen.maxY - frame.height))
        window.setFrame(frame, display: true)
        window.saveFrame(usingName: "Hearth.widget.\(kind.rawValue)")
    }
}

private final class DesktopWidgetWindow: NSWindow, NSWindowDelegate {
    var overview = false
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        WidgetWindowGeometry.constrainedSize(frameSize, minimum: minSize, overview: overview)
    }
}

private final class WidgetHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: Cards

/// One widget: frosted glass with the desktop showing through, Hearth's type and colours.
struct DesktopWidgetCard: View {
    @EnvironmentObject var store: HomeStore
    @EnvironmentObject var log: ActivityLog
    let kind: DesktopWidgetKind
    var previewOpaque = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var hovering = false
    @AppStorage("desktopWidgets.climateEntity") private var selectedClimate = ""

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        GeometryReader { geometry in
            Group {
                if kind == .overview { content(width: geometry.size.width) }
                else {
                    Button { openPanel() } label: {
                        content(width: geometry.size.width)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .contentShape(shape)
                    }
                    .buttonStyle(.plain)
                    .help("Open \(kind.title) in Hearth")
                }
            }
            .padding(18).padding(.top, 8).padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
            .background {
                if reduceTransparency || previewOpaque {
                    shape.fill(Theme.raised)
                } else {
                    DesktopGlass().clipShape(shape)
                    shape.fill(Theme.base.opacity(scheme == .dark ? 0.35 : 0.25))
                }
            }
            .overlay(shape.strokeBorder(LinearGradient(colors: [Theme.fg.opacity(0.18), Theme.fg.opacity(0.04)],
                                                       startPoint: .top, endPoint: .bottom), lineWidth: 0.75))
            .overlay(alignment: .top) {
                Capsule().fill(Theme.muted.opacity(hovering ? 0.65 : 0.28))
                    .frame(width: 32, height: 3).padding(.horizontal, 26).frame(height: 24)
                    .contentShape(Rectangle())
                    .gesture(windowGesture(resizing: false))
                    .help("Drag to move")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Move \(kind.title) widget")
                    .accessibilityAction(named: Text("Move left")) { moveBy(x: -20, y: 0) }
                    .accessibilityAction(named: Text("Move right")) { moveBy(x: 20, y: 0) }
                    .accessibilityAction(named: Text("Move up")) { moveBy(x: 0, y: -20) }
                    .accessibilityAction(named: Text("Move down")) { moveBy(x: 0, y: 20) }
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "line.3.horizontal.decrease")
                    .rotationEffect(.degrees(-45)).font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.muted.opacity(hovering ? 0.8 : 0.3))
                    .frame(width: 28, height: 28).contentShape(Rectangle())
                    .gesture(windowGesture(resizing: true))
                    .help("Drag to resize")
                    .accessibilityLabel("Resize \(kind.title) widget")
                    .accessibilityAdjustableAction { direction in
                        let amount: CGFloat = direction == .increment ? 30 : -30
                        DesktopWidgets.shared.manipulate(kind, translation: CGSize(width: amount, height: amount), resizing: true, finished: true)
                    }
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 4) {
                    Circle().fill(store.status == .connected ? Theme.ok : Theme.muted).frame(width: 3, height: 3)
                    Text(connectionLabel)
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.muted)
                }.padding(.leading, 18).padding(.bottom, 8).allowsHitTesting(false)
            }
            .contentShape(shape)
            .onHover { inside in withAnimation(.snap) { hovering = inside } }
    }

    private func windowGesture(resizing: Bool) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { DesktopWidgets.shared.manipulate(kind, translation: $0.translation, resizing: resizing, finished: false) }
            .onEnded { DesktopWidgets.shared.manipulate(kind, translation: $0.translation, resizing: resizing, finished: true) }
    }

    private func moveBy(x: CGFloat, y: CGFloat) {
        DesktopWidgets.shared.moveAccessibly(kind, translation: CGSize(width: x, height: y))
    }

    private var connectionLabel: String {
        switch store.status {
        case .connected: return store.isDemo ? "Sample" : "Live"
        case .connecting: return "Connecting"
        case .needsSetup: return "Connect Home Assistant"
        case .rejected: return "Sign-in needed"
        case .failed: return "Offline · last received values"
        }
    }

    private func openPanel(page requested: String? = nil) {
        HearthNavigation.open(requested ?? (kind == .climate ? (climate?.id ?? "rooms") : kind.page))
    }

    private func link<V: View>(_ page: String, @ViewBuilder content: () -> V) -> some View {
        Button { openPanel(page: page) } label: {
            content().frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    @ViewBuilder private func content(width: CGFloat) -> some View {
        switch kind {
        case .climate: ClimateTile(entity: climate, large: true)
        case .door: DoorTile(item: latestAtDoor, wide: width >= 420)
        case .energy: EnergyTile(system: EnergySystem.read(store, prefs: nil), home: homeWatts)
        case .overview:
            if width >= 620 {
                HStack(spacing: 18) {
                    link(climate?.id ?? "rooms") { ClimateTile(entity: climate, large: false) }.frame(width: 140)
                    divider
                    link("activity") { DoorTile(item: latestAtDoor, wide: false, compact: true) }.frame(maxWidth: .infinity)
                    divider
                    link(summaryPage) { overviewSummary }.frame(width: 200)
                }
            } else {
                VStack(spacing: 18) {
                    HStack(spacing: 18) {
                        link(climate?.id ?? "rooms") { ClimateTile(entity: climate, large: false) }
                        divider
                        link(summaryPage) { overviewSummary }
                    }.frame(minHeight: 110)
                    Rectangle().fill(Theme.hairline).frame(height: 0.75)
                    link("activity") { DoorTile(item: latestAtDoor, wide: false, compact: true) }.frame(minHeight: 80)
                }
            }
        }
    }

    private var divider: some View { Rectangle().fill(Theme.hairline).frame(width: 0.75) }

    private var summaryPage: String {
        let energy = EnergySystem.read(store, prefs: nil)
        if energy.hasBattery || energy.hasSolar || homeWatts != nil { return "energy" }
        return store.entities.values.contains { $0.domain == "media_player" && $0.state == "playing" } ? "speakers" : "rooms"
    }

    @ViewBuilder private var overviewSummary: some View {
        let energy = EnergySystem.read(store, prefs: nil)
        if energy.hasBattery || energy.hasSolar || homeWatts != nil {
            EnergyTile(system: energy, home: homeWatts)
        } else if let player = store.entities.values.filter({ $0.domain == "media_player" && $0.state == "playing" }).sorted(by: { $0.id < $1.id }).first {
            VStack(alignment: .leading, spacing: 4) {
                WidgetLabel(text: "Playing", symbol: "waveform", tint: Theme.sand)
                Spacer(minLength: 4)
                Text(player.str("media_title") ?? player.name).font(.system(size: 16, weight: .semibold)).lineLimit(2)
                Text(player.str("media_artist") ?? player.name).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                WidgetLabel(text: "Home", symbol: "house", tint: Theme.sand)
                Spacer(minLength: 4)
                Text("\(store.devices.count) devices").font(.system(size: 24, weight: .light)).monospacedDigit()
                Text("\(store.areas.count) rooms").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var climate: Entity? {
        let all = store.entities.values.filter {
            $0.domain == "climate" && !DeviceKind.vehicles.contains(store.homeDevice(store.registry[$0.id]?.deviceID ?? "")?.kind ?? .generic)
        }.sorted { $0.id < $1.id }
        if let chosen = all.first(where: { $0.id == selectedClimate }) { return chosen }
        return all.first { !$0.isUnavailable && Climate(e: $0).on } ?? all.first { !$0.isUnavailable } ?? all.first
    }

    /// Always show the newest event. A missing picture must not cause an older
    /// event to hide a new arrival; its picture can appear when the log adds it.
    private var latestAtDoor: ActivityLog.Item? {
        log.items.first { [.person, .doorbell].contains($0.kind) }
    }

    private var homeWatts: Double? {
        let list = HomeList.shared
        return HomeEnergy(home: list.main, store: store, list: list, gadgets: GadgetStore.shared.gadgets).nowWatts
    }
}

/// Liquid glass's desktop cousin: behind-window blur that lets the wallpaper through.
private struct DesktopGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

private struct WidgetLabel: View {
    let text: String
    let symbol: String
    var tint: Color = Theme.muted

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(tint)
            Text(text.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.9).foregroundStyle(Theme.muted).lineLimit(1)
        }
    }
}

private struct ClimateTile: View {
    let entity: Entity?
    let large: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let entity {
                let c = Climate(e: entity)
                WidgetLabel(text: Climate.shortName(entity.name), symbol: Theme.modeSymbol(c.on ? c.mode : "off"),
                            tint: c.on ? Theme.air(c.mode) : Theme.muted)
                Spacer(minLength: 4)
                if entity.isUnavailable {
                    Text("Offline").font(.system(size: large ? 28 : 24, weight: .light)).foregroundStyle(Theme.muted)
                } else if let t = c.target, c.on {
                    Text(t == t.rounded() ? "\(Int(t))°" : String(format: "%.1f°", t))
                        .font(.system(size: large ? 46 : 40, weight: .light)).tracking(-1.5).monospacedDigit()
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText())
                } else {
                    Text("Off").font(.system(size: large ? 34 : 30, weight: .light)).foregroundStyle(Theme.muted)
                }
                Text(c.on ? Theme.modeName(c.mode) + (c.room.map { " · room \(Int($0.rounded()))°" } ?? "") : (c.room.map { "Room \(Int($0.rounded()))°" } ?? " "))
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted).monospacedDigit().lineLimit(1)
            } else {
                WidgetLabel(text: "Climate", symbol: "snowflake")
                Spacer()
                Text("No air conditioner").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct DoorTile: View {
    let item: ActivityLog.Item?
    let wide: Bool
    var compact = false

    var body: some View {
        HStack(spacing: 12) {
            if !compact, let path = item?.imageFile, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).privacyBlurred()
                    .frame(width: wide ? 140 : 82)
                    .frame(maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .privacySensitive()
            }
            VStack(alignment: .leading, spacing: 4) {
                WidgetLabel(text: "Activity", symbol: item?.kind.symbol ?? "bell", tint: Theme.sand)
                Spacer(minLength: 2)
                if let item {
                    Text(item.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(2)
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(Self.ago(item.date, now: context.date)).font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.muted).monospacedDigit()
                    }
                } else {
                    Text("All quiet").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                    Text("People and the doorbell show here").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    static func ago(_ date: Date, now: Date) -> String {
        let s = max(0, now.timeIntervalSince(date))
        if s < 60 { return "Just now" }
        if s < 3600 { return "\(Int(s / 60)) min ago" }
        if s < 86_400 { return "\(Int(s / 3600)) h ago · \(date.formatted(date: .omitted, time: .shortened))" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct EnergyTile: View {
    let system: EnergySystem
    let home: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetLabel(text: "Energy", symbol: "bolt.fill", tint: Theme.ok)
            Spacer(minLength: 4)
            if system.hasBattery || system.hasSolar || home != nil {
                ViewThatFits(in: .horizontal) {
                  HStack(alignment: .lastTextBaseline, spacing: 18) {
                    if let p = system.chargePercent {
                        figure("\(Int(p.rounded()))%", "Battery")
                    }
                    if let w = system.solarWatts {
                        figure(EnergyUnits.power(w), "Solar")
                    }
                    if let w = home {
                        figure(EnergyUnits.power(w), "Home now")
                    }
                  }.fixedSize(horizontal: true, vertical: false)
                  VStack(spacing: 7) {
                    if let p = system.chargePercent { compactFigure("\(Int(p.rounded()))%", "Battery") }
                    if let w = system.solarWatts { compactFigure(EnergyUnits.power(w), "Solar") }
                    if let w = home { compactFigure(EnergyUnits.power(w), "Home now") }
                  }
                }
            } else {
                Text("Not connected yet").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                Text("Add your inverter in Home Assistant").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func compactFigure(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.muted)
            Spacer(minLength: 6)
            Text(value).font(.system(size: 18, weight: .light)).monospacedDigit().foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
        }
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 26, weight: .light)).tracking(-0.6).monospacedDigit().foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted)
        }
    }
}
