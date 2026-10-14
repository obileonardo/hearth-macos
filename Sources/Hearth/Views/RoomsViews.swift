import SwiftUI

/// Where you are inside the Rooms tab.
enum RoomRoute: Hashable {
    case room(String?)
    case device(String)
}

/// Rooms by floor, then a room's devices, then one device's settings.
struct RoomsPage: View {
    @EnvironmentObject var store: HomeStore
    let shown: Bool
    @Binding var path: [RoomRoute]

    var body: some View {
        ScreenFlow(route: path, depth: path.count) { shownPath in
            switch shownPath.last {
            case nil:
                RoomsOverview(shown: shown) { push(.room($0)) }
            case .room(let id):
                RoomDetail(areaID: id, back: pop) { push(.device($0)) }
            case .device(let id):
                DeviceDetail(deviceID: id, back: pop).id(id)
            }
        }
    }

    private func push(_ r: RoomRoute) { withAnimation(.glide) { path.append(r) } }
    private func pop() { withAnimation(.glide) { _ = path.popLast() } }
}

/// Maps Home Assistant's room icons (and failing that, room names) to SF Symbols.
enum RoomStyle {
    static func symbol(_ area: Area?) -> String {
        let icon = (area?.icon ?? "").replacingOccurrences(of: "mdi:", with: "")
        let name = (area?.name ?? "").lowercased()
        let table: [(String, String)] = [
            ("sofa", "sofa.fill"), ("living", "sofa.fill"), ("stove", "frying.pan.fill"), ("kitchen", "frying.pan.fill"),
            ("cog", "wrench.and.screwdriver.fill"), ("lab", "wrench.and.screwdriver.fill"),
            ("bed", "bed.double.fill"), ("chair-rolling", "chair.fill"), ("office", "chair.fill"), ("desk", "desktopcomputer"),
            ("outdoor", "tree.fill"),
            ("garden", "leaf.fill"), ("yard", "tree.fill"), ("garage", "car.fill"), ("bath", "bathtub.fill"),
            ("dining", "fork.knife"), ("stairs", "stairs"), ("entrance", "door.left.hand.open"), ("door", "door.left.hand.open"),
        ]
        for (needle, symbol) in table where icon.contains(needle) || name.contains(needle) { return symbol }
        return area == nil ? "tray.fill" : "square.grid.2x2.fill"
    }

    static func tint(_ area: Area?) -> Color {
        let palette: [Color] = [
            Color.accent(0.86, 0.78, 0.66), Color.accent(0.62, 0.84, 1.0),
            Color.accent(0.72, 0.9, 0.7), Color.accent(0.95, 0.72, 0.62),
            Color.accent(0.8, 0.76, 1.0), Color.accent(0.6, 0.92, 0.86),
        ]
        let seed = (area?.id ?? "none").unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xffff }
        return palette[seed % palette.count]
    }
}

// MARK: Overview

struct RoomsOverview: View {
    @EnvironmentObject var store: HomeStore
    let shown: Bool
    let open: (String?) -> Void

    private struct FloorGroup: Identifiable {
        let id: String
        let name: String?
        let rooms: [Area?]
    }

    private var groups: [FloorGroup] {
        let rooms = store.areas.values.filter { !store.devices(inArea: $0.id).isEmpty }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        var result: [FloorGroup] = store.floors.compactMap { floor in
            let here = rooms.filter { $0.floorID == floor.id }
            return here.isEmpty ? nil : FloorGroup(id: floor.id, name: floor.name, rooms: here)
        }
        var loose: [Area?] = rooms.filter { r in !store.floors.contains { $0.id == r.floorID } }
        if !store.devices(inArea: nil).isEmpty { loose.append(nil) }
        if !loose.isEmpty { result.append(FloorGroup(id: "other", name: result.isEmpty ? nil : "Elsewhere", rooms: loose)) }
        return result
    }

    var body: some View {
        let total = store.devices.values.filter { !$0.isService && !store.entities(ofDevice: $0.id).isEmpty }.count
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(eyebrow: "\(store.areas.count) rooms · \(total) devices", title: "Rooms") { EmptyView() }
                .reveal(shown, 0)
            ForEach(Array(groups.enumerated()), id: \.element.id) { gi, group in
                VStack(alignment: .leading, spacing: 8) {
                    if let name = group.name { Text(name.uppercased()).eyebrow() }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(Array(group.rooms.enumerated()), id: \.offset) { i, area in
                            RoomCard(area: area) { open(area?.id) }
                                .reveal(shown, 1 + gi * 2 + i)
                        }
                    }
                }
            }
        }
    }
}

