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
    @StateObject private var explorer = RoomsExplorerState()

    var body: some View {
        ScreenFlow(route: path, depth: path.count) { shownPath in
            switch shownPath.last {
            case nil:
                RoomsOverview(shown: shown, explorer: explorer, open: { push(.room($0)) }, openDevice: { push(.device($0)) })
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

/// Stores only the presentation choice; floor and room navigation never changes HA assignments.
enum RoomsLayoutPreference: String, CaseIterable {
    case overview, interactive
    static let key = "rooms.layout"
    static func saved(_ value: String) -> Self { Self(rawValue: value) ?? .overview }
}

enum RoomsFloorScope: Hashable {
    case all
    case floor(String)
    case unassigned
}

/// Kept by RoomsPage so opening a device and returning preserves the chosen floor and room.
@MainActor
final class RoomsExplorerState: ObservableObject {
    @Published var floorScope: RoomsFloorScope = .all
    @Published var selectedRoom: RoomsExplorerItem?
}

enum RoomsExplorerItem: Hashable, Identifiable {
    case area(String)
    case unassigned
    var id: Self { self }
    var areaID: String? {
        if case .area(let id) = self { return id }
        return nil
    }
}

/// Registry-based navigation only. Room ordering never implies a measured floor plan.
enum RoomsExplorerNavigation {
    static func floors(_ floors: [Floor]) -> [Floor] {
        floors.sorted {
            if $0.level != $1.level { return $0.level < $1.level }
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }
    }

    static func hasUnassignedRooms(_ areas: [Area], floors: [Floor], hasUnassignedDevices: Bool) -> Bool {
        let known = Set(floors.map(\.id))
        return hasUnassignedDevices || areas.contains { $0.floorID.map { !known.contains($0) } ?? true }
    }

    static func resolvedScope(_ preferred: RoomsFloorScope, floors: [Floor], hasUnassignedRooms: Bool) -> RoomsFloorScope {
        switch preferred {
        case .all: return .all
        case .floor(let id): return floors.contains { $0.id == id } ? preferred : .all
        case .unassigned: return hasUnassignedRooms ? .unassigned : .all
        }
    }

    static func items(areas: [Area], floors: [Floor], scope: RoomsFloorScope,
                      hasUnassignedDevices: Bool) -> [RoomsExplorerItem] {
        let known = Set(floors.map(\.id))
        let rooms = areas.filter { area in
            switch scope {
            case .all: return true
            case .floor(let id): return area.floorID == id
            case .unassigned: return area.floorID.map { !known.contains($0) } ?? true
            }
        }.sorted {
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            return comparison == .orderedSame ? $0.id < $1.id : comparison == .orderedAscending
        }
        var result = rooms.map { RoomsExplorerItem.area($0.id) }
        if hasUnassignedDevices && (scope == .all || scope == .unassigned) { result.append(.unassigned) }
        return result
    }

    static func selection(_ preferred: RoomsExplorerItem?, in items: [RoomsExplorerItem]) -> RoomsExplorerItem? {
        preferred.flatMap { items.contains($0) ? $0 : nil } ?? items.first
    }
}

struct RoomsOverview: View {
    @EnvironmentObject var store: HomeStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(RoomsLayoutPreference.key) private var savedLayout = RoomsLayoutPreference.overview.rawValue
    let shown: Bool
    @ObservedObject var explorer: RoomsExplorerState
    let open: (String?) -> Void
    let openDevice: (String) -> Void

    private var layout: RoomsLayoutPreference { .saved(savedLayout) }

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
        let devices = store.devices.values.filter { !$0.isService && !store.entities(ofDevice: $0.id).isEmpty }
        let total = devices.count
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(eyebrow: "\(store.areas.count) rooms · \(total) devices", title: "Rooms",
                       pinnedIllustrations: devices.sorted { $0.id < $1.id }.prefix(3).compactMap { store.homeDevice($0.id)?.kind },
                       pinnedCount: total) {
                HStack(spacing: 2) {
                    layoutButton(.overview, symbol: "square.grid.2x2", title: "Rooms overview", index: 0)
                    layoutButton(.interactive, symbol: "rectangle.split.2x1", title: "Interactive rooms", index: 1)
                }
                .slidingSelection(layout == .overview ? 0 : 1, radius: 14)
                .padding(3).background(Capsule().fill(Theme.fg.opacity(0.05)).overlay(Capsule().strokeBorder(Theme.hairline)))
            }
            .reveal(shown, 0)
            if layout == .interactive {
                RoomsExplorer(state: explorer, openRoom: open, openDevice: openDevice)
                    .reveal(shown, 1)
            } else {
                overview
            }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 16) {
            if groups.isEmpty {
                CenteredPageEmptyState {
                    VStack(spacing: 10) {
                        Image(systemName: "door.left.hand.open").font(.system(size: 30, weight: .light))
                            .foregroundStyle(Theme.muted).accessibilityHidden(true)
                        Text(store.areas.isEmpty ? "No rooms yet" : "Your rooms are ready")
                            .font(.system(size: 15, weight: .semibold))
                        Text(store.areas.isEmpty ? "Add rooms and assign devices in Home Assistant to see them here."
                             : "Explore every room in Interactive view, including rooms without devices.")
                            .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        if !store.areas.isEmpty {
                            Button("Explore rooms") { savedLayout = RoomsLayoutPreference.interactive.rawValue }
                                .buttonStyle(PressStyle()).foregroundStyle(Theme.brand)
                        }
                    }
                    .padding(16).frame(maxWidth: .infinity)
                }
            }
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

    private func layoutButton(_ value: RoomsLayoutPreference, symbol: String, title: String, index: Int) -> some View {
        Button { withAnimation(reduceMotion ? nil : .glide) { savedLayout = value.rawValue } } label: {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(layout == value ? Theme.onKey : Theme.muted)
                .frame(width: 28, height: 26).selectionFrame(index)
        }
        .buttonStyle(PressStyle()).help(title).accessibilityLabel(title)
        .accessibilityAddTraits(layout == value ? .isSelected : [])
    }
}

/// Shared dimensions keep cards square and preserve room for strokes and focus rings.
enum RoomStripLayout {
    static let tileSide: CGFloat = 160
    static let spacing: CGFloat = 12
    static let verticalClearance: CGFloat = 8
    static let viewportHeight = tileSide + 2 * verticalClearance
}

/// Select a floor, then a room, while keeping that room's real devices in view.
private struct RoomsExplorer: View {
    @EnvironmentObject var store: HomeStore
    @ObservedObject var state: RoomsExplorerState
    let openRoom: (String?) -> Void
    let openDevice: (String) -> Void

    private var floors: [Floor] { RoomsExplorerNavigation.floors(store.floors) }
    private var hasUnassignedDevices: Bool { !store.devices(inArea: nil).isEmpty }
    private var hasUnassignedRooms: Bool {
        RoomsExplorerNavigation.hasUnassignedRooms(Array(store.areas.values), floors: floors,
                                                   hasUnassignedDevices: hasUnassignedDevices)
    }
    private var scope: RoomsFloorScope {
        RoomsExplorerNavigation.resolvedScope(state.floorScope, floors: floors, hasUnassignedRooms: hasUnassignedRooms)
    }
    private var items: [RoomsExplorerItem] {
        RoomsExplorerNavigation.items(areas: Array(store.areas.values), floors: floors, scope: scope,
                                      hasUnassignedDevices: hasUnassignedDevices)
    }
    private var selection: RoomsExplorerItem? { RoomsExplorerNavigation.selection(state.selectedRoom, in: items) }
    private var floorName: String {
        switch scope {
        case .all: return "All floors"
        case .floor(let id): return floors.first { $0.id == id }?.name ?? "All floors"
        case .unassigned: return "No floor"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text("Browse rooms").font(.system(size: 14, weight: .semibold)).fixedSize()
                Spacer(minLength: 8)
                Menu {
                    Button { chooseFloor(.all) } label: { floorLabel("All floors", selected: scope == .all) }
                    ForEach(floors) { floor in
                        Button { chooseFloor(.floor(floor.id)) } label: {
                            floorLabel(floor.name, selected: scope == .floor(floor.id))
                        }
                    }
                    if hasUnassignedRooms {
                        Button { chooseFloor(.unassigned) } label: { floorLabel("No floor", selected: scope == .unassigned) }
                    }
                } label: {
                    HStack(spacing: 24) {
                        HStack(spacing: 7) {
                            Image(systemName: "square.3.layers.3d").accessibilityHidden(true)
                            Text(floorName).lineLimit(1)
                        }
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).accessibilityHidden(true)
                    }
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12).frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.fg.opacity(0.045)).overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline)))
                }
                // A borderless menu draws its own title and arrow and drops this label's
                // spacing and background; the button style keeps the label as designed.
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                .frame(maxWidth: 200, alignment: .trailing)
                .accessibilityLabel("Floor").accessibilityValue(floorName)
            }
            .frame(minHeight: 40)
            if items.isEmpty {
                CenteredPageEmptyState {
                    emptyState(floors.isEmpty && store.areas.isEmpty ? "No rooms yet" : "No rooms on this floor",
                               detail: "Add rooms and floor assignments in Home Assistant to see them here.")
                }
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .center, spacing: RoomStripLayout.spacing) {
                            ForEach(items) { item in roomTile(item) }
                        }
                        .padding(.horizontal, PanelView.scrollContentInset)
                        .padding(.vertical, RoomStripLayout.verticalClearance)
                        .roomStripMouseDrag()
                    }
                    .frame(height: RoomStripLayout.viewportHeight)
                    .scrollIndicators(.never)
                    .scrollClipDisabled()
                    // The only horizontal edge is the actual panel edge. No
                    // inset rectangular mask clips tiles, corners or focus rings.
                    .padding(.horizontal, -PanelView.scrollContentInset)
                    .accessibilityLabel("Rooms on \(floorName)")
                    .accessibilityHint("Scroll horizontally or drag to browse rooms; select a room to show its devices")
                    Text("Drag or scroll to browse")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.faint)
                        .accessibilityHidden(true)
                }
                ScreenFlow(route: selection) { item in
                    if let item { roomDevices(item) }
                }
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder private func floorLabel(_ title: String, selected: Bool) -> some View {
        if selected { Label(title, systemImage: "checkmark") } else { Text(title) }
    }

    private func chooseFloor(_ value: RoomsFloorScope) {
        state.floorScope = value
        state.selectedRoom = nil
    }

    private func roomTile(_ item: RoomsExplorerItem) -> some View {
        let area = item.areaID.flatMap { store.areas[$0] }
        let devices = store.homeDevices(inArea: item.areaID)
        let selected = item == selection
        let name = area?.name ?? "No room"
        return Button { state.selectedRoom = item } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: RoomStyle.symbol(area)).font(.system(size: 16, weight: .medium))
                        .foregroundStyle(selected ? Theme.brand : Theme.muted)
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.brand)
                        .font(.system(size: 13)).opacity(selected ? 1 : 0).accessibilityHidden(true)
                }
                .frame(height: 22)
                .padding(.bottom, 8)
                Text(name).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 36, alignment: .topLeading)
                Text(roomFloorName(area)).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
                    .frame(height: 14).padding(.top, 3)
                Spacer(minLength: 8)
                HStack(spacing: -4) {
                    ForEach(devices.prefix(3)) { device in
                        DeviceArtView(kind: device.kind, active: device.online, accent: device.accent, size: 24)
                            .frame(width: 26, height: 26)
                    }
                    Spacer(minLength: 4)
                    Text("\(devices.count) \(devices.count == 1 ? "device" : "devices")")
                        .font(.system(size: 10.5, weight: .medium)).monospacedDigit()
                        .foregroundStyle(Theme.muted).lineLimit(1)
                }.frame(height: 26).accessibilityHidden(true)
            }
            .padding(14)
            .frame(width: RoomStripLayout.tileSide, height: RoomStripLayout.tileSide, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(selected ? Theme.brand.opacity(0.08) : Theme.raised))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(selected ? Theme.brand : Theme.hairline, lineWidth: selected ? 1.25 : 0.75))
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(name), \(devices.count) device\(devices.count == 1 ? "" : "s")")
        .accessibilityValue(roomFloorName(area))
        .accessibilityHint("Shows this room’s devices below")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func roomFloorName(_ area: Area?) -> String {
        area?.floorID.flatMap { id in floors.first { $0.id == id }?.name } ?? "No floor"
    }

    private func roomDevices(_ item: RoomsExplorerItem) -> some View {
        let area = item.areaID.flatMap { store.areas[$0] }
        let devices = store.homeDevices(inArea: item.areaID)
        let name = area?.name ?? "No room"
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.system(size: 16, weight: .semibold)).accessibilityAddTraits(.isHeader)
                    Text("\(devices.count) device\(devices.count == 1 ? "" : "s") · \(devices.filter(\.online).count) online")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                Button { openRoom(item.areaID) } label: {
                    Label("Open room", systemImage: "arrow.up.right")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.brand)
                }
                .buttonStyle(PressStyle()).accessibilityLabel("Open \(name)")
            }
            .padding(.top, 4)
            if devices.isEmpty {
                emptyState("No devices in this room", detail: "Assign a device to \(name) in Home Assistant to show it here.")
            } else {
                VStack(spacing: 8) {
                    ForEach(devices) { device in
                        DeviceCard(device: device) { openDevice(device.id) }
                    }
                }
            }
        }
    }

    private func emptyState(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.raised))
    }
}

