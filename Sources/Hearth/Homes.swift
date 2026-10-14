import Foundation
import SwiftUI

// MARK: Homes

/// A place with its own devices: the house, a holiday flat, the office. Devices from Home
/// Assistant and gadgets or vehicles added by hand each belong to one home. The main home
/// holds everything not linked anywhere else, so someone with one home never sets anything up.
struct Home: Codable, Identifiable, Equatable {
    enum Style: String, Codable, CaseIterable, Identifiable {
        case house, apartment, office
        var id: String { rawValue }
        var title: String {
            switch self {
            case .house: "House"
            case .apartment: "Apartment"
            case .office: "Office"
            }
        }
        var symbol: String {
            switch self {
            case .house: "house"
            case .apartment: "building.2"
            case .office: "building.columns"
            }
        }
    }

    var id = UUID()
    var name: String
    var style: Style = .house
    /// Home Assistant device ids and hand-added gadget ids (UUID strings). Empty for the main home,
    /// which holds whatever isn't linked to another home.
    var devices: [String] = []
    var isMain = false
    /// False until someone names the main home, so it can follow Home Assistant's own location name.
    var named = false
}

/// The homes, kept in Application Support.
@MainActor
final class HomeList: ObservableObject {
    static let shared = HomeList()

    @Published private(set) var homes: [Home] = []
    private let file: URL

    /// An explicit file keeps previews and regression fixtures separate from personal homes.
    /// Omitting it retains the app's normal Application Support/CLI-selected location.
    init(file explicitFile: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hearth", isDirectory: true)
        // Development: `-homesFile <path>` uses another list, so tests never touch yours.
        file = explicitFile ?? UserDefaults.standard.string(forKey: "homesFile").map { URL(fileURLWithPath: $0) }
            ?? base.appendingPathComponent("homes.json")
        if let data = try? Data(contentsOf: file), let list = try? JSONDecoder().decode([Home].self, from: data) {
            homes = list
        }
        if !homes.contains(where: \.isMain) {
            homes.insert(Home(name: "Home", isMain: true), at: 0)
        }
    }

    var main: Home { homes.first(where: \.isMain)! }
    var others: [Home] { homes.filter { !$0.isMain } }

    /// The home a device or gadget belongs to.
    func home(of key: String) -> Home {
        others.first { $0.devices.contains(key) } ?? main
    }

    /// Follows Home Assistant's location name until the main home is named by hand.
    func adoptLocationName(_ name: String) {
        guard let i = homes.firstIndex(where: \.isMain), !homes[i].named,
              !name.isEmpty, homes[i].name != name else { return }
        homes[i].name = name
        write()
    }

    @discardableResult
    func add(name: String, style: Home.Style) -> Home {
        let home = Home(name: name, style: style)
        homes.append(home)
        write()
        return home
    }

    func update(_ home: Home) {
        guard let i = homes.firstIndex(where: { $0.id == home.id }) else { return }
        var h = home
        // Editing a home's name or devices must never promote/demote its identity.
        h.isMain = homes[i].isMain
        if h.isMain { h.named = true; h.devices = [] }
        homes[i] = h
        write()
    }

    /// Removes a home; its devices go back to the main home.
    func remove(_ id: UUID) {
        homes.removeAll { $0.id == id && !$0.isMain }
        write()
    }

    /// Puts a device in a home, taking it out of any other. Linking to the main home just unlinks it.
    func link(_ key: String, to homeID: UUID) {
        for i in homes.indices { homes[i].devices.removeAll { $0 == key } }
        if let i = homes.firstIndex(where: { $0.id == homeID }), !homes[i].isMain {
            homes[i].devices.append(key)
        }
        write()
    }

    private func write() {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(homes) { try? data.write(to: file, options: .atomic) }
    }
}

// MARK: What a home is using

/// What a home draws right now and has used today, worked out from whatever its devices report.
/// The main home prefers the whole-house figure from the Energy dashboard's sensors, and
/// separately adds up the devices that report their own power.
@MainActor
struct HomeEnergy {
    struct User: Identifiable {
        let device: HomeDevice
        let watts: Double
        var id: String { device.id }
    }

    let home: Home
    /// Home Assistant devices in this home, by name.
    var devices: [HomeDevice] = []
    /// Hand-added gadgets and vehicles in this home.
    var gadgets: [Gadget] = []
    /// Devices drawing power right now, biggest first.
    var users: [User] = []
    /// The house's own total, from the inverter or the grid meter (main home only).
    var houseWatts: Double?
    /// Today's energy for each device that reports it, in kWh.
    var deviceToday: [String: Double] = [:]

    /// The devices that report their power, added up.
    var devicesWatts: Double? { users.isEmpty ? nil : users.reduce(0) { $0 + $1.watts } }
    /// The best figure for right now.
    var nowWatts: Double? { houseWatts ?? devicesWatts }
    var hasReadings: Bool { nowWatts != nil || !deviceToday.isEmpty }

    /// Kinds whose power sensors measure supply, not use.
    static let suppliers: Set<DeviceKind> = [.inverter, .battery, .solarPanel]

    init(home: Home, store: HomeStore, list: HomeList, gadgets manual: [Gadget], everything: Bool = false) {
        self.home = home
        let all = store.devices.values.filter { !$0.isService }.compactMap { store.homeDevice($0.id) }
            .filter { !$0.entities.isEmpty }
        devices = all.filter { everything || list.home(of: $0.id).id == home.id }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        gadgets = everything ? manual : manual.filter { list.home(of: $0.id.uuidString).id == home.id }

        for d in devices where !Self.suppliers.contains(d.kind) {
            if let w = Self.watts(of: d), w >= 0.5 { users.append(User(device: d, watts: w)) }
            if let kwh = Self.today(of: d) { deviceToday[d.id] = kwh }
        }
        users.sort { $0.watts > $1.watts }

        if home.isMain || everything {
            let sys = EnergySystem.read(store, prefs: nil)
            if sys.load != nil || sys.hasGrid { houseWatts = sys.loadWatts }
        }
    }

