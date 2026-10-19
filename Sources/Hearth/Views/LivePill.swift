import AppKit
import Combine
import SwiftUI

/// A malformed finite reading can still exceed Int. Keep normal notification
/// rounding while omitting impossible values instead of trapping or inventing 0.
enum LivePillClimateReading {
    static func text(_ value: Double) -> String? {
        guard value.isFinite, Int(exactly: value.rounded()) != nil else { return nil }
        if value == value.rounded() { return degrees(value) }
        return String(format: "%.1f", value)
    }
}

/// Something worth a moment of attention: who's at the door, the alarm, a car that's charged.
struct PillEvent: Equatable, Identifiable {
    enum Kind: String, CaseIterable, Identifiable {
        case doorbell, people, alarm, vehicles, climate, hearth
        var id: String { rawValue }
        var title: String {
            switch self {
            case .doorbell: "Doorbell"
            case .people: "People"
            case .alarm: "Alarm"
            case .vehicles: "Vehicles"
            case .climate: "Climate"
            case .hearth: "Hearth"
            }
        }
        var symbol: String {
            switch self {
            case .doorbell: "bell.fill"
            case .people: "person.fill"
            case .alarm: "exclamationmark.shield.fill"
            case .vehicles: "bolt.car.fill"
            case .climate: "snowflake"
            case .hearth: "house.fill"
            }
        }
    }

    let id = UUID()
    var kind: Kind
    /// Where or what: "Front Door", "Model Y", "Workspace".
    var place: String
    /// What happened: "Someone's at the door", "Charged to 90%".
    var detail: String
    var symbol: String
    var tint: Color
    var date = Date()
    /// A camera picture for the orb, when there is one.
    var imagePath: String?
    /// The page the pill opens, and what its round button says.
    var page: String?
    var actionSymbol = "arrow.up.right"
    var actionLabel = "Open"
    var urgent = false
}

/// The Live pill: a capsule of glass that drops from under Hearth's menu bar item when
/// something happens, then lifts away. Hovering holds it; a click opens the right page.
@MainActor
final class LivePill: ObservableObject {
    static let shared = LivePill()

    static func preview(event: PillEvent? = nil) -> some View {
        let pill = LivePill()
        pill.event = event ?? PillEvent(kind: .doorbell, place: "Front door", detail: "Someone's at the door",
                               symbol: "bell.fill", tint: Theme.sand, page: "security", urgent: true)
        pill.shown = true
        pill.remaining = duration
        return LivePillView().environmentObject(pill)
    }

    @Published private(set) var event: PillEvent?
    @Published var shown = false
    @Published var hovering = false {
        didSet { if hovering { remaining = Self.duration } }
    }
    /// Seconds left before it lifts away, for the ring on its button.
    @Published private(set) var remaining: Double = 0
    /// How far the capsule moves up inside a window held at the screen's top edge.
    @Published private(set) var bodyLift: CGFloat = 0
    /// The line the menu bar is showing now, for the preview when a source is switched on.
    var statusLine: StatusLine?

    static let duration: Double = 6
    private var panel: NSPanel?
    private var timer: Task<Void, Never>?
    private var watchers = Set<AnyCancellable>()
    private var seenItems = Set<UUID>()
    private var defaultsSnapshot: [String: Bool] = [:]
    private weak var store: HomeStore?
    private weak var log: ActivityLog?

    var enabled: Bool { UserDefaults.standard.object(forKey: "livePill") as? Bool ?? true }

    static func shows(_ kind: PillEvent.Kind) -> Bool {
        guard kind != .hearth else { return true }
        let off = Set((UserDefaults.standard.string(forKey: "livePill.off") ?? "").split(separator: ",").map(String.init))
        return !off.contains(kind.rawValue)
    }

    // MARK: Wiring

