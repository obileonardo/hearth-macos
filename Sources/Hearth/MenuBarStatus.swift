import SwiftUI

/// One short thing the menu bar can say: a symbol and a few characters.
struct StatusLine: Equatable {
    enum Source: String, CaseIterable, Identifiable {
        case climate, cameras, vehicles, energy, home, media, alarm
        var id: String { rawValue }
        var title: String {
            switch self {
            case .climate: "Air conditioning"
            case .cameras: "Camera events"
            case .vehicles: "Vehicle charge"
            case .energy: "Battery and solar"
            case .home: "Home use"
            case .media: "Now playing"
            case .alarm: "Alarm"
            }
        }
        var on: Bool { UserDefaults.standard.object(forKey: "status.\(rawValue)") as? Bool ?? true }
    }

    let source: Source
    let symbol: String
    let text: String
    /// Takes over the menu bar until it's old news: the doorbell, someone at a camera, an alarm.
    var urgent = false
}

/// Everything worth saying in the menu bar right now, read live from Home Assistant and the activity feed.
@MainActor
enum StatusFeed {
    static func lines(store: HomeStore, log: ActivityLog, now: Date = Date()) -> [StatusLine] {
        var lines: [StatusLine] = []
        let enabled = Set(StatusLine.Source.allCases.filter(\.on))

        if enabled.contains(.alarm) {
            for e in store.entities.values where e.domain == "alarm_control_panel" && e.state == "triggered" {
                lines.append(StatusLine(source: .alarm, symbol: "exclamationmark.shield.fill", text: "Alarm", urgent: true))
            }
        }

        if enabled.contains(.cameras), let item = log.items.first(where: { [.person, .doorbell, .motion, .pet].contains($0.kind) }) {
            let age = now.timeIntervalSince(item.date)
            if age < 30 * 60 {
                let (who, place) = parts(of: item.title)
                let symbol = switch item.kind {
                case .doorbell: "bell.fill"
                case .person: "person.fill"
                case .pet: "pawprint.fill"
                default: "figure.walk"
                }
                let urgent = (item.kind == .doorbell && age < 120) || (item.kind == .person && age < 60)
                lines.append(StatusLine(source: .cameras, symbol: symbol, text: "\(who ?? place) \(short(age))", urgent: urgent))
            }
        }

        if enabled.contains(.climate) {
            for e in store.entities.values.filter({ $0.domain == "climate" }).sorted(by: { $0.id < $1.id }) {
                let c = Climate(e: e)
                if c.on, let t = c.target {
                    let degrees = t == t.rounded() ? "\(Int(t))" : String(format: "%.1f", t)
                    lines.append(StatusLine(source: .climate, symbol: Theme.modeSymbol(e.state), text: "\(degrees)°"))
                }
            }
        }

        if enabled.contains(.vehicles) {
            let devices = store.devices.values.compactMap { store.homeDevice($0.id) }.sorted { $0.name < $1.name }
            for d in devices where d.kind == .electricCar {
                let s = VehicleStatus(d, kind: .electricCar)
                if let percent = s.percent {
                    lines.append(StatusLine(source: .vehicles, symbol: s.isCharging ? "bolt.car.fill" : "car.side.fill", text: percent))
                }
            }
            for d in devices where d.kind == .robotVacuum || d.kind == .lawnMower {
                let s = VehicleStatus(d)
                guard let state = (s.vacuum ?? s.mower)?.state else { continue }
                if state == "error" {
                    lines.append(StatusLine(source: .vehicles, symbol: "exclamationmark.triangle.fill", text: "\(d.name.split(separator: " ").first ?? "Robot") needs help", urgent: true))
                } else if ["cleaning", "mowing"].contains(state) {
                    lines.append(StatusLine(source: .vehicles, symbol: d.kind == .lawnMower ? "leaf.fill" : "sparkles", text: s.percent ?? state.pretty))
                }
            }
        }

        if enabled.contains(.energy) {
            let e = EnergySystem.read(store, prefs: nil)
            if let percent = e.chargePercent {
                let charging = (e.batteryWatts ?? 0) < -20
                let symbol = charging ? "battery.100percent.bolt"
                    : percent >= 88 ? "battery.100percent" : percent >= 63 ? "battery.75percent"
                    : percent >= 38 ? "battery.50percent" : percent >= 13 ? "battery.25percent" : "battery.0percent"
                let low = percent < 15 && !charging
                lines.append(StatusLine(source: .energy, symbol: symbol, text: low ? "Battery \(Int(percent))%" : "\(Int(percent))%", urgent: low))
            }
            if let watts = e.solarWatts, watts > 20 {
                lines.append(StatusLine(source: .energy, symbol: "sun.max.fill", text: EnergyUnits.power(watts)))
            }
        }

        if enabled.contains(.home) {
            let list = HomeList.shared
            let main = HomeEnergy(home: list.main, store: store, list: list, gadgets: GadgetStore.shared.gadgets)
            if let watts = main.nowWatts, watts >= 1 {
                lines.append(StatusLine(source: .home, symbol: "bolt.house.fill", text: EnergyUnits.power(watts)))
            }
        }

        if enabled.contains(.media), let p = store.entities.values.first(where: { $0.domain == "media_player" && $0.state == "playing" }) {
            let title = p.str("media_title") ?? p.name
            lines.append(StatusLine(source: .media, symbol: "music.note", text: title.count > 18 ? String(title.prefix(17)) + "…" : title))
        }
        return lines
    }