    /// A device's own power reading: its power sensor, the largest if it has several.
    static func watts(of device: HomeDevice) -> Double? {
        device.entities
            .filter { $0.domain == "sensor" && !$0.isUnavailable }
            .filter { $0.str("device_class") == "power" || ["W", "kW", "MW"].contains($0.str("unit_of_measurement") ?? "") }
            .compactMap(EnergyUnits.watts)
            .max()
    }

    /// Today's energy from a sensor that resets daily ("energy today", "daily energy"), in its own unit.
    static func today(of device: HomeDevice) -> Double? {
        device.entities
            .filter { $0.domain == "sensor" && !$0.isUnavailable }
            .filter { $0.str("device_class") == "energy" || ["Wh", "kWh", "MWh"].contains($0.str("unit_of_measurement") ?? "") }
            .filter { e in
                let id = e.id.lowercased()
                return (id.contains("today") || id.contains("daily")) && !id.contains("yesterday")
            }
            .compactMap(EnergyUnits.kilowattHours)
            .max()
    }

    /// Energy sensors that keep counting up (a smart plug's total), whose change today Home
    /// Assistant's statistics can tell us.
    static func countingSensors(of device: HomeDevice) -> [Entity] {
        device.entities.filter { e in
            let id = e.id.lowercased()
            let cls = e.str("state_class") ?? ""
            return e.domain == "sensor" && !e.isUnavailable
                && (e.str("device_class") == "energy" || ["Wh", "kWh", "MWh"].contains(e.str("unit_of_measurement") ?? ""))
                && cls.hasPrefix("total")
                && !["today", "daily", "yesterday", "week", "month", "year", "last"].contains { id.contains($0) }
        }
    }
}

// MARK: Today's totals

/// The numbers that come from Home Assistant's statistics rather than live states: the house's
/// energy today from the Energy dashboard's setup, and today's change on counting sensors.
/// Fetched while a homes screen is visible, every five minutes.
@MainActor
final class HomesFeed: ObservableObject {
    /// The house's use today, from the Energy dashboard, in kWh.
    @Published private(set) var houseToday: Double?
    /// Today's change on counting energy sensors, by device id, in kWh.
    @Published private(set) var countedToday: [String: Double] = [:]
    @Published private(set) var prefs: EnergyPrefs?
    private var lastRefresh = Date.distantPast

    /// Today's energy for a home: the house total for the main home when known, otherwise its devices added up.
    func today(_ energy: HomeEnergy) -> Double? {
        if energy.home.isMain, let houseToday { return houseToday }
        var total = energy.deviceToday
        for (id, kwh) in countedToday where total[id] == nil && energy.devices.contains(where: { $0.id == id }) {
            total[id] = kwh
        }
        return total.isEmpty ? nil : total.values.reduce(0, +)
    }

    func deviceToday(_ energy: HomeEnergy, _ id: String) -> Double? {
        energy.deviceToday[id] ?? countedToday[id]
    }

    /// Loads today's figures, at most every five minutes unless forced.
    func refresh(_ store: HomeStore, list: HomeList, force: Bool = false) async {
        guard store.status == .connected, force || Date().timeIntervalSince(lastRefresh) > 280 else { return }
        lastRefresh = Date()

        if let config = try? await store.command(["type": "get_config"]) as? JSON,
           let name = config["location_name"] as? String, !store.isDemo {
            list.adoptLocationName(name)
        }

        let json = try? await store.command(["type": "energy/get_prefs"]) as? JSON
        let prefs = json.map(EnergyPrefs.init) ?? EnergyPrefs()
        self.prefs = prefs
        if prefs.isSet {
            func change(_ id: String) async -> Double {
                let result = try? await store.command([
                    "type": "recorder/statistic_during_period",
                    "statistic_id": id,
                    "calendar": ["period": "day"],
                    "types": ["change"],
                    "units": ["energy": "kWh"],
                ]) as? JSON
                return (result?["change"] as? NSNumber)?.doubleValue ?? 0
            }
            var used = 0.0
            for id in prefs.gridIn { used += await change(id) }
            for id in prefs.solar { used += await change(id) }
            for id in prefs.batteryOut { used += await change(id) }
            for id in prefs.gridOut { used -= await change(id) }
            for id in prefs.batteryIn { used -= await change(id) }
            houseToday = max(used, 0)
        } else {
            houseToday = nil
        }

        var counted: [String: Double] = [:]
        let devices = store.devices.values.filter { !$0.isService }.compactMap { store.homeDevice($0.id) }
        for d in devices where !HomeEnergy.suppliers.contains(d.kind) && HomeEnergy.today(of: d) == nil {
            for e in HomeEnergy.countingSensors(of: d) {
                let result = try? await store.command([
                    "type": "recorder/statistic_during_period",
                    "statistic_id": e.id,
                    "calendar": ["period": "day"],
                    "types": ["change"],
                    "units": ["energy": "kWh"],
                ]) as? JSON
                if let v = (result?["change"] as? NSNumber)?.doubleValue { counted[d.id, default: 0] += v }
            }
        }
        countedToday = counted
    }
}
