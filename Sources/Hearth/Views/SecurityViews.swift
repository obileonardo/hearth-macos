import SwiftUI

/// The front door live, the alarm, then every other camera with its latest picture.
struct SecurityPage: View {
    @EnvironmentObject var store: HomeStore
    @Environment(\.hearthOpenWindow) private var openWindow
    let alarms: [Entity]
    let cameras: [Entity]
    let shown: Bool
    /// False while the menu bar panel is closed, so live video doesn't run unseen.
    let visible: Bool

    @AppStorage("camera.refresh") private var refreshSeconds = 60.0
    /// Familiar faces, shown in place of the cameras. `-openFaces YES` opens it, for checking.
    @State private var showFaces = UserDefaults.standard.bool(forKey: "openFaces")
    @State private var updated = Date.distantPast
    @State private var refreshing = false

    /// The doorbell leads; failing that, the first camera.
    private var hero: Entity? {
        cameras.first { cam in
            let dev = store.registry[cam.id]?.deviceID.flatMap { store.homeDevice($0) }
            return dev?.kind == .doorbell
        } ?? cameras.first
    }

    var body: some View {
        if showFaces {
            FacesPage(back: { withAnimation(.glide) { showFaces = false } })
                .transition(.dissolve)
        } else {
            cameraPage.transition(.dissolve)
        }
    }

    /// Use the same native illustrations as the camera cards; never camera footage.
    private var cameraIllustrations: [DeviceKind] {
        cameras.prefix(3).map { camera in
            let kind = store.registry[camera.id]?.deviceID.flatMap { store.homeDevice($0)?.kind }
            guard let kind, [.indoorCamera, .outdoorCamera, .doorbell].contains(kind) else { return .outdoorCamera }
            return kind
        }
    }