    func attach(store: HomeStore, log: ActivityLog) {
        self.store = store
        self.log = log
        seenItems = Set(log.items.map(\.id))
        log.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] items in self?.newActivity(items) }
            .store(in: &watchers)
        defaultsSnapshot = Self.switches()
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.switchesChanged() }
            .store(in: &watchers)
        store.$status
            .receive(on: RunLoop.main)
            .filter { $0 == .connected }
            .first()
            .sink { [weak self] _ in self?.introduceOnce() }
            .store(in: &watchers)
    }

    /// Called for every state change Home Assistant reports.
    func handle(_ new: Entity, _ old: Entity?) {
        guard let old, !new.isUnavailable, !old.isUnavailable else { return }
        let device = store?.device(of: new.id)?.name ?? new.name
        switch new.domain {
        case "alarm_control_panel" where new.state == "triggered" && old.state != "triggered":
            present(PillEvent(kind: .alarm, place: device, detail: "The alarm is going off", symbol: "exclamationmark.shield.fill",
                              tint: Theme.live, page: "security", actionSymbol: "video.fill", actionLabel: "See cameras", urgent: true))
        case "vacuum" where new.state == "error" && old.state != "error",
             "lawn_mower" where new.state == "error" && old.state != "error":
            present(PillEvent(kind: .vehicles, place: device, detail: "Needs a hand", symbol: "exclamationmark.triangle.fill",
                              tint: Theme.live, page: "vehicles", actionLabel: "See vehicles"))
        case "sensor" where new.id.contains("charg"):
            let done = ["complete", "completed", "charged", "fully_charged", "done", "finished", "charge_complete"]
            if old.state.lowercased() == "charging", done.contains(new.state.lowercased()) {
                present(PillEvent(kind: .vehicles, place: device, detail: "Finished charging", symbol: "bolt.car.fill",
                                  tint: Theme.ok, page: "vehicles", actionSymbol: "car.side.fill", actionLabel: "See vehicles"))
            }
        case "climate":
            let c = Climate(e: new), was = Climate(e: old)
            guard c.on, let target = c.target, let room = c.room, let before = was.room else { return }
            let cooling = ["cool", "dry"].contains(new.state), heating = new.state == "heat"
            if (cooling && before > target && room <= target) || (heating && before < target && room >= target) {
                guard let degrees = LivePillClimateReading.text(target) else { return }
                present(PillEvent(kind: .climate, place: Climate.shortName(new.name), detail: "Reached \(degrees)°",
                                  symbol: Theme.modeSymbol(new.state), tint: Theme.air(new.state), page: new.id,
                                  actionSymbol: "thermometer.medium", actionLabel: "Open climate"))
            }
        default:
            break
        }
    }

    private func newActivity(_ items: [ActivityLog.Item]) {
        let fresh = items.filter { !seenItems.contains($0.id) }
        seenItems = Set(items.map(\.id))
        // Pictures arrive a moment after the event; keep the pill's orb up to date.
        if let current = event, current.imagePath == nil,
           let match = items.first(where: { $0.date == current.date && $0.imageFile != nil }) {
            event?.imagePath = match.imageFile
        }
        guard let item = fresh.first(where: { [.doorbell, .person, .security].contains($0.kind) }),
              Date().timeIntervalSince(item.date) < 90 else { return }
        let place = item.place.isEmpty ? (store?.device(of: item.entityID)?.name ?? "Home") : item.place
        switch item.kind {
        case .doorbell:
            let who = item.title.components(separatedBy: " rang ").first.flatMap { $0 == "Someone" ? nil : $0 }
            present(PillEvent(kind: .doorbell, place: store?.device(of: item.entityID)?.name ?? place,
                              detail: who.map { "\($0) is at the door" } ?? "Someone's at the door",
                              symbol: "bell.fill", tint: Theme.sand, date: item.date, imagePath: item.imageFile,
                              page: "security", actionSymbol: "video.fill", actionLabel: "See the door", urgent: true))
        case .person:
            let who = item.title.components(separatedBy: " at ").first.flatMap { $0 == "Person" ? nil : $0 }
            present(PillEvent(kind: .people, place: place, detail: who.map { "\($0) is here" } ?? "Someone's here",
                              symbol: "person.fill", tint: Theme.sand, date: item.date, imagePath: item.imageFile,
                              page: "security", actionSymbol: "video.fill", actionLabel: "See cameras"))
        default:
            present(PillEvent(kind: .alarm, place: place, detail: item.title, symbol: "shield.lefthalf.filled",
                              tint: Theme.ok, date: item.date, page: "security", actionSymbol: "shield.fill", actionLabel: "See alarm"))
        }
    }

    // MARK: Moments outside events

    private func introduceOnce() {
        let key = "livePill.introduced"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.presentSummary(intro: true) }
    }

    /// The menu bar sources and the pill itself, so switching one on can show what it does.
    private static func switches() -> [String: Bool] {
        var out: [String: Bool] = [:]
        for s in StatusLine.Source.allCases { out["status." + s.rawValue] = s.on }
        out["livePill"] = UserDefaults.standard.object(forKey: "livePill") as? Bool ?? true
        return out
    }

    private func switchesChanged() {
        let now = Self.switches()
        defer { defaultsSnapshot = now }
        let turnedOn = now.filter { $0.value && defaultsSnapshot[$0.key] == false }
        guard !turnedOn.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.presentSummary(intro: false) }
    }

    /// A gentle hello: what Hearth is watching, or the line the menu bar has just started showing.
    func presentSummary(intro: Bool) {
        let cams = store?.entities.values.filter { $0.domain == "camera" }.count ?? 0
        let line = statusLine
        let detail = intro
            ? (cams > 0 ? "Watching \(cams) camera\(cams == 1 ? "" : "s") for you" : "Watching your home for you")
            : (line?.text ?? "Live in your menu bar")
        present(PillEvent(kind: .hearth, place: intro ? "Live" : "Menu bar", detail: detail,
                          symbol: line?.symbol ?? "house.fill", tint: Theme.ok, page: nil,
                          actionSymbol: "checkmark", actionLabel: "Got it"), force: true)
    }

    // MARK: Showing

    func present(_ new: PillEvent, force: Bool = false) {
        guard force || (enabled && Self.shows(new.kind)) else { return }
        // Something urgent isn't replaced by something calm.
        if shown, let current = event, current.urgent, !new.urgent { return }
        event = new
        ensurePanel()
        place()
        panel?.orderFrontRegardless()
        withAnimation(AccessibilityDisplay.shared.reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.8)) {
            shown = true
        }
        countDown()
    }

    func dismiss() {
        timer?.cancel()
        withAnimation(AccessibilityDisplay.shared.reduceMotion ? .easeIn(duration: 0.18) : .spring(response: 0.38, dampingFraction: 1)) {
            shown = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, !self.shown else { return }
            self.panel?.orderOut(nil)
        }
    }

    /// Opens Hearth's panel on the event's page.
    func open() {
        let page = event?.page
        dismiss()
        if let page { HearthNavigation.open(page) } else { Self.clickStatusItem() }
    }

    private func countDown() {
        timer?.cancel()
        remaining = Self.duration
        timer = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                // Also catches native menu-extra moves and display changes while
                // hovered. Holding a notification must not freeze its anchor.
                self.refreshAnchor()
                if self.hovering { continue }
                self.remaining -= 0.1
                if self.remaining <= 0 { self.dismiss(); break }
            }
        }
    }

    // MARK: Window

    /// The window leaves room all round so the pill's soft shadow is never clipped to a box.
    static let size = CGSize(width: 456, height: FlashPillGeometry.panelHeight)
    static let pillWidth: CGFloat = 376

    private func ensurePanel() {
        guard panel == nil else { return }
        let p = FlashPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        // Floating sits under the menu bar, so the clear top of this window never
        // covers menu bar items while its capsule shows below them.
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let host = NSHostingView(rootView: LivePillView().environmentObject(self))
        // Only the capsule should show; the rest of the window is fully clear.
        host.wantsLayer = true
        host.layer?.backgroundColor = .clear
        host.layer?.isOpaque = false
        host.layer?.masksToBounds = false
        host.clipsToBounds = false
        p.contentView = host
        panel = p
    }

    /// Reposition only the notification. The main panel owns its fixed opening
    /// anchor; changing a status message never moves that window through here.
    func refreshAnchor() {
        guard panel?.isVisible == true else { return }
        place()
    }

    /// Centred under the actual live capsule, including after its width changes.
    private func place() {
        guard let panel else { return }
        let menu = HearthMenuController.shared
        let item = menu.anchorView?.window
        guard let screen = item?.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let anchor = menu.liveStatusPillFrame ?? item?.frame
            ?? NSRect(x: screen.frame.maxX - 200, y: screen.frame.maxY - 24, width: 40, height: 24)
        let frame = FlashPillGeometry.frame(anchor: anchor, visibleFrame: screen.visibleFrame,
                                           screenFrame: screen.frame, panelWidth: Self.size.width)
        let lift = FlashPillGeometry.bodyLift(anchor: anchor, screenFrame: screen.frame)
        if lift != bodyLift { bodyLift = lift }
        if abs(frame.minX - panel.frame.minX) > 0.5 || abs(frame.minY - panel.frame.minY) > 0.5
            || frame.size != panel.frame.size {
            panel.setFrame(frame, display: true)
        }
    }

    /// Opens the menu bar panel the way a click would.
    static func clickStatusItem() {
        HearthMenuController.shared.open()
    }
}

