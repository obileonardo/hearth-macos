import SwiftUI
import WidgetKit

struct HearthGalleryEntry: TimelineEntry {
    var date: Date
    var snapshot: HearthWidgetSnapshot
    var stale: Bool { HearthWidgetTimeline.stale(snapshot, at: date) }
}

struct HearthGalleryProvider: TimelineProvider {
    func placeholder(in context: Context) -> HearthGalleryEntry {
        .init(date: .now, snapshot: .sample())
    }
    func getSnapshot(in context: Context, completion: @escaping (HearthGalleryEntry) -> Void) {
        completion(.init(date: .now, snapshot: context.isPreview ? .sample() : read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<HearthGalleryEntry>) -> Void) {
        let now = Date.now
        let snapshot = read()
        // Advance to a stale indicator even if the app quits and no new reload
        // arrives. WidgetKit, rather than the app, schedules timeline delivery.
        let dates = HearthWidgetTimeline.dates(snapshot, now: now)
        completion(Timeline(entries: dates.map { .init(date: $0, snapshot: snapshot) },
                            policy: .after(HearthWidgetTimeline.refresh(after: now))))
    }
    private func read() -> HearthWidgetSnapshot { HearthWidgetStore.shared()?.read() ?? .empty() }
}

enum HearthGalleryKind: String, CaseIterable {
    case overview, climate, activity, energy
    var title: String {
        switch self {
        case .overview: "Hearth overview"
        case .climate: "Climate"
        case .activity: "Recent activity"
        case .energy: "Energy"
        }
    }
    var detail: String {
        switch self {
        case .overview: "The home's climate, activity and energy at a glance."
        case .climate: "Your selected air conditioner and room temperature."
        case .activity: "The newest person or doorbell event from Hearth."
        case .energy: "Battery charge, solar generation and home power."
        }
    }
    var families: [WidgetFamily] {
        self == .overview ? [.systemMedium, .systemLarge, .systemExtraLarge] : [.systemSmall, .systemMedium]
    }
}

@MainActor
private func galleryConfiguration(_ kind: HearthGalleryKind) -> some WidgetConfiguration {
        StaticConfiguration(kind: "com.elvisobi.hearth.\(kind.rawValue)", provider: HearthGalleryProvider()) { entry in
            HearthGalleryView(entry: entry, kind: kind)
        }
        .configurationDisplayName(kind.title)
        .description(kind.detail)
        .supportedFamilies(kind.families)
        .contentMarginsDisabled()
}

struct HearthOverviewWidget: Widget { var body: some WidgetConfiguration { galleryConfiguration(.overview) } }
struct HearthClimateWidget: Widget { var body: some WidgetConfiguration { galleryConfiguration(.climate) } }
struct HearthActivityWidget: Widget { var body: some WidgetConfiguration { galleryConfiguration(.activity) } }
struct HearthEnergyWidget: Widget { var body: some WidgetConfiguration { galleryConfiguration(.energy) } }

#if !HEARTH_WIDGET_PREVIEW
@main
#endif
struct HearthWidgets: WidgetBundle {
    var body: some Widget {
        HearthOverviewWidget()
        HearthClimateWidget()
        HearthActivityWidget()
        HearthEnergyWidget()
    }
}

struct HearthGalleryView: View {
    let entry: HearthGalleryEntry
    let kind: HearthGalleryKind
    var previewFamily: WidgetFamily? = nil
    var previewing = false
    @Environment(\.widgetFamily) private var environmentFamily
    @Environment(\.colorScheme) private var scheme
    private var snapshot: HearthWidgetSnapshot { entry.snapshot }
    private var family: WidgetFamily { previewFamily ?? environmentFamily }
    private var tint: Color { Color(red: 0.66, green: 0.76, blue: 0.84) }
    private var muted: Color { Color.primary.opacity(0.56) }
    private var destination: URL {
        switch kind {
        case .climate: HearthWidgetLink.climateURL(entityID: snapshot.climate?.entityID)
        case .activity: HearthWidgetLink.url(page: "activity")
        case .energy: HearthWidgetLink.url(page: "energy")
        case .overview: HearthWidgetLink.url(page: "rooms")
        }
    }

    var body: some View {
        if previewing { surface.background(backdrop) }
        else { surface.containerBackground(for: .widget) { backdrop } }
    }