    /// Splits a named person from their room; a generic doorbell event gives the door.
    private static func parts(of title: String) -> (who: String?, place: String) {
        if let r = title.range(of: " at ") {
            let who = String(title[..<r.lowerBound])
            let named = !["Person", "Movement", "Pet", "Sound", "Someone"].contains(who)
            return (named ? who : nil, String(title[r.upperBound...]))
        }
        if let r = title.range(of: " rang ") {
            let who = String(title[..<r.lowerBound])
            return (who == "Someone" ? nil : who, String(title[r.upperBound...]))
        }
        return (nil, title)
    }

    private static func short(_ age: TimeInterval) -> String {
        age < 60 ? "now" : age < 3600 ? "\(Int(age / 60))m" : "\(Int(age / 3600))h"
    }
}

/// Moves the menu bar on to its next line every few seconds.
@MainActor
final class StatusTicker: ObservableObject {
    @Published private(set) var tick = 0
    private var task: Task<Void, Never>?

    init() {
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let seconds = UserDefaults.standard.object(forKey: "status.interval") as? Double ?? 6
                try? await Task.sleep(for: .seconds(seconds))
                self?.tick += 1
            }
        }
    }

    deinit { task?.cancel() }
}

/// The menu bar: the app's glyph when there's nothing to say, otherwise one line at a time.
struct MenuBarLabel: View {
    @EnvironmentObject var store: HomeStore
    @EnvironmentObject var log: ActivityLog
    @StateObject private var ticker = StatusTicker()
    @AppStorage("pill.showsName") private var showsName = true

    var body: some View {
        let lines = StatusFeed.lines(store: store, log: log)
        let line = lines.first(where: \.urgent) ?? (lines.isEmpty ? nil : lines[ticker.tick % lines.count])
        Image(nsImage: MenuBarPill.image(line: line, showsName: showsName))
            .accessibilityLabel(line.map { "Hearth, \($0.text)" } ?? "Hearth")
            .onAppear { DispatchQueue.main.async { MenuBarPill.styleStatusButton() } }
            .onChange(of: ticker.tick) { _, _ in MenuBarPill.styleStatusButton() }
            .onChange(of: line) { _, now in LivePill.shared.statusLine = now }
    }
}