struct RoomCard: View {
    @EnvironmentObject var store: HomeStore
    let area: Area?
    let action: () -> Void

    var body: some View {
        let devices = store.homeDevices(inArea: area?.id)
        let tint = RoomStyle.tint(area)
        let temp = roomTemperature(devices)
        let moving = devices.contains { d in d.entities.contains { $0.domain == "binary_sensor" && ($0.str("device_class") == "motion" || $0.str("device_class") == "occupancy") && $0.state == "on" } }
        Button(action: action) {
            Bezel(radius: 22, inset: 3) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        Image(systemName: RoomStyle.symbol(area))
                            .font(.system(size: 15, weight: .light))
                            .foregroundStyle(tint)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(tint.opacity(0.12)))
                            .overlay(Circle().strokeBorder(tint.opacity(0.25), lineWidth: 0.75))
                        Spacer()
                        if let temp {
                            Text(temp).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(area?.name ?? "No room").font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        HStack(spacing: 5) {
                            if moving { PulseDot(color: Theme.ok, size: 5) }
                            Text(moving ? "Movement now" : "\(devices.count) device\(devices.count == 1 ? "" : "s")")
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(moving ? Theme.ok : Theme.muted)
                        }
                    }
                    HStack(spacing: -6) {
                        ForEach(devices.prefix(4)) { d in
                            DeviceArtView(kind: d.kind, active: d.online, accent: d.accent, size: 24)
                                .background(Circle().fill(Theme.raised))
                                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 0.5))
                                .padding(1.5)
                                .background(Circle().fill(Theme.raised))
                        }
                        if devices.count > 4 {
                            Text("+\(devices.count - 4)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                                .frame(width: 24, height: 24).background(Circle().fill(Theme.raised))
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(PressStyle())
    }

    private func roomTemperature(_ devices: [HomeDevice]) -> String? {
        for d in devices {
            if let c = d.first("climate"), let t = c.num("current_temperature") { return "\(Int(t.rounded()))°" }
        }
        for d in devices {
            if let s = d.entities.first(where: { $0.str("device_class") == "temperature" }), let v = Double(s.state) { return "\(Int(v.rounded()))°" }
        }
        return nil
    }
}

// MARK: Room

/// A back button and a title, for pages inside a tab.
struct SubpageHeader<Trailing: View>: View {
    let eyebrow: String
    let title: String
    let back: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Button(action: back) {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.fg.opacity(0.06)).overlay(Circle().strokeBorder(Theme.hairline)))
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Back")
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow.uppercased()).eyebrow()
                Text(title).font(.system(size: 19, weight: .semibold)).tracking(-0.3).lineLimit(1)
            }
            Spacer()
            trailing
        }
        .collapsesInto(eyebrow: eyebrow, title: title, back: back)
    }
}

struct RoomDetail: View {
    @EnvironmentObject var store: HomeStore
    let areaID: String?
    let back: () -> Void
    let open: (String) -> Void

    var body: some View {
        let area = areaID.flatMap { store.areas[$0] }
        let devices = store.homeDevices(inArea: areaID)
        VStack(alignment: .leading, spacing: 14) {
            SubpageHeader(eyebrow: area.flatMap { a in store.floors.first { $0.id == a.floorID }?.name } ?? "Room",
                          title: area?.name ?? "No room", back: back) {
                Image(systemName: RoomStyle.symbol(area)).font(.system(size: 16, weight: .light)).foregroundStyle(RoomStyle.tint(area))
            }
            VStack(spacing: 8) {
                ForEach(devices) { d in
                    DeviceCard(device: d) { open(d.id) }
                }
            }
        }
    }
}

