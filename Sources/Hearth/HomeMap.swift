import AppKit
import Foundation
import SwiftUI

// MARK: Pins

/// A device placed somewhere in the house: a point in the map's own space, in metres.
struct MapPin: Codable, Identifiable, Equatable {
    /// A Home Assistant device id, `gadget:<uuid>` for a gadget added by hand, or `demo:<name>`.
    var id: String
    var name: String
    /// A `DeviceKind` raw value, for the icon.
    var kind: String
    var x: Float
    var y: Float
    var z: Float
    /// Which floor it's on: 0 is the ground floor. Older maps saved before floors read as 0.
    var floor: Int? = nil

    var isDemo: Bool { id.hasPrefix("demo:") }
    var art: DeviceKind { DeviceKind(rawValue: kind) ?? .generic }
    var position: SIMD3<Float> { SIMD3(x, y, z) }
    var level: Int { floor ?? 0 }
}

/// Which way energy moves through a device on the map.
enum PinRole {
    /// Supplies the house: an inverter, a battery or solar.
    case source
    /// Uses power.
    case load
    /// Nothing known.
    case none
}

// MARK: Floors

/// One storey of a map. The ground floor of a scanned map is the scan itself; upper floors each
/// bring their own scan, kept in the maps folder's `floors` folder.
struct MapFloor: Codable, Identifiable, Equatable {
    var level: Int
    /// What you called it; nil uses Home Assistant's floor of the same level, or Ground, First…
    var name: String?
    /// The file name of this floor's scan in `floors/`, or nil for the map's own scan.
    var scan: String?

    var id: Int { level }

    static func defaultName(_ level: Int) -> String {
        switch level {
        case ..<0: level == -1 ? "Basement" : "Basement \(-level)"
        case 0: "Ground"
        case 1: "First"
        case 2: "Second"
        case 3: "Third"
        default: "Floor \(level)"
        }
    }
}

/// How walls are drawn.
/// What a left-drag does on the map: slide the house about, or turn it over like a ball.
enum DragMode: String, CaseIterable, Identifiable {
    case move, turn
    var id: String { rawValue }
    var title: String { self == .move ? "Move" : "Turn" }
    var symbol: String { self == .move ? "hand.raised" : "rotate.3d" }
}

enum WallMode: String, CaseIterable, Identifiable {
    /// Full height and solid.
    case solid
    /// Full height and frosted, so devices behind them show.
    case seeThrough
    /// Cut at waist height, like an architect's model.
    case cut

    var id: String { rawValue }
    var title: String {
        switch self {
        case .solid: "Solid"
        case .seeThrough: "See-through"
        case .cut: "Cut"
        }
    }
    var symbol: String {
        switch self {
        case .solid: "square.fill"
        case .seeThrough: "square.dashed"
        case .cut: "square.bottomhalf.filled"
        }
    }
}

// MARK: The house

/// The maps you've imported, which one is showing, its floors, and where every device sits in it.
/// With no scan, the demo house shows, with demo devices already placed.
@MainActor
final class HomeMapStore: ObservableObject {
    static let shared = HomeMapStore()

    /// The scan file showing, or nil for the demo house.
    @Published private(set) var current: URL?
    @Published private(set) var pins: [MapPin] = []
    /// The current map's floors, lowest first. Always at least one.
    @Published private(set) var floors: [MapFloor] = [MapFloor(level: 0)]
    /// Show a scan's own colours and textures instead of Hearth's clay.
    @Published var showTextures = UserDefaults.standard.bool(forKey: "map.textures") {
        didSet { UserDefaults.standard.set(showTextures, forKey: "map.textures") }
    }
    @Published var wallMode: WallMode = HomeMapStore.savedWallMode() {
        didSet { UserDefaults.standard.set(wallMode.rawValue, forKey: "map.walls") }
    }
    /// The floor on show, or nil for every floor stacked.
    @Published var floorFilter: Int? = HomeMapStore.savedFloor() {
        didSet {
            UserDefaults.standard.set(floorFilter.map(String.init) ?? "all", forKey: "map.floor")
            if let f = floorFilter { lastFloor = f }
        }
    }
    /// The top-down plan instead of the 3D view.
    @Published var dragMode: DragMode = DragMode(rawValue: UserDefaults.standard.string(forKey: "map.drag") ?? "") ?? .move {
        didSet { UserDefaults.standard.set(dragMode.rawValue, forKey: "map.drag") }
    }
    @Published var planView = UserDefaults.standard.bool(forKey: "map.plan") {
        didSet { UserDefaults.standard.set(planView, forKey: "map.plan") }
    }
    /// The last single floor chosen; the plan shows it when every floor was on show.
    private(set) var lastFloor = 0