    private var cameraPage: some View {
        let rest = cameras.filter { $0.id != hero?.id }
        return VStack(alignment: .leading, spacing: 14) {
            PageHeader(eyebrow: eyebrow, title: "Security",
                       pinnedIllustrations: cameraIllustrations, pinnedCount: cameras.count) {
                Button { withAnimation(.glide) { showFaces = true } } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 13, weight: .regular))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Theme.fg.opacity(0.05)).overlay(Circle().strokeBorder(Theme.hairline)))
                }
                .buttonStyle(PressStyle())
                .help("Familiar faces")
                .accessibilityLabel("Familiar faces")
                Button { Task { await refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .regular))
                        .rotationEffect(.degrees(refreshing ? 360 : 0))
                        .animation(refreshing ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default, value: refreshing)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Theme.fg.opacity(0.05)).overlay(Circle().strokeBorder(Theme.hairline)))
                }
                .buttonStyle(PressStyle())
                .help("Refresh the pictures")
                .accessibilityLabel("Refresh the pictures")
            }
            .reveal(shown, 0)

            if let hero {
                HeroCamera(entity: hero, live: visible) {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "camera", value: hero.id)
                }
                .reveal(shown, 1)
            }

            // Hubs: every base station, the ones holding cameras first, with its alarm or guard mode.
            let hubs = store.devices.values
                .compactMap { store.homeDevice($0.id) }
                .filter { [.securityHub, .securityHubPro].contains($0.kind) }
                .map { (hub: $0, cameras: store.cameras(onHub: $0.id).count) }
                .sorted { ($0.cameras, $1.hub.name) > ($1.cameras, $0.hub.name) }
            if !hubs.isEmpty {
                Text(hubs.count == 1 ? "HUB" : "HUBS").eyebrow().padding(.leading, 4).reveal(shown, 2)
                ForEach(Array(hubs.enumerated()), id: \.element.hub.id) { i, item in
                    HubCard(hub: item.hub, cameras: item.cameras).reveal(shown, 2 + i)
                }
            }
            // Alarm panels that don't belong to a hub device.
            ForEach(Array(alarms.filter { a in !hubs.contains { $0.hub.entities.contains { $0.id == a.id } } }.enumerated()), id: \.element.id) { i, alarm in
                AlarmControl(entity: alarm).reveal(shown, 3 + i)
            }

            if !rest.isEmpty {
                Text("CAMERAS").eyebrow().padding(.leading, 4).reveal(shown, 3)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(Array(rest.enumerated()), id: \.element.id) { i, cam in
                        GridCamera(entity: cam) {
                            NSApp.activate(ignoringOtherApps: true)
                            openWindow(id: "camera", value: cam.id)
                        }
                        .reveal(shown, 4 + i)
                    }
                }
            }
        }
        .task(id: visible) {
            guard visible else { return }
            while !Task.isCancelled {
                if Date().timeIntervalSince(updated) >= UpdateIntervalPreference.cameraRefresh.seconds(for: refreshSeconds) - 1 { await refresh() }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private var eyebrow: String {
        let ago = updated == .distantPast ? "" : " · updated \(updated.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))"
        return "\(cameras.count) camera\(cameras.count == 1 ? "" : "s")\(ago)"
    }

    /// Every camera's picture: the event image where a camera keeps one, otherwise a snapshot.
    private func refresh() async {
        refreshing = true
        await withTaskGroup(of: Void.self) { group in
            for cam in cameras where cam.id != hero?.id {
                group.addTask { @MainActor in
                    if let img = eventImage(for: cam) { _ = await store.image(img) }
                    _ = await store.snapshot(cam.id)
                }
            }
        }
        updated = Date()
        refreshing = false
    }

    private func eventImage(for camera: Entity) -> String? {
        guard let dev = store.registry[camera.id]?.deviceID else { return nil }
        return store.entities.keys.first { $0.hasPrefix("image.") && $0.hasSuffix("event_image") && store.registry[$0]?.deviceID == dev }
    }
}

/// A base station: its illustration, what mode it's in, and the controls it offers.
struct HubCard: View {
    @EnvironmentObject var store: HomeStore
    let hub: HomeDevice
    /// How many cameras are paired with it.
    let cameras: Int

    var body: some View {
        let alarm = hub.first("alarm_control_panel")
        let guardMode = hub.entity(key: "guard_mode")
        let mode = [hub.entity(key: "current_mode")?.state, alarm?.state].compactMap { $0 }.first { !["unknown", "unavailable"].contains($0) }
        Bezel(radius: 22, inset: 3, lit: hub.online && alarm.map { $0.state != "disarmed" } == true, tint: Theme.ok) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    DeviceArtView(kind: hub.kind, active: hub.online, accent: Theme.ok, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hub.name).font(.system(size: 14, weight: .semibold))
                        HStack(spacing: 5) {
                            PulseDot(color: hub.online ? Theme.ok : Theme.live, size: 5, live: hub.online)
                            Text(hub.online ? (mode.map { $0.replacingOccurrences(of: "_", with: " ").capitalized } ?? "Online") : "Offline")
                                .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.muted)
                        }
                        Text([hub.info.manufacturer, hub.info.model, cameras == 0 ? "No cameras" : "\(cameras) camera\(cameras == 1 ? "" : "s")"]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.faint)
                    }
                    Spacer()
                }
                if let alarm {
                    AlarmControl(entity: alarm, showsHeader: false)
                }
                if let guardMode {
                    EntityControl(entity: guardMode, copy: EntityCatalog.copy(for: guardMode, deviceName: hub.name), tint: Theme.ok)
                        .padding(.horizontal, -12)
                }
                if alarm == nil && guardMode == nil {
                    Text(cameras > 0
                         ? "Eufy doesn't let other apps change this hub's mode yet, so switch Home, Away or Disarmed in the Eufy app. Its cameras are below."
                         : "This hub doesn't offer any controls to Home Assistant yet.")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
        }
    }
}

/// The lead camera, live while the panel is open.
struct HeroCamera: View {
    @EnvironmentObject var store: HomeStore
    let entity: Entity
    let live: Bool
    let expand: () -> Void
    /// Its top edge has slid under the pinned title.
    @State private var underTitle = false

    var body: some View {
        let device = store.registry[entity.id]?.deviceID.flatMap { store.homeDevice($0) }
        ZStack(alignment: .bottomLeading) {
            Color.black
            if live {
                LiveVideoView(entityID: entity.id, covered: underTitle)
            } else if let image = store.snapshots[entity.id] {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).privacyBlurred()
                    .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            }
            LinearGradient(colors: [.black.opacity(0.35), .clear, .clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
            VStack {
                HStack {
                    // While live, the video shows its own badge with the real connection state.
                    if !live {
                        HStack(spacing: 5) {
                            PulseDot(color: Theme.live, size: 5, live: false)
                            Text("PAUSED").font(.system(size: 11, weight: .bold)).tracking(1.2)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(.black.opacity(0.45)))
                    }
                    Spacer()
                    Button(action: expand) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 11.5, weight: .semibold))
                            .frame(width: 26, height: 26).background(Circle().fill(.black.opacity(0.45)))
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Open camera in a window")
                }
                Spacer()
                HStack(spacing: 8) {
                    if let device {
                        DeviceArtView(kind: device.kind, active: true, accent: device.accent, size: 26)
                            .background(Circle().fill(.black.opacity(0.4)))
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(device?.name ?? entity.name).font(.system(size: 14, weight: .semibold))
                        if let last = lastMotion(device) {
                            Text("Last motion \(last)").font(.system(size: 12)).foregroundStyle(Theme.fg.opacity(0.7))
                        }
                    }
                    Spacer()
                    PrivacyBlurControl()
                }
            }
            .padding(12)
        }
        .aspectRatio(16 / 10, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(LinearGradient(colors: [Theme.fg.opacity(0.22), Theme.fg.opacity(0.03)], startPoint: .top, endPoint: .bottom), lineWidth: 0.75))
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.fg.opacity(0.025))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.75)))
        .background(GeometryReader { g in
            Color.clear.onChange(of: g.frame(in: .named(PinnedTitleBar.space)).minY < PinnedTitleBar.height, initial: true) { _, now in
                underTitle = now
            }
        })
        .task(id: entity.id) { if store.snapshots[entity.id] == nil { _ = await store.snapshot(entity.id) } }
        // A screen: dark in either appearance, so white text on the picture stays legible.
        .environment(\.colorScheme, .dark)
    }

    private func lastMotion(_ device: HomeDevice?) -> String? {
        let candidates = device?.entities.filter { ($0.domain == "event" && $0.str("device_class") == "motion") || ($0.domain == "binary_sensor" && $0.str("device_class") == "motion") } ?? []
        let dates = candidates.compactMap { e -> Date? in
            if e.domain == "event" {
                let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return f.date(from: e.state) ?? ISO8601DateFormatter().date(from: e.state)
            }
            return e.lastChanged
        }
        return dates.max()?.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }
}