    var backdrop: some View {
        LinearGradient(colors: scheme == .dark ? [Color(white: 0.10), Color(white: 0.055)]
                                               : [Color(white: 0.98), Color(white: 0.93)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The same authored surface is available to deterministic offline renders;
    /// only WidgetKit's system-owned container is supplied by the actual host.
    var surface: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
            HStack(spacing: 5) {
                Circle().fill(snapshot.connection == "Connected" && !entry.stale ? Color.green.opacity(0.7) : muted).frame(width: 3, height: 3)
                if entry.stale {
                    if previewing { Text("Updated \(relative(snapshot.updatedAt)) ago") }
                    else { Text("Updated \(snapshot.updatedAt, style: .relative) ago") }
                } else { Text(snapshot.connection) }
            }
            .font(.system(size: 9, weight: .medium)).foregroundStyle(muted)
            .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(16)
        .foregroundStyle(Color.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.primary.opacity(scheme == .dark ? 0.035 : 0.025))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Color.primary.opacity(0.12), Color.primary.opacity(0.035)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 0.6))
                .padding(4)
        }
        .widgetURL(destination)
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .climate: climate
        case .activity: activity
        case .energy: energy
        case .overview:
            if family == .systemLarge {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 18) {
                        link(HearthWidgetLink.climateURL(entityID: snapshot.climate?.entityID)) { climate }
                        link(summaryURL) { summary }
                    }
                    Divider().opacity(0.45)
                    link(HearthWidgetLink.url(page: "activity")) { activity }
                }
            } else {
                HStack(alignment: .top, spacing: 14) {
                    link(HearthWidgetLink.climateURL(entityID: snapshot.climate?.entityID)) { climate }.frame(maxWidth: .infinity)
                    Divider().opacity(0.45)
                    link(HearthWidgetLink.url(page: "activity")) { activity }.frame(maxWidth: .infinity)
                    Divider().opacity(0.45)
                    link(summaryURL) { summary }.frame(maxWidth: .infinity)
                }
            }
        }
    }
    @ViewBuilder private func link<Content: View>(_ destination: URL, @ViewBuilder content: () -> Content) -> some View {
        // ImageRenderer cannot rasterize a system Link outside a widget host.
        // Offline fixtures use its exact content; production retains the link.
        if previewing { content() }
        else { Link(destination: destination, label: content).buttonStyle(.plain) }
    }
    private var summaryURL: URL {
        HearthWidgetLink.url(page: snapshot.energy.hasReadings ? "energy" : snapshot.playing != nil ? "speakers" : "rooms")
    }
    private var climate: some View {
        VStack(alignment: .leading, spacing: 6) {
            label(snapshot.climate?.name ?? "Climate", symbol: "snowflake")
            Spacer(minLength: 2)
            if let c = snapshot.climate {
                Text(!c.available ? "Offline" : c.mode == "off" ? "Off" : c.target.map(degrees) ?? "—")
                    .font(.system(size: kind == .climate ? 42 : 32, weight: .light)).tracking(-1)
                    .monospacedDigit().minimumScaleFactor(0.65).lineLimit(1)
                Text(c.mode == "off" ? "Off" : c.mode.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(muted).lineLimit(1)
                if let room = c.room {
                    Text("Room \(degrees(room))").font(.system(size: 11)).foregroundStyle(muted).lineLimit(1)
                }
            } else {
                Text("Connect Hearth").font(.system(size: 13, weight: .medium))
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
    private var activity: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("Activity", symbol: snapshot.activity?.symbol ?? "bell")
            Spacer(minLength: 2)
            Text(snapshot.activity?.title ?? "All quiet")
                .font(.system(size: 14, weight: .semibold)).lineLimit(3).privacySensitive()
            if let date = snapshot.activity?.date {
                Group {
                    if previewing { Text(relative(date)) }
                    else { Text(date, style: .relative) }
                }.font(.system(size: 11)).foregroundStyle(muted)
            } else {
                Text("People and the doorbell").font(.system(size: 11)).foregroundStyle(muted).lineLimit(2)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
    private var energy: some View {
        VStack(alignment: .leading, spacing: 7) {
            label("Energy", symbol: "bolt")
            Spacer(minLength: 2)
            if snapshot.energy.hasReadings {
                if let battery = snapshot.energy.batteryPercent { figure("\(Int(battery.rounded()))%", "Battery") }
                if let watts = snapshot.energy.solarWatts { figure(power(watts), "Solar") }
                if let watts = snapshot.energy.homeWatts { figure(power(watts), "Home") }
            } else {
                Text("Not connected yet").font(.system(size: 13, weight: .medium)).lineLimit(2)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
    @ViewBuilder private var summary: some View {
        if snapshot.energy.hasReadings { energy }
        else if let playing = snapshot.playing {
            VStack(alignment: .leading, spacing: 6) {
                label("Playing", symbol: "waveform")
                Spacer(minLength: 2)
                Text(playing.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                if let artist = playing.artist { Text(artist).font(.system(size: 11)).foregroundStyle(muted).lineLimit(1) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                label("Home", symbol: "house")
                Spacer(minLength: 2)
                Text("\(snapshot.deviceCount)").font(.system(size: 32, weight: .light)).monospacedDigit()
                Text("devices · \(snapshot.roomCount) rooms").font(.system(size: 11)).foregroundStyle(muted).lineLimit(2)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
    private func label(_ text: String, symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 10, weight: .medium)).foregroundStyle(tint)
            Text(text.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.6)
                .foregroundStyle(muted).lineLimit(1)
        }
    }
    private func figure(_ value: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value).font(.system(size: 20, weight: .light)).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
            Text(text).font(.system(size: 10)).foregroundStyle(muted).lineLimit(1)
        }
    }
    private func degrees(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))°" : String(format: "%.1f°", value)
    }
    private func power(_ value: Double) -> String {
        abs(value) >= 1000 ? String(format: "%.1f kW", value / 1000) : "\(Int(value.rounded())) W"
    }
    private func relative(_ date: Date) -> String {
        let seconds = max(0, entry.date.timeIntervalSince(date))
        if seconds < 60 { return "Just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min" }
        if seconds < 86_400 { return "\(Int(seconds / 3600)) h" }
        return "\(Int(seconds / 86_400)) d"
    }
}