/// AppKit moves ordinary windows below the menu bar when they are shown or
/// moved. The flash window's clear top deliberately reaches into the menu bar so
/// its capsule can sit just under the status pill; without this, the capsule
/// landed a full menu bar lower than `FlashPillGeometry.frame` placed it.
/// `FlashPillGeometry.frame` already keeps the window on its screen.
final class FlashPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

// MARK: The pill

private struct LivePillView: View {
    @EnvironmentObject var pill: LivePill
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            if let event = pill.event {
                content(event)
                    .frame(width: FlashPillGeometry.interactionWidth(bodyWidth: LivePill.pillWidth), height: FlashPillGeometry.interactionHeight)
                    .opacity(pill.shown ? 1 : 0)
                    .offset(x: -FlashPillGeometry.dismissOverhang / 2,
                            y: FlashPillGeometry.offset(shown: pill.shown, reduceMotion: reduceMotion) - FlashPillGeometry.dismissOverhang)
                    .allowsHitTesting(pill.shown)
                    .accessibilityHidden(!pill.shown)
            }
        }
        .padding(.top, FlashPillGeometry.topPadding - pill.bodyLift)
        .frame(width: LivePill.size.width, height: LivePill.size.height, alignment: .top)
    }

    private func content(_ e: PillEvent) -> some View {
        HStack(spacing: 12) {
            Orb(event: e)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Hearth").font(.system(size: 15, weight: .heavy)).tracking(-0.35)
                    Circle().fill(Theme.faint).frame(width: 3, height: 3)
                    Text(e.place).font(.system(size: 15, weight: .semibold)).tracking(-0.2).lineLimit(1)
                }
                .foregroundStyle(Theme.ink)
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    Text("\(e.detail) · \(Self.ago(e.date, now: context.date))")
                        .font(.system(size: 12.5, weight: .medium)).monospacedDigit()
                        .foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Button(action: pill.open) {
                ZStack {
                    Circle().fill(e.urgent ? AnyShapeStyle(e.tint) : AnyShapeStyle(Theme.fg.opacity(scheme == .dark ? 0.1 : 0.06)))
                    // A thin ring runs down with the time left, and stops while you hover.
                    Circle()
                        .trim(from: 0, to: max(0, pill.remaining / LivePill.duration))
                        .stroke(e.urgent ? Color.white.opacity(0.75) : e.tint.opacity(0.9),
                                style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(1.5)
                        .animation(reduceMotion ? nil : .linear(duration: 0.1), value: pill.remaining)
                    Image(systemName: e.actionSymbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(e.urgent ? Color.white : Theme.ink)
                }
                .frame(width: 42, height: 42)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(e.actionLabel)
            .help(e.actionLabel)
        }
        .padding(.leading, 12)
        .padding(.trailing, 13)
        .frame(width: LivePill.pillWidth, height: FlashPillGeometry.bodyHeight)
        .clipShape(Capsule())
        .background {
            // Isolate backdrop and its mask from foreground text and the dismiss
            // badge. The shadow comes from the capsule silhouette, never a
            // blurred snapshot of the entire notification rectangle.
            Capsule().fill(Theme.base.opacity(scheme == .dark ? 0.55 : 0.5))
                .liquidGlass(in: Capsule())
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(LinearGradient(colors: [Theme.fg.opacity(0.2), Theme.fg.opacity(0.04)],
                                                               startPoint: .top, endPoint: .bottom), lineWidth: 0.75))
                .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.16), radius: FlashPillGeometry.shadowRadius, y: FlashPillGeometry.shadowOffset)
                .shadow(color: .black.opacity(scheme == .dark ? 0.25 : 0.06), radius: 3, y: 1)
                .allowsHitTesting(false)
        }
        // Only the capsule owns the Open gesture. Padding and the dismiss
        // overlay are outside that gesture subtree, so pressing X cannot Open.
        .contentShape(Capsule())
        .onTapGesture(perform: pill.open)
        .padding([.top, .leading], FlashPillGeometry.dismissOverhang)
        .overlay(alignment: .topLeading) {
            if pill.hovering {
                Button(action: pill.dismiss) {
                    Image(systemName: "xmark").font(.system(size: 8.5, weight: .bold)).foregroundStyle(Theme.ink)
                        .frame(width: FlashPillGeometry.dismissSize, height: FlashPillGeometry.dismissSize)
                        .background(Circle().fill(Theme.raised).overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 0.75)))
                }
                .buttonStyle(PressStyle())
                .contentShape(Rectangle())
                .transition(reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
                .accessibilityLabel("Dismiss")
            }
        }
        // The bounded clear corner belongs to hover only. It keeps the badge
        // visible while the pointer crosses from the capsule to the X button.
        .contentShape(Rectangle())
        .onHover { inside in withAnimation(reduceMotion ? nil : .snap) { pill.hovering = inside } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Hearth, \(e.place): \(e.detail)")
    }

    static func ago(_ date: Date, now: Date) -> String {
        let s = max(0, now.timeIntervalSince(date))
        return s < 45 ? "now" : s < 3600 ? "\(Int(s / 60)) min ago" : "\(Int(s / 3600)) h ago"
    }
}