    static let folder: URL = {
        let dir = UserDefaults.standard.string(forKey: "mapsFolder").map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Hearth/maps", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Upper floors' scans, kept apart so they don't show up as maps of their own.
    static let floorsFolder: URL = {
        let dir = folder.appendingPathComponent("floors", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let scanTypes = ["usdz", "usd", "usda", "usdc", "obj"]

    var isDemo: Bool { current == nil }
    var title: String { current.map { $0.deletingPathExtension().lastPathComponent } ?? "Demo house" }
    var hasFloors: Bool { floors.count > 1 }

    /// The floors drawn right now: one, or all of them.
    var visibleLevels: [Int] {
        if let f = shownFloor { return [f] }
        return floors.map(\.level)
    }

    /// The single floor on show, if one is: the chosen one, or in the plan, the last one chosen.
    var shownFloor: Int? {
        let levels = floors.map(\.level)
        if let f = floorFilter, levels.contains(f) { return f }
        if planView || !hasFloors { return levels.contains(lastFloor) ? lastFloor : levels.first }
        return nil
    }

    /// Every scan you've imported, newest first.
    var scans: [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files.filter { Self.scanTypes.contains($0.pathExtension.lowercased()) }
            .sorted { modified($0) > modified($1) }
    }

    init() {
        if let f = floorFilter { lastFloor = f }
        // Development: `-mapFile <path>` shows that scan without importing it or changing your choice.
        if let path = UserDefaults.standard.string(forKey: "mapFile"), !path.isEmpty {
            current = URL(fileURLWithPath: path)
            load()
            return
        }
        if let name = UserDefaults.standard.string(forKey: "map.current"), !name.isEmpty {
            let url = Self.folder.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { current = url }
        }
        load()
    }

    private static func savedWallMode() -> WallMode {
        if let raw = UserDefaults.standard.string(forKey: "map.walls"), let mode = WallMode(rawValue: raw) { return mode }
        // Maps from before the three modes only knew cut or full.
        return (UserDefaults.standard.object(forKey: "map.cut") as? Bool ?? true) ? .cut : .solid
    }

    private static func savedFloor() -> Int? {
        guard let raw = UserDefaults.standard.string(forKey: "map.floor"), raw != "all" else { return nil }
        return Int(raw)
    }

    // MARK: Choosing a map

    func show(_ url: URL?) {
        current = url
        UserDefaults.standard.set(url?.lastPathComponent, forKey: "map.current")
        load()
    }

    /// Asks for a scan and copies it into Hearth's folder as a new map.
    func importScan() {
        guard let source = pickScan(title: "Import a scan of your home",
                                    message: "Choose a USDZ from a LiDAR scan (RoomPlan, Polycam, 3D Scanner App) or an OBJ.") else { return }
        var target = Self.folder.appendingPathComponent(source.lastPathComponent)
        var n = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = Self.folder.appendingPathComponent("\(source.deletingPathExtension().lastPathComponent) \(n).\(source.pathExtension)")
            n += 1
        }
        do {
            try FileManager.default.copyItem(at: source, to: target)
            show(target)
        } catch {
            NSLog("Hearth: couldn't import the scan: \(error.localizedDescription)")
        }
    }

    /// Adds a floor above the top one to the scanned map showing, from its own scan.
    func addFloorFromScan() {
        guard let map = current else { return }
        let level = (floors.map(\.level).max() ?? 0) + 1
        guard let source = pickScan(title: "Scan for the \(MapFloor.defaultName(level).lowercased()) floor",
                                    message: "Choose the scan of this floor. Hearth stacks it on top of the floors you have.") else { return }
        let name = "\(map.deletingPathExtension().lastPathComponent)-floor\(level).\(source.pathExtension.lowercased())"
        var target = Self.floorsFolder.appendingPathComponent(name)
        // A failed copy must never erase an existing scan, including an orphaned scan
        // left by an interrupted import. Choose another name before copying.
        var n = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = Self.floorsFolder.appendingPathComponent("\(URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent) \(n).\(source.pathExtension.lowercased())")
            n += 1
        }
        do {
            try FileManager.default.copyItem(at: source, to: target)
            floors.append(MapFloor(level: level, scan: target.lastPathComponent))
            saveLayout()
            floorFilter = level
        } catch {
            NSLog("Hearth: couldn't add the floor: \(error.localizedDescription)")
        }
    }

    /// Takes an upper floor off a scanned map, with its devices.
    func removeFloor(_ level: Int) {
        guard !isDemo, level != 0, let floor = floors.first(where: { $0.level == level }) else { return }
        if let scan = floor.scan { try? FileManager.default.removeItem(at: Self.floorsFolder.appendingPathComponent(scan)) }
        floors.removeAll { $0.level == level }
        pins.removeAll { $0.level == level }
        saveLayout()
        savePins()
        if floorFilter == level { floorFilter = 0 }
    }

    func rename(_ level: Int, to name: String) {
        guard let i = floors.firstIndex(where: { $0.level == level }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        floors[i].name = trimmed.isEmpty ? nil : trimmed
        saveLayout()
    }

    /// The scan file for a floor of the current map.
    func scanURL(for floor: MapFloor) -> URL? {
        if let scan = floor.scan { return Self.floorsFolder.appendingPathComponent(scan) }
        return floor.level == 0 ? current : nil
    }

    /// A floor's name: yours, then Home Assistant's floor at the same level, then Ground, First…
    func name(of level: Int, homeAssistant: [Floor] = []) -> String {
        if let custom = floors.first(where: { $0.level == level })?.name { return custom }
        if isDemo { return DemoHouse.floors.first { $0.level == level }?.name ?? MapFloor.defaultName(level) }
        if let ha = homeAssistant.first(where: { $0.level == level }) { return ha.name }
        return MapFloor.defaultName(level)
    }

    func delete(_ url: URL) {
        for floor in layout(for: url) { if let scan = floor.scan { try? FileManager.default.removeItem(at: Self.floorsFolder.appendingPathComponent(scan)) } }
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: pinsFile(for: url))
        try? FileManager.default.removeItem(at: layoutFile(for: url))
        if current == url { show(nil) }
        objectWillChange.send()
    }

    private func pickScan(title: String, message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = message
        panel.allowedContentTypes = Self.scanTypes.compactMap { .init(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }

    // MARK: Pins

    func place(_ pin: MapPin) {
        pins.removeAll { $0.id == pin.id }
        pins.append(pin)
        savePins()
    }

    func remove(_ id: String) {
        pins.removeAll { $0.id == id }
        savePins()
    }

    func isPinned(_ id: String) -> Bool { pins.contains { $0.id == id } }

    /// The demo house's file changed when it gained a first floor; the old one is read once to keep
    /// any real devices you'd placed.
    private static let demoPins = "demo-house-2.pins.json"
    private static let oldDemoPins = "demo-house.pins.json"

    private func pinsFile(for map: URL?) -> URL {
        map.map { $0.deletingPathExtension().appendingPathExtension("pins.json") }
            ?? Self.folder.appendingPathComponent(Self.demoPins)
    }

    private func layoutFile(for map: URL) -> URL {
        map.deletingPathExtension().appendingPathExtension("layout.json")
    }

    private func layout(for map: URL) -> [MapFloor] {
        guard let data = try? Data(contentsOf: layoutFile(for: map)),
              let saved = try? JSONDecoder().decode([MapFloor].self, from: data), !saved.isEmpty else { return [MapFloor(level: 0)] }
        return saved.sorted { $0.level < $1.level }
    }

    private func load() {
        floors = current.map(layout(for:)) ?? DemoHouse.floors.map { MapFloor(level: $0.level) }
        if let data = try? Data(contentsOf: pinsFile(for: current)),
           let saved = try? JSONDecoder().decode([MapPin].self, from: data) {
            pins = saved
        } else if current == nil {
            // The first time with two floors: the demo devices, plus anything real from before.
            let old = (try? Data(contentsOf: Self.folder.appendingPathComponent(Self.oldDemoPins)))
                .flatMap { try? JSONDecoder().decode([MapPin].self, from: $0) } ?? []
            pins = DemoHouse.pins + old.filter { !$0.isDemo }
        } else {
            pins = []
        }
    }

    private func savePins() {
        if let data = try? JSONEncoder().encode(pins) {
            try? data.write(to: pinsFile(for: current))
        }
    }

    private func saveLayout() {
        guard let map = current, let data = try? JSONEncoder().encode(floors) else { return }
        try? data.write(to: layoutFile(for: map))
    }

    /// Puts the demo devices back where they started, keeping any real devices you placed.
    func resetDemo() {
        guard isDemo else { return }
        pins = DemoHouse.pins + pins.filter { !$0.isDemo }
        savePins()
    }

    private func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

// MARK: Power

/// How much power a pinned device is using, and whether it supplies or uses it.
@MainActor
enum MapPower {
    static func role(of pin: MapPin) -> PinRole {
        switch pin.art {
        case .inverter, .battery, .solarPanel: .source
        default: .load
        }
    }

    /// Watts right now: the device's power sensor, a demo simulation, or nil when nothing says.
    static func watts(_ pin: MapPin, store: HomeStore, now: Date = Date()) -> Double? {
        if pin.isDemo { return DemoHouse.watts(pin, now: now) }
        guard !pin.id.hasPrefix("gadget:") else { return nil }
        let sensors = store.entities(ofDevice: pin.id).filter { $0.domain == "sensor" && !$0.isUnavailable }
        let power = sensors.first { $0.str("device_class") == "power" }
            ?? sensors.first { ["W", "kW"].contains($0.str("unit_of_measurement") ?? "") }
        return EnergyUnits.watts(power).map { abs($0) }
    }

    /// Glow strength from 0 to 1: a few watts is a faint glow, a kilowatt or more is bright.
    static func glow(_ watts: Double?) -> Double {
        guard let w = watts, w > 0 else { return 0 }
        return min(1, max(0.12, log10(w + 1) / 3.4))
    }
}

// MARK: Demo house

/// A small two-storey home for people who haven't scanned theirs yet: living room, kitchen, hall
/// and utility downstairs, bedrooms and an office upstairs, with devices whose power use is
/// simulated so the glow and the energy flow have something to show.
enum DemoHouse {
    struct Wall {
        var from: SIMD2<Float>
        var to: SIMD2<Float>
        /// Openings along the wall: centre distance from `from`, and width.
        var doors: [(Float, Float)] = []
    }

    struct Block {
        var center: SIMD3<Float>
        var size: SIMD3<Float>
        var tone: CGFloat = 0.86
    }

    struct Room {
        var name: String
        var center: SIMD2<Float>
    }

    struct Storey {
        var level: Int
        var name: String
        var walls: [Wall]
        var furniture: [Block]
        var rooms: [Room]
    }

    /// 10 m by 7 m.
    static let size = SIMD2<Float>(10, 7)
    static let wallHeight: Float = 2.5
    /// Floor to floor.
    static let storeyHeight: Float = 2.9
    /// Where power climbs between floors: a riser in the corner of the utility room.
    static let riser = SIMD2<Float>(9.75, 4.25)

    /// Both floors share the outline and the structural walls, as a real house does.
    private static func shell(frontDoor: Bool) -> [Wall] {
        [
            Wall(from: [0, 0], to: [10, 0], doors: frontDoor ? [(2.8, 1.0)] : []),
            Wall(from: [10, 0], to: [10, 7]),
            Wall(from: [10, 7], to: [0, 7]),
            Wall(from: [0, 7], to: [0, 0]),
            Wall(from: [6, 0], to: [6, 4], doors: [(2.0, frontDoor ? 1.6 : 0.9)]),
            Wall(from: [0, 4], to: [10, 4], doors: [(2.6, 0.9), (7.6, 0.9)]),
            Wall(from: [5, 4], to: [5, 7], doors: [(1.5, 0.9)]),
        ]
    }

    /// Twelve steps climbing along the hall's back wall.
    private static var stairs: [Block] {
        (0..<12).map { i in
            let rise = Float(i + 1) * storeyHeight / 12
            return Block(center: [0.9 + Float(i) * 0.28, rise / 2, 6.45], size: [0.28, rise, 0.9], tone: 0.8)
        }
    }

    static let floors: [Storey] = [
        Storey(level: 0, name: "Ground", walls: shell(frontDoor: true), furniture: [
            // Living room: sofa, coffee table, TV stand, rug.
            Block(center: [2.6, 0.22, 3.2], size: [2.4, 0.44, 0.9], tone: 0.78),
            Block(center: [2.6, 0.2, 2.0], size: [1.1, 0.4, 0.6], tone: 0.7),
            Block(center: [2.6, 0.25, 0.35], size: [1.8, 0.5, 0.4], tone: 0.62),
            Block(center: [2.6, 0.005, 2.2], size: [3.4, 0.01, 2.4], tone: 0.4),
            // Kitchen: counters and an island.
            Block(center: [8.0, 0.45, 0.35], size: [3.6, 0.9, 0.6], tone: 0.9),
            Block(center: [9.65, 0.45, 2.0], size: [0.6, 0.9, 2.6], tone: 0.9),
            Block(center: [7.9, 0.45, 2.2], size: [1.6, 0.9, 0.9], tone: 0.82),
            // Hall: a console table by the stairs.
            Block(center: [3.9, 0.4, 4.35], size: [1.2, 0.8, 0.4], tone: 0.72),
            // Utility: a rack for the inverter and batteries.
            Block(center: [9.6, 0.6, 5.6], size: [0.6, 1.2, 1.6], tone: 0.58),
        ] + stairs, rooms: [
            Room(name: "Living room", center: [3.0, 2.0]),
            Room(name: "Kitchen", center: [8.0, 2.0]),
            Room(name: "Hall", center: [2.5, 5.2]),
            Room(name: "Utility", center: [7.5, 5.5]),
        ]),
        Storey(level: 1, name: "First", walls: shell(frontDoor: false), furniture: [
            // Main bedroom: bed and bedside tables.
            Block(center: [3.0, 0.25, 1.4], size: [1.8, 0.5, 2.1], tone: 0.86),
            Block(center: [1.75, 0.25, 0.45], size: [0.45, 0.5, 0.4], tone: 0.68),
            Block(center: [4.25, 0.25, 0.45], size: [0.45, 0.5, 0.4], tone: 0.68),
            // Second bedroom: a single bed and a wardrobe.
            Block(center: [8.4, 0.25, 1.2], size: [1.0, 0.5, 2.0], tone: 0.86),
            Block(center: [6.5, 1.0, 3.6], size: [0.6, 2.0, 1.2], tone: 0.7),
            // Office: desk, chair, shelf.
            Block(center: [2.0, 0.37, 6.55], size: [2.2, 0.74, 0.7], tone: 0.76),
            Block(center: [2.0, 0.25, 5.8], size: [0.55, 0.5, 0.55], tone: 0.5),
            Block(center: [0.3, 0.9, 5.3], size: [0.4, 1.8, 1.2], tone: 0.7),
            // Landing: a bench.
            Block(center: [7.5, 0.22, 6.6], size: [1.4, 0.44, 0.45], tone: 0.74),
        ], rooms: [
            Room(name: "Bedroom", center: [3.0, 2.6]),
            Room(name: "Guest room", center: [8.0, 2.6]),
            Room(name: "Office", center: [2.5, 5.5]),
            Room(name: "Landing", center: [7.5, 5.3]),
        ]),
    ]

    private static func up(_ level: Int) -> Float { Float(level) * storeyHeight }

    static let pins: [MapPin] = [
        MapPin(id: "demo:inverter", name: "Inverter", kind: DeviceKind.inverter.rawValue, x: 9.85, y: 1.5, z: 6.2, floor: 0),
        MapPin(id: "demo:battery", name: "Battery", kind: DeviceKind.battery.rawValue, x: 9.6, y: 1.25, z: 5.2, floor: 0),
        MapPin(id: "demo:ac", name: "Air conditioner", kind: DeviceKind.airConditioner.rawValue, x: 0.1, y: 2.1, z: 2.0, floor: 0),
        MapPin(id: "demo:tv", name: "TV", kind: DeviceKind.tv.rawValue, x: 2.6, y: 1.0, z: 0.25, floor: 0),
        MapPin(id: "demo:fridge", name: "Fridge", kind: DeviceKind.fridge.rawValue, x: 9.6, y: 1.0, z: 3.6, floor: 0),
        MapPin(id: "demo:router", name: "Router", kind: DeviceKind.router.rawValue, x: 3.9, y: 1.05, z: 4.35, floor: 0),
        MapPin(id: "demo:speaker", name: "Speaker", kind: DeviceKind.smartSpeaker.rawValue, x: 7.9, y: 0.95, z: 2.2, floor: 0),
        MapPin(id: "demo:bedroom-ac", name: "Bedroom AC", kind: DeviceKind.airConditioner.rawValue, x: 0.1, y: up(1) + 2.1, z: 1.6, floor: 1),
        MapPin(id: "demo:computer", name: "Mac mini", kind: DeviceKind.computer.rawValue, x: 2.4, y: up(1) + 0.8, z: 6.55, floor: 1),
        MapPin(id: "demo:lamp", name: "Bedside speaker", kind: DeviceKind.smartSpeaker.rawValue, x: 4.25, y: up(1) + 0.6, z: 0.45, floor: 1),
    ]

    /// Believable power for each demo device, moving slowly so the map feels alive.
    static func watts(_ pin: MapPin, now: Date) -> Double? {
        let t = now.timeIntervalSince1970
        let wobble = { (period: Double, amount: Double) in 1 + amount * sin(t / period * 2 * .pi) }
        switch pin.id {
        case "demo:inverter": return nil
        case "demo:battery": return nil
        case "demo:ac": return 860 * wobble(40, 0.18)
        case "demo:bedroom-ac": return 540 * wobble(55, 0.2)
        case "demo:tv": return 95 * wobble(13, 0.08)
        // A fridge's compressor runs, then rests.
        case "demo:fridge": return sin(t / 90 * 2 * .pi) > -0.2 ? 140 * wobble(7, 0.05) : 6
        case "demo:computer": return 32 * wobble(9, 0.3)
        case "demo:router": return 11
        case "demo:speaker": return 4 * wobble(5, 0.4)
        case "demo:lamp": return 3 * wobble(6, 0.3)
        default: return nil
        }
    }
}