/// Safe display-only room data; malformed numbers do not become readings.
enum RoomPresentation {
    static func temperature(_ value: Double?) -> String? {
        guard let value, value.isFinite, let rounded = Int(exactly: value.rounded()) else { return nil }
        return "\(rounded)°"
    }

    static func temperature(in devices: [HomeDevice]) -> String? {
        // Prefer a climate's reported room temperature; keep looking when one is invalid.
        for device in devices {
            for entity in device.entities where entity.domain == "climate" {
                if let reading = temperature(entity.num("current_temperature")) { return reading }
            }
        }
        for device in devices {
            for entity in device.entities where entity.str("device_class") == "temperature" {
                if let reading = temperature(Double(entity.state)) { return reading }
            }
        }
        return nil
    }

    static func emptyRoomMessage(name: String?) -> String {
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return "Assign a device to \(name) in Home Assistant to show it here."
        }
        return "Devices without a room assignment in Home Assistant will appear here."
    }
}

struct RoomCard: View {
    @EnvironmentObject var store: HomeStore
    let area: Area?
    let action: () -> Void

    var body: some View {
        let devices = store.homeDevices(inArea: area?.id)
        let tint = RoomStyle.tint(area)
        let temp = RoomPresentation.temperature(in: devices)
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

}

// MARK: Room

/// Decorative previews reflect the destination, never unrelated room controls.
enum SubpageHeadingSymbols {
    static func resolve(eyebrow: String, title: String) -> [String] {
        switch title.lowercased() {
        case "help & support": return ["lifepreserver", "envelope", "ladybug"]
        case "get help": return ["lifepreserver", "envelope"]
        case "report a bug": return ["ladybug", "envelope"]
        case "account": return ["person.crop.circle", "server.rack", "network"]
        case "notifications": return ["bell", "slider.horizontal.3"]
        case "familiar faces": return ["person.crop.circle", "person.2"]
        default:
            switch eyebrow.lowercased() {
            case "home", "main home", "demo home": return ["house", "bolt"]
            case "settings": return ["gearshape"]
            case "help & support": return ["envelope"]
            default: return ["square.grid.2x2"]
            }
        }
    }
}

/// A back button and a title, for pages inside a tab.
struct SubpageHeader<Trailing: View>: View {
    let eyebrow: String
    let title: String
    let back: () -> Void
    var pinnedIllustrations: [DeviceKind] = []
    var pinnedSymbols: [String]? = nil
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(HeadingAccessibility.label(title: title, summary: eyebrow))
            .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing
        }
        .collapsesInto(eyebrow: eyebrow, title: title, back: back, illustrations: pinnedIllustrations,
                       symbols: pinnedSymbols ?? SubpageHeadingSymbols.resolve(eyebrow: eyebrow, title: title))
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
                          title: area?.name ?? "No room", back: back,
                          pinnedSymbols: [RoomStyle.symbol(area), "lightbulb", "thermometer.medium"]) {
                Image(systemName: RoomStyle.symbol(area)).font(.system(size: 16, weight: .light)).foregroundStyle(RoomStyle.tint(area))
                    .accessibilityHidden(true)
            }
            if devices.isEmpty {
                CenteredPageEmptyState {
                    VStack(spacing: 10) {
                        Image(systemName: RoomStyle.symbol(area))
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(Theme.muted).accessibilityHidden(true)
                        Text(area == nil ? "No unassigned devices" : "No devices in this room")
                            .font(.system(size: 15, weight: .semibold))
                        Text(RoomPresentation.emptyRoomMessage(name: area?.name))
                            .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(devices) { d in
                        DeviceCard(device: d) { open(d.id) }
                    }
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
            SubpageHeader(eyebrow: area?.name ?? "Device", title: device.name, back: back,
                          pinnedIllustrations: [device.kind]) { EmptyView() }

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