struct DeviceCard: View {
    @EnvironmentObject var store: HomeStore
    let device: HomeDevice
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Bezel(radius: 22, inset: 3, lit: device.online && isActive, tint: device.accent) {
                HStack(spacing: 12) {
                    if device.kind == .electricCar {
                        HomeCarArt(device: device, size: 48)
                    } else {
                        DeviceArtView(kind: device.kind, active: device.online, accent: device.accent, size: 48)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Text(device.summary).font(.system(size: 12.5)).foregroundStyle(device.online ? Theme.muted : Theme.live).lineLimit(1)
                        Text([device.info.manufacturer, device.info.model].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.faint).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if let primary {
                        GlowSwitch(isOn: primary.state == "on", tint: device.accent) {
                            let on = primary.state == "on"
                            store.optimistic(primary.id) { $0.state = on ? "off" : "on" }
                            store.call(primary.domain, on ? "turn_off" : "turn_on", primary.id)
                        }
                    } else {
                        Image(systemName: "chevron.right").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.faint)
                    }
                }
                .padding(10)
            }
        }
        .buttonStyle(PressStyle())
    }

    /// The one switch worth having on the card: a camera's power or detection.
    private var primary: Entity? {
        device.entity(key: "camera_enabled") ?? (device.kind == .doorbell ? device.entity(key: "motion_detection") : nil)
    }

    private var isActive: Bool {
        primary?.state == "on" || device.first("climate").map { Climate(e: $0).on } == true
    }
}

// MARK: Device

struct DeviceDetail: View {
    @EnvironmentObject var store: HomeStore
    @Environment(\.hearthOpenWindow) private var openWindow
    let deviceID: String
    let back: () -> Void

    var body: some View {
        if let device = store.homeDevice(deviceID) {
            content(device)
        }
    }

    private func content(_ device: HomeDevice) -> some View {
        let area = device.info.areaID.flatMap { store.areas[$0] }
        let sections = grouped(device)
        let camera = device.first("camera")
        return VStack(alignment: .leading, spacing: 14) {
            SubpageHeader(eyebrow: area?.name ?? "Device", title: device.name, back: back) { EmptyView() }

            // Hero: the illustration, what it is and what it's doing.
            Bezel(radius: 24, inset: 4, lit: device.online, tint: device.accent) {
                HStack(spacing: 14) {
                    if device.kind == .electricCar {
                        HomeCarArt(device: device, size: 84)
                    } else {
                        DeviceArtView(kind: device.kind, active: device.online, accent: device.accent, size: 84)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.summary).font(.system(size: 15, weight: .semibold))
                        Text([device.info.manufacturer, device.info.model].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                        HStack(spacing: 5) {
                            PulseDot(color: device.online ? Theme.ok : Theme.live, size: 5, live: device.online)
                            Text(device.online ? "Online" : "Offline").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted)
                        }
                        if let camera {
                            Button {
                                NSApp.activate(ignoringOtherApps: true)
                                openWindow(id: "camera", value: camera.id)
                            } label: {
                                Label("Watch live", systemImage: "play.fill")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(Theme.onCTA)
                                    .padding(.horizontal, 11).padding(.vertical, 5)
                                    .background(Capsule().fill(Theme.cta))
                            }
                            .buttonStyle(PressStyle())
                            .padding(.top, 3)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
            }

            if device.kind == .electricCar {
                Bezel(radius: 18, inset: 3) { CarPaintPicker(device: device).padding(12) }
            }
            if let alarm = device.first("alarm_control_panel") {
                AlarmControl(entity: alarm)
            }
            if let climate = device.first("climate") {
                Text("Open \(Climate.shortName(climate.name)) from the dock for the full air conditioner controls.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
            }

            ForEach(sections, id: \.0) { group, items in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.rawValue.uppercased()).eyebrow().padding(.leading, 4)
                    Bezel(radius: 20, inset: 3) {
                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.0.id) { i, item in
                                EntityControl(entity: item.0, copy: item.1, tint: device.accent)
                                if i < items.count - 1 { Rectangle().fill(Theme.hairline).frame(height: 0.75).padding(.leading, 51) }
                            }
                        }
                    }
                }
            }
        }
    }

    /// The device's entities as labelled sections, without the noise.
    private func grouped(_ device: HomeDevice) -> [(ControlGroup, [(Entity, EntityCopy)])] {
        var buckets: [ControlGroup: [(Entity, EntityCopy)]] = [:]
        for e in device.entities where !["camera", "climate", "alarm_control_panel", "image"].contains(e.domain) {
            let copy = EntityCatalog.copy(for: e, deviceName: device.name)
            guard !copy.hidden else { continue }
            buckets[copy.group, default: []].append((e, copy))
        }
        return ControlGroup.allCases.compactMap { g in
            guard let items = buckets[g], !items.isEmpty else { return nil }
            return (g, items.sorted { order($0.0) < order($1.0) })
        }
    }

    /// Switches first, then sliders and pickers, then readings.
    private func order(_ e: Entity) -> Int {
        ["notify": 0, "media_player": 0, "switch": 1, "select": 2, "number": 3, "button": 5][e.domain] ?? 4
    }
}