/// The pill's left end: the camera's picture when there is one, otherwise a lit orb.
private struct Orb: View {
    let event: PillEvent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let path = event.imagePath, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).privacyBlurred()
                    .frame(width: 44, height: 44).clipShape(Circle())
                    .overlay(Circle().strokeBorder(event.tint.opacity(0.9), lineWidth: 1.5))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: event.symbol).font(.system(size: 8.5, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 18, height: 18).background(Circle().fill(event.tint))
                            .overlay(Circle().strokeBorder(.black.opacity(0.25), lineWidth: 0.5))
                            .offset(x: 3, y: 3)
                    }
            } else {
                Circle()
                    .fill(RadialGradient(colors: [event.tint.opacity(0.95), event.tint.opacity(0.55)],
                                         center: UnitPoint(x: 0.35, y: 0.3), startRadius: 1, endRadius: 30))
                    .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.45), .clear], startPoint: .top, endPoint: .center))
                        .padding(3).blur(radius: 1.5))
                    .frame(width: 40, height: 40)
                    .shadow(color: event.tint.opacity(0.55), radius: 10)
                Image(systemName: event.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
            }
            if event.urgent {
                TimelineView(.animation(paused: reduceMotion)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                    Circle().strokeBorder(event.tint, lineWidth: 1.5)
                        .frame(width: 44, height: 44)
                        .scaleEffect(1 + t * 0.35)
                        .opacity(reduceMotion ? 0 : 1 - t)
                }
            }
        }
        .frame(width: 46, height: 46)
        .accessibilityHidden(true)
    }
}