/// A camera in the grid: its last event picture, its name and when it last saw movement.
struct GridCamera: View {
    static let unreachableNote = "This camera is on a HomeBase Professional, which Home Assistant can't reach yet. Its status comes from Eufy's cloud and may be out of date, and it can't be paused from here."
    @EnvironmentObject var store: HomeStore
    @EnvironmentObject var log: ActivityLog
    let entity: Entity
    let open: () -> Void

    var body: some View {
        let device = store.registry[entity.id]?.deviceID.flatMap { store.homeDevice($0) }
        let eventImage = device?.entities.first { $0.domain == "image" && $0.id.hasSuffix("event_image") }
        // The live picture, or failing that the last one Hearth kept from this camera's events,
        // so a bridge restart (which forgets event pictures) never leaves the grid blank.
        let saved = device.flatMap { d in
            log.items.first { $0.imageFile != nil && store.registry[$0.entityID]?.deviceID == d.id }
        }
        let picture = eventImage.flatMap { store.snapshots[$0.id] } ?? store.snapshots[entity.id]
            ?? saved.flatMap { $0.imageFile }.flatMap { NSImage(contentsOfFile: $0) }
        let motion = device?.entities.first { $0.domain == "binary_sensor" && $0.id.hasSuffix("motion_detected") }
        let person = device?.entities.first { $0.domain == "binary_sensor" && $0.id.hasSuffix("person_detected") }
        let active = person?.state == "on" || motion?.state == "on"
        let cloudSaysOff = device?.entity(key: "camera_enabled")?.state == "off"
        // On a hub Home Assistant can't reach, the on/off state is Eufy's cloud copy and may be stale.
        let unreachable = device.map { store.isOnUnreachableHub($0.id) } ?? false
        // A camera that has just sent motion is on, whatever Eufy's cloud copy says.
        let heardFrom = device.flatMap { d in log.items.first { store.registry[$0.entityID]?.deviceID == d.id }?.date }
        let recentlyActive = heardFrom.map { Date().timeIntervalSince($0) < 15 * 60 } ?? false
        let off = cloudSaysOff && !(unreachable && recentlyActive)

        Button(action: open) {
            // The card sets the size; the picture fills it and is cut to it, so a wide
            // picture can't push the card wider than its column.
            // A screen's own dark, the same in either appearance.
            Color(red: 0.075, green: 0.075, blue: 0.085)
                .aspectRatio(16 / 11, contentMode: .fit)
                .overlay {
                    if let picture {
                        Image(nsImage: picture).resizable().aspectRatio(contentMode: .fill).privacyBlurred()
                    } else if let device {
                        DeviceArtView(kind: device.kind, active: !off, accent: device.accent, size: 54)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    ZStack(alignment: .bottomLeading) {
                        LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 5) {
                                PulseDot(color: off ? Theme.faint : active ? Theme.sand : Theme.live, size: 5, live: !off)
                                Text(device?.name ?? entity.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                            }
                            Text(off ? (unreachable ? "Off, per Eufy's cloud" : "Camera off") : active ? (person?.state == "on" ? "Person now" : "Movement now")
                                 : (motion?.lastChanged).map { "Motion \($0.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))" } ?? "Watching")
                                .font(.system(size: 11)).foregroundStyle(Theme.fg.opacity(0.7))
                        }
                        .padding(9)
                    }
                }
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(active ? Theme.sand.opacity(0.7) : Theme.fg.opacity(0.12), lineWidth: active ? 1.2 : 0.75))
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.fg.opacity(0.025))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.75)))
        }
        .buttonStyle(PressStyle())
        .overlay(alignment: .topTrailing) {
            if let toggle = device?.entity(key: "camera_enabled"), !unreachable {
                CameraPauseButton(entity: toggle, cameraName: device?.name ?? entity.name).padding(10)
            } else if unreachable {
                PanelInfoButton(message: Self.unreachableNote)
                    .padding(10)
            }
        }
        // A screen: dark in either appearance, like the camera tiles in Apple's Home.
        .environment(\.colorScheme, .dark)
    }
}