/// Draws the menu bar pill as an image, since a status item can't hold a styled capsule.
/// One dark capsule stays legible on either menu-bar appearance. The owned
/// status view draws this image directly, without a native button glass bezel.
@MainActor
enum MenuBarPill {
    private static var cache: [String: NSImage] = [:]
    /// Widths settle to steps, so the pill doesn't twitch as figures change.
    private static let step: CGFloat = 12

    static func image(line: StatusLine?, showsName: Bool, availableHeight: CGFloat? = nil, maximumWidth: CGFloat? = nil) -> NSImage {
        let height = availableHeight ?? HearthMenuController.shared.anchorView?.bounds.height ?? NSStatusBar.system.thickness
        let geometry = StatusPillGeometry(availableHeight: height)
        let key = "\(line?.symbol ?? "-")|\(line?.text ?? "-")|\(line?.urgent == true)|\(showsName)|\(geometry.canvasHeight)|\(geometry.bodyHeight)|\(maximumWidth ?? 0)"
        if let hit = cache[key] { return hit }
        if cache.count > 64 { cache.removeAll() }
        let urgent = line?.urgent == true
        let natural = render(PillArt(line: line, showsName: showsName, urgent: urgent, minWidth: 0, geometry: geometry))
        let naturalWidth = (natural.size.width / step).rounded(.up) * step
        let width = maximumWidth.map { min(naturalWidth, max(1, $0)) } ?? naturalWidth
        let image = render(PillArt(line: line, showsName: showsName, urgent: urgent, minWidth: width, geometry: geometry))
        image.isTemplate = false
        cache[key] = image
        return image
    }

    private static func render(_ view: PillArt) -> NSImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let cg = renderer.cgImage else { return MenuBarIcon.image }
        return NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2))
    }

    /// Red that holds up on any menu bar: a doorbell, someone at a camera, the alarm.
    static let urgentFill = Color(red: 0.93, green: 0.24, blue: 0.21)

    static func styleStatusButton() {
        if let cell = HearthMenuController.shared.button?.cell as? NSButtonCell {
            cell.highlightsBy = []
        }
        func find(_ view: NSView) -> NSStatusBarButton? {
            (view as? NSStatusBarButton) ?? view.subviews.lazy.compactMap(find).first
        }
        for window in NSApp.windows {
            if let root = window.contentView, let button = find(root), let cell = button.cell as? NSButtonCell {
                cell.highlightsBy = []
            }
        }
    }
}

private struct PillArt: View {
    let line: StatusLine?
    let showsName: Bool
    let urgent: Bool
    let minWidth: CGFloat
    let geometry: StatusPillGeometry

    var body: some View {
        let ink = Color.white
        HStack(spacing: 6) {
            MenuBarGlyph(size: 14)
            if showsName || line == nil {
                Text("Hearth").font(.system(size: 12, weight: .semibold)).tracking(-0.15)
            }
            if let line {
                if showsName {
                    Circle().fill(ink.opacity(urgent ? 0.7 : 0.45)).frame(width: 2.5, height: 2.5).padding(.horizontal, 1)
                }
                Image(systemName: line.symbol).font(.system(size: 10.5, weight: .semibold))
                Text(line.text).font(.system(size: 12.5, weight: .medium)).monospacedDigit().lineLimit(1).truncationMode(.tail)
            }
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 10)
        .frame(width: minWidth > 0 ? minWidth : nil)
        .frame(height: geometry.bodyHeight)
        .background {
            Capsule().fill(urgent ? AnyShapeStyle(MenuBarPill.urgentFill) : AnyShapeStyle(
                LinearGradient(colors: [Color(white: 0.14).opacity(0.92), Color(white: 0.06).opacity(0.9)],
                               startPoint: .top, endPoint: .bottom)))
                .overlay(Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.2), .white.opacity(0.055)],
                    startPoint: .top, endPoint: .bottom), lineWidth: 0.6))
        }
        .frame(height: geometry.canvasHeight)
        .clipped()
    }
}