// MARK: Settings

/// The Live pill, the menu bar pill and the desktop widgets.
struct PillAndWidgetSettings: View {
    @EnvironmentObject var store: HomeStore
    @AppStorage("livePill") private var livePill = true
    @AppStorage("livePill.off") private var off = ""
    @AppStorage("desktopWidgets") private var widgets = false
    @AppStorage("desktopWidgets.off") private var widgetsOff = ""
    @AppStorage("desktopWidgets.climateEntity") private var widgetClimate = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LIVE PILL").eyebrow().padding(.leading, 4)
            Bezel(radius: 18, inset: 3) {
                VStack(spacing: 0) {
                    toggleRow("Show event updates", "capsule.inset.filled", $livePill)
                    if livePill {
                        ChipsRow(options: PillEvent.Kind.allCases.filter { $0 != .hearth }.map { ($0.rawValue, $0.title, $0.symbol) },
                                 off: $off)
                            .padding(.horizontal, 12).padding(.bottom, 12).padding(.top, 6)
                            .transition(.opacity)
                    }
                    settingsDivider
                    HStack {
                        Text("Sample event").font(.system(size: 13, weight: .medium))
                        Spacer()
                        Button("Preview") { LivePill.shared.presentSummary(intro: true) }
                            .buttonStyle(PressStyle())
                            .font(.system(size: 12.5, weight: .semibold))
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Capsule().fill(Theme.fg.opacity(0.07)))
                    }
                    .padding(.horizontal, 12).frame(height: 40)
                }
            }
            .animation(.settle, value: livePill)

            Text("DESKTOP WIDGETS").eyebrow().padding(.leading, 4).padding(.top, 12)
            Bezel(radius: 18, inset: 3) {
                VStack(spacing: 0) {
                    toggleRow("Show desktop widgets", "rectangle.3.group", $widgets)
                    if widgets {
                        settingsDivider
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            ForEach(DesktopWidgetKind.allCases) { kind in widgetChoice(kind) }
                        }
                            .padding(12)
                            .transition(.opacity)
                        settingsDivider
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Climate source").font(.system(size: 12.5, weight: .medium))
                            Picker("Climate source", selection: $widgetClimate) {
                                Text("Automatic").tag("")
                                ForEach(widgetClimates) { entity in Text(entity.name).tag(entity.id) }
                                if !widgetClimate.isEmpty && !widgetClimates.contains(where: { $0.id == widgetClimate }) {
                                    Text("Saved AC · unavailable").tag(widgetClimate)
                                }
                            }
                            .labelsHidden().pickerStyle(.menu).controlSize(.regular)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Automatic prefers a running AC.")
                                .font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }.padding(12)
                    }
                }
            }
            .animation(.settle, value: widgets)
            if widgets {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Click to open. Drag the handle to move, or the corner to resize.")
                    Text("Live while Hearth is open.")
                }
                .font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                .padding(.horizontal, 4).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: widgets) { _, _ in DesktopWidgets.shared.refresh() }
        .onChange(of: widgetsOff) { _, _ in DesktopWidgets.shared.refresh() }
    }

    private var widgetClimates: [Entity] {
        store.entities.values.filter { $0.domain == "climate" && !DeviceKind.vehicles.contains(store.homeDevice(store.registry[$0.id]?.deviceID ?? "")?.kind ?? .generic) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var settingsDivider: some View {
        Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.horizontal, 12)
    }

    private func widgetChoice(_ kind: DesktopWidgetKind) -> some View {
        let disabled = Set(widgetsOff.split(separator: ",").map(String.init))
        let selected = !disabled.contains(kind.rawValue)
        return Button {
            var next = disabled
            if selected { next.insert(kind.rawValue) } else { next.remove(kind.rawValue) }
            widgetsOff = next.sorted().joined(separator: ",")
        } label: {
            HStack(spacing: 8) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? Theme.brand : Theme.muted)
                    .frame(width: 18)
                Text(kind.title).font(.system(size: 12, weight: .semibold))
                    .lineLimit(2).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(selected ? Theme.brand : Theme.faint)
            }
            .padding(.horizontal, 10).frame(height: 46)
            .foregroundStyle(selected ? Theme.ink : Theme.muted)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(selected ? Theme.brand.opacity(0.09) : Theme.fg.opacity(0.025)))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(selected ? Theme.brand.opacity(0.28) : Theme.hairline, lineWidth: 0.75))
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(kind.title)
        .accessibilityValue(selected ? "Shown" : "Hidden")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func toggleRow(_ title: String, _ symbol: String, _ on: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(Theme.muted).frame(width: 18)
            Text(title).font(.system(size: 13, weight: .medium))
            Spacer()
            Toggle(title, isOn: on).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
    }
}

/// A wrapping row of on/off chips, stored as a comma list of the ones turned off.
private struct ChipsRow: View {
    let options: [(key: String, title: String, symbol: String)]
    @Binding var off: String

    var body: some View {
        let set = Set(off.split(separator: ",").map(String.init))
        FlowLayout(spacing: 8) {
            ForEach(options, id: \.key) { option in
                let on = !set.contains(option.key)
                Button {
                    var s = set
                    if on { s.insert(option.key) } else { s.remove(option.key) }
                    off = s.sorted().joined(separator: ",")
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: option.symbol).font(.system(size: 10.5, weight: .semibold))
                        Text(option.title).font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(on ? Theme.ink : Theme.muted)
                    .padding(.horizontal, 10).frame(height: 28)
                    .background(Capsule().fill(on ? Theme.fg.opacity(0.1) : Color.clear))
                    .overlay(Capsule().strokeBorder(on ? Theme.cardEdge : Theme.hairline, lineWidth: 0.75))
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// Lays children out left to right, wrapping onto new lines.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += s.width + spacing
            row = max(row, s.height)
        }
        return CGSize(width: width, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            row = max(row, s.height)
        }
    }
}