/// Pauses a camera (privacy mode) or turns it back on, through its "camera enabled" switch.
/// It waits for the camera to confirm, and says so plainly when it doesn't.
struct CameraPauseButton: View {
    @EnvironmentObject var store: HomeStore
    let entity: Entity
    let cameraName: String
    var compact = true
    @State private var waitingFor: String?
    @State private var unanswered = false
    @State private var commandFailure: String?

    var body: some View {
        let on = entity.state == "on"
        Button(action: toggle) {
            HStack(spacing: 5) {
                if waitingFor != nil {
                    ProgressView().controlSize(.mini).tint(Theme.ink)
                } else {
                    Image(systemName: unanswered ? "exclamationmark.triangle.fill" : on ? "pause.fill" : "play.fill")
                        .font(.system(size: 10, weight: .bold))
                }
                if unanswered {
                    Text("No reply").font(.system(size: 11, weight: .semibold))
                } else if !compact {
                    Text(waitingFor != nil ? (waitingFor == "off" ? "Pausing" : "Turning on") : on ? "Pause camera" : "Turn camera on")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundStyle(unanswered ? Theme.live : Theme.ink)
            .padding(.horizontal, compact && !unanswered ? 0 : 10)
            .frame(minWidth: 26, minHeight: 26)
            .background(Capsule().fill(.black.opacity(0.55)).overlay(Capsule().strokeBorder(Theme.fg.opacity(0.14), lineWidth: 0.75)))
        }
        .buttonStyle(PressStyle())
        .disabled(waitingFor != nil || entity.isUnavailable)
        .panelTooltip(unanswered ? commandFailure ?? "\(cameraName) didn't respond. Its hub may not accept commands from Home Assistant."
              : on ? "Pause \(cameraName) (privacy mode)" : "Turn \(cameraName) back on")
        .accessibilityLabel(on ? "Pause \(cameraName)" : "Turn \(cameraName) back on")
        .onChange(of: entity.state) { _, now in
            if now == waitingFor { waitingFor = nil; unanswered = false; commandFailure = nil }
        }
        .animation(.snap, value: waitingFor)
        .animation(.snap, value: unanswered)
    }

    private func toggle() {
        let target = entity.state == "on" ? "off" : "on"
        waitingFor = target
        unanswered = false
        commandFailure = nil
        guard let action = DeviceCommand.power(entity, on: target == "on") else { waitingFor = nil; return }
        store.call(action) { result in
            if case .failure(let error) = result, waitingFor == target {
                waitingFor = nil; unanswered = true; commandFailure = error.localizedDescription
            }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(15))
            guard waitingFor == target else { return }
            waitingFor = nil
            unanswered = true
            try? await Task.sleep(for: .seconds(8))
            unanswered = false
        }
    }
}

extension HomeStore {
    /// True when a camera sits on a hub the Eufy library can't talk to (the HomeBase Professional,
    /// T9000), so commands never arrive and its state is only Eufy's cloud copy.
    func isOnUnreachableHub(_ cameraDeviceID: String) -> Bool {
        devices.values.contains { hub in
            (hub.model ?? "").uppercased().hasPrefix("T9000") && cameras(onHub: hub.id).contains(cameraDeviceID)
        }
    }

    /// Eufy's debug sensors carry serial numbers: a station's own, and the station each camera is on.
    private func eufyProperties(ofDevice id: String) -> JSON? {
        entities.values.first {
            registry[$0.id]?.deviceID == id && ($0.id.hasSuffix("_debug_station") || $0.id.hasSuffix("_debug_device"))
        }?.attributes["properties"] as? JSON
    }

    /// The devices whose cameras sit on a hub.
    func cameras(onHub hubID: String) -> [String] {
        guard let serial = eufyProperties(ofDevice: hubID)?["serialNumber"] as? String else { return [] }
        return devices.keys.filter { $0 != hubID && eufyProperties(ofDevice: $0)?["stationSerialNumber"] as? String == serial }
    }
}
