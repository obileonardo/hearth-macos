import SwiftUI

// MARK: Recognising energy hardware

extension DeviceKind {
    /// Inverters, batteries and solar panels, from the maker or what the device calls itself.
    /// `text` is the model and name, lowercased.
    static func energyKind(maker: String, text: String) -> DeviceKind? {
        func says(_ words: String...) -> Bool { words.contains { text.contains($0) } }
        func made(_ words: String...) -> Bool { words.contains { maker.contains($0) } }
        // Appliances with an "inverter" compressor are not solar inverters.
        if says("air conditioner", "aircon", "fridge", "refrigerator", "freezer", "washer", "dryer", "microwave", "heat pump") { return nil }

        if made("huawei"), says("luna") { return .battery }
        if made("huawei"), says("sun2000", "inverter") { return .inverter }
        // A battery or its BMS is never the inverter, so it goes first.
        if made("pylontech", "jikong", "jk bms", "jkbms", "daly", "seplos", "dyness", "ecoflow", "bluetti", "jackery")
            || (made("anker") && says("solix")) || (made("tesla") && says("powerwall"))
            || says("powerwall", "lifepo4", "lithium", "battery pack", "battery bank", "smartshunt", "battery monitor", "bms") {
            return .battery
        }
        if says("solar panel", "pv array", "pv string", "photovoltaic") { return .solarPanel }
        if made("deye", "sunsynk", "growatt", "goodwe", "solax", "fronius", "victron", "enphase", "solaredge", "voltronic",
                "cworth", "solarman", "sofar", "srne", "easun", "mpp solar", "luxpower", "apsystems", "sungrow", "hoymiles",
                "solis", "ginlong", "felicity", "powmr", "sma solar")
            || maker == "sma" || maker.hasPrefix("sma ") || maker == "must" || maker.hasPrefix("must ")
            || says("inverter", "multiplus", "quattro", "mppt", "solar charger") {
            return .inverter
        }
        return nil
    }
}

/// The colours of the energy page: warm sun, green charge, cool grid, the room's own sand.
enum EnergyPalette {
    static let solar = Color.accent(1.0, 0.78, 0.38)
    static let battery = Color.accent(0.5, 0.92, 0.64)
    static let grid = Color.accent(0.7, 0.72, 1.0)
    static let home = Theme.sand

    static func accent(_ kind: DeviceKind) -> Color {
        switch kind {
        case .solarPanel: solar
        case .battery: battery
        default: Color.accent(0.62, 0.9, 0.86)
        }
    }
}

// MARK: Reading the numbers

/// Which sensors Home Assistant's Energy dashboard uses, from `energy/get_prefs`.
struct EnergyPrefs {
    var solar: [String] = []
    var gridIn: [String] = []
    var gridOut: [String] = []
    var batteryIn: [String] = []
    var batteryOut: [String] = []
    /// Live power sensors, where the dashboard names them.
    var solarRate: [String] = []
    var gridRate: [String] = []
    var batteryRate: [String] = []

    var isSet: Bool { !(solar.isEmpty && gridIn.isEmpty && batteryIn.isEmpty && batteryOut.isEmpty) }
    var statistics: [String] { solar + gridIn + gridOut + batteryIn + batteryOut }

    init() {}

    init(_ json: JSON) {
        for source in json["energy_sources"] as? [JSON] ?? [] {
            switch source["type"] as? String {
            case "solar":
                solar += Self.ids(source, "stat_energy_from")
                solarRate += Self.rates(source)
            case "battery":
                batteryOut += Self.ids(source, "stat_energy_from")
                batteryIn += Self.ids(source, "stat_energy_to")
                batteryRate += Self.rates(source)
            case "grid":
                for flow in source["flow_from"] as? [JSON] ?? [] { gridIn += Self.ids(flow, "stat_energy_from") }
                for flow in source["flow_to"] as? [JSON] ?? [] { gridOut += Self.ids(flow, "stat_energy_to") }
                gridIn += Self.ids(source, "stat_energy_from")
                gridOut += Self.ids(source, "stat_energy_to")
                gridRate += Self.rates(source)
            default:
                break
            }
        }
    }

    private static func ids(_ json: JSON, _ key: String) -> [String] {
        (json[key] as? String).map { [$0] } ?? []
    }

    /// Any power sensor named anywhere in a source, whatever this Home Assistant version calls the key.
    private static func rates(_ value: Any) -> [String] {
        if let json = value as? JSON {
            return json.flatMap { key, v -> [String] in
                if key.contains("rate"), let id = v as? String { return [id] }
                return rates(v)
            }
        }
        if let list = value as? [Any] { return list.flatMap(rates) }
        return []
    }
}

/// Power in watts and energy in kilowatt hours, from a sensor's state and its own unit.
enum EnergyUnits {
    static func watts(_ e: Entity?) -> Double? {
        guard let e, let v = Double(e.state) else { return nil }
        switch e.str("unit_of_measurement") ?? "W" {
        case "kW": return v * 1000
        case "MW": return v * 1_000_000
        case "mW": return v / 1000
        default: return v
        }
    }

    static func kilowattHours(_ e: Entity?) -> Double? {
        guard let e, let v = Double(e.state) else { return nil }
        switch e.str("unit_of_measurement") ?? "kWh" {
        case "Wh": return v / 1000
        case "MWh": return v * 1000
        default: return v
        }
    }

    static func power(_ watts: Double) -> String {
        let w = abs(watts)
        if w < 1000 { return "\(Int(w.rounded())) W" }
        if w < 100_000 { return String(format: "%.1f kW", w / 1000) }
        return String(format: "%.0f kW", w / 1000)
    }

    static func energy(_ kwh: Double) -> String {
        if kwh < 1 { return "\(Int((kwh * 1000).rounded())) Wh" }
        if kwh < 100 { return String(format: "%.1f kWh", kwh) }
        return String(format: "%.0f kWh", kwh)
    }

    static func duration(hours: Double) -> String {
        let minutes = Int((hours * 60).rounded())
        if minutes < 60 { return "\(max(minutes, 1)) min" }
        if minutes < 48 * 60 { return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min" }
        return "\(minutes / (24 * 60)) days"
    }
}

/// Everything the page knows about the system: the Energy dashboard's sensors first, then
/// sensors recognised by what they measure and what they're called.
struct EnergySystem {
    var solar: [Entity] = []
    /// Battery power, positive while discharging (Home Assistant's convention).
    var battery: Entity?
    var batteryCharging: Entity?
    var batteryDischarging: Entity?
    /// Grid power, positive while importing.
    var grid: Entity?
    var gridImport: Entity?
    var gridExport: Entity?
    var load: Entity?
    var charge: Entity?
    var batteryVoltage: Entity?
    var batteryCurrent: Entity?
    var batteryTemperature: Entity?
    var batteryCapacity: Entity?
    var batteryStatus: Entity?
    var inverterMode: Entity?
    var inverterTemperature: Entity?
    var outputLoad: Entity?
    var faults: [Entity] = []
    var cells: [Entity] = []
    var cellTemperatures: [Entity] = []
    var solarToday: Entity?
    var devices: [HomeDevice] = []

    // MARK: Numbers

    var solarWatts: Double? {
        let values = solar.compactMap(EnergyUnits.watts)
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    var batteryWatts: Double? {
        var value: Double?
        if let w = EnergyUnits.watts(battery) {
            value = w
        } else if batteryCharging != nil || batteryDischarging != nil {
            value = (EnergyUnits.watts(batteryDischarging) ?? 0) - (EnergyUnits.watts(batteryCharging) ?? 0)
        }
        // Not every inverter follows Home Assistant's sign; trust its own words when it has them.
        if var v = value, let status = batteryStatus?.state.lowercased() {
            if status.contains("discharg") { v = abs(v) } else if status.contains("charg") { v = -abs(v) }
            value = v
        }
        return value
    }

    var gridWatts: Double? {
        if let w = EnergyUnits.watts(grid) { return w }
        if gridImport != nil || gridExport != nil {
            return (EnergyUnits.watts(gridImport) ?? 0) - (EnergyUnits.watts(gridExport) ?? 0)
        }
        return nil
    }

    var loadWatts: Double? {
        if let w = EnergyUnits.watts(load) { return max(w, 0) }
        guard solarWatts != nil || batteryWatts != nil || gridWatts != nil else { return nil }
        return max((solarWatts ?? 0) + (batteryWatts ?? 0) + (gridWatts ?? 0), 0)
    }

    var chargePercent: Double? { charge.flatMap { Double($0.state) } }

    /// The battery's full size in watt hours, from a capacity sensor in Wh, kWh or Ah.
    var capacityWattHours: Double? {
        guard let e = batteryCapacity, let v = Double(e.state), v > 0 else { return nil }
        switch e.str("unit_of_measurement") ?? "" {
        case "Wh": return v
        case "kWh": return v * 1000
        case "MWh": return v * 1_000_000
        case "Ah":
            guard let volts = batteryVoltage.flatMap({ Double($0.state) }), volts > 0 else { return nil }
            return v * volts
        default: return nil
        }
    }

    var hasSolar: Bool { !solar.isEmpty || solarToday != nil }
    var hasBattery: Bool { battery != nil || batteryCharging != nil || batteryDischarging != nil || charge != nil }
    var hasGrid: Bool { grid != nil || gridImport != nil || gridExport != nil }
    var hasInverter: Bool { inverterMode != nil || inverterTemperature != nil || outputLoad != nil || devices.contains { $0.kind == .inverter } }
    var isEmpty: Bool { !hasSolar && !hasBattery && !hasGrid && load == nil && devices.isEmpty && cells.isEmpty }

    // MARK: Finding the sensors

    @MainActor
    static func read(_ store: HomeStore, prefs: EnergyPrefs?) -> EnergySystem {
        var sys = EnergySystem()
        let order: [DeviceKind] = [.inverter, .battery, .solarPanel]
        sys.devices = store.devices.values
            .filter { !$0.isService }
            .compactMap { store.homeDevice($0.id) }
            .filter { order.contains($0.kind) }
            .sorted {
                let a = order.firstIndex(of: $0.kind) ?? 0, b = order.firstIndex(of: $1.kind) ?? 0
                return a != b ? a < b : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        let energyDevice = Dictionary(uniqueKeysWithValues: sys.devices.map { ($0.id, $0.kind) })
        func kindOf(_ e: Entity) -> DeviceKind? { store.registry[e.id]?.deviceID.flatMap { energyDevice[$0] } }

        let sensors = store.entities.values.filter { $0.domain == "sensor" && store.registry[$0.id]?.hidden != true }
        let words = Dictionary(uniqueKeysWithValues: sensors.map { ($0.id, Self.words($0)) })
        func w(_ e: Entity) -> Set<String> { words[e.id] ?? [] }
        func unit(_ e: Entity) -> String { e.str("unit_of_measurement") ?? "" }
        func numeric(_ e: Entity) -> Bool { Double(e.state) != nil }
        let power = sensors.filter { $0.str("device_class") == "power" || ["W", "kW", "MW"].contains(unit($0)) }

        func best(_ pool: [Entity], _ score: (Entity) -> Int) -> Entity? {
            pool.map { ($0, score($0)) }.filter { $0.1 > 0 }
                .max { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.id > $1.0.id }?.0
        }
        func has(_ e: Entity, _ any: String...) -> Bool { !w(e).isDisjoint(with: any) }

        // The Energy dashboard's own power sensors, when it names them.
        if let prefs {
            sys.solar = prefs.solarRate.compactMap { store.entities[$0] }
            sys.battery = prefs.batteryRate.first.flatMap { store.entities[$0] }
            sys.grid = prefs.gridRate.first.flatMap { store.entities[$0] }
        }

        // Solar: one total if there is one, otherwise every string added up.
        if sys.solar.isEmpty {
            let pv = power.filter { has($0, "pv", "solar", "photovoltaic") || w($0).contains { $0.hasPrefix("pv") && $0.dropFirst(2).allSatisfy(\.isNumber) } }
                .filter { !has($0, "battery", "grid", "load", "export", "import") }
            let strings = pv.filter { w($0).contains { ($0.hasPrefix("pv") || $0.hasPrefix("mppt")) && $0.count > 2 && $0.last!.isNumber } }
            let totals = pv.filter { e in !strings.contains { $0.id == e.id } }
            if let total = best(totals, { has($0, "power", "total", "input") ? 3 : 1 }) {
                sys.solar = [total]
            } else {
                sys.solar = strings.sorted { $0.id < $1.id }
            }
        }

        let batteryish = power.filter { has($0, "battery", "bat", "batt") || kindOf($0) == .battery }
            .filter { !has($0, "pv", "solar", "grid", "load") }
        if sys.battery == nil {
            sys.battery = best(batteryish) { has($0, "charge", "charging", "discharge", "discharging") ? 0 : 3 }
            if sys.battery == nil {
                sys.batteryDischarging = best(batteryish) { has($0, "discharge", "discharging") ? 3 : 0 }
                sys.batteryCharging = best(batteryish) { has($0, "charge", "charging") && !has($0, "discharge", "discharging") ? 3 : 0 }
            }
        }

        let gridish = power.filter { has($0, "grid", "meter", "utility", "mains") || (kindOf($0) != nil && has($0, "import", "export")) }
            .filter { !has($0, "pv", "solar", "battery", "load") }
        if sys.grid == nil {
            sys.grid = best(gridish) { has($0, "import", "export", "consumption", "feed") ? 0 : 3 }
            if sys.grid == nil {
                sys.gridImport = best(gridish) { has($0, "import", "consumption") ? 3 : 0 }
                sys.gridExport = best(gridish) { has($0, "export", "feed") ? 3 : 0 }
            }
        }

        sys.load = best(power.filter { !has($0, "pv", "solar", "battery", "grid") }) { e in
            if has(e, "load", "consumption", "essential") { return has(e, "power") ? 5 : 4 }
            if kindOf(e) == .inverter, has(e, "output", "ac") { return 2 }
            return 0
        }

        // Battery details.
        sys.charge = best(sensors.filter { unit($0) == "%" && numeric($0) }) { e in
            // A car's or a charger's state of charge is not the house battery's.
            if kindOf(e) == nil, has(e, "wallbox", "car", "vehicle", "ev", "charger", "phone", "tablet", "watch") { return 0 }
            if has(e, "soc") || (has(e, "state") && has(e, "charge")) {
                return kindOf(e) != nil || has(e, "battery", "bat", "bms", "pack", "inverter") ? 5 : 0
            }
            if kindOf(e) == .battery || kindOf(e) == .inverter, e.str("device_class") == "battery" { return 3 }
            if has(e, "battery") && kindOf(e) != nil { return 2 }
            return 0
        }
        let notCell: (Entity) -> Bool = { e in !Self.isNumbered(e, prefixes: ["cell"]) }
        sys.batteryVoltage = best(sensors.filter { unit($0) == "V" && notCell($0) }) { e in
            if has(e, "pv", "grid", "ac", "output", "bus") { return 0 }
            return has(e, "battery", "bat", "bms", "pack") ? 3 : (kindOf(e) == .battery ? 2 : 0)
        }
        sys.batteryCurrent = best(sensors.filter { unit($0) == "A" && notCell($0) }) { e in
            if has(e, "pv", "grid", "ac", "output") { return 0 }
            return has(e, "battery", "bat", "bms", "pack") ? 3 : (kindOf(e) == .battery ? 2 : 0)
        }
        let temperatures = sensors.filter { $0.str("device_class") == "temperature" || ["°C", "°F"].contains(unit($0)) }
        sys.batteryTemperature = best(temperatures.filter(notCell)) { e in
            if Self.isNumbered(e, prefixes: ["temperature", "temp", "sensor", "probe"]) { return 0 }
            return has(e, "battery", "bat", "bms", "pack") ? 3 : (kindOf(e) == .battery ? 2 : 0)
        }
        sys.batteryCapacity = best(sensors.filter { ["Wh", "kWh", "MWh", "Ah"].contains(unit($0)) && numeric($0) }) { e in
            guard has(e, "capacity", "size", "nominal") else { return 0 }
            if has(e, "remaining", "left", "today", "total") { return 0 }
            return has(e, "battery", "bat", "bms", "pack") || kindOf(e) == .battery ? 3 : 0
        }
        sys.batteryStatus = best(sensors.filter { !numeric($0) && !$0.isUnavailable }) { e in
            has(e, "battery", "bat", "bms") && has(e, "status", "state", "mode") ? 3 : 0
        }

        // The inverter.
        sys.inverterMode = best(sensors.filter { !numeric($0) && !$0.isUnavailable }) { e in
            if has(e, "battery", "bat", "bms", "fault", "warning", "alarm", "error") { return 0 }
            guard has(e, "mode", "status", "running", "work", "source", "priority") else { return 0 }
            if has(e, "inverter") { return 4 }
            return kindOf(e) == .inverter ? (has(e, "mode", "work") ? 3 : 2) : 0
        }
        sys.inverterTemperature = best(temperatures) { e in
            if has(e, "battery", "bat", "bms", "cell") { return 0 }
            if has(e, "inverter", "radiator", "heatsink", "igbt", "dc", "ac") { return kindOf(e) == .inverter || has(e, "inverter") ? 3 : 1 }
            return kindOf(e) == .inverter ? 2 : 0
        }
        sys.outputLoad = best(sensors.filter { unit($0) == "%" && numeric($0) }) { e in
            has(e, "load") && (kindOf(e) == .inverter || has(e, "inverter", "output")) ? 3 : 0
        }

        // Faults and warnings that are actually raised.
        let calm: Set<String> = ["", "0", "none", "no fault", "no faults", "normal", "ok", "no", "off", "false", "no warning",
                                 "no warnings", "no alarm", "no error", "unknown", "unavailable"]
        sys.faults = store.entities.values.filter { e in
            guard kindOf(e) != nil || has(e, "inverter", "bms") else { return false }
            if e.domain == "binary_sensor", e.str("device_class") == "problem" { return e.state == "on" }
            if e.domain == "sensor", Self.words(e).isDisjoint(with: ["fault", "faults", "warning", "warnings", "alarm", "alarms", "error"]) == false {
                return !calm.contains(e.state.lowercased())
            }
            return false
        }
        .sorted { $0.id < $1.id }

        // Battery cells, numbered: cell 1 voltage, cell_voltage_01 and so on.
        sys.cells = sensors.filter { ["V", "mV"].contains(unit($0)) && numeric($0) && Self.isNumbered($0, prefixes: ["cell"]) }
            .sorted { (Self.number($0) ?? 0) < (Self.number($1) ?? 0) }
        sys.cellTemperatures = temperatures.filter { e in
            numeric(e) && (has(e, "bms", "battery", "cell", "pack") || kindOf(e) == .battery)
                && Self.isNumbered(e, prefixes: ["cell", "temperature", "temp", "sensor", "probe", "t"])
        }
        .sorted { (Self.number($0) ?? 0) < (Self.number($1) ?? 0) }

        sys.solarToday = best(sensors.filter { ["Wh", "kWh", "MWh"].contains(unit($0)) }) { e in
            has(e, "pv", "solar") && has(e, "today", "daily", "day") ? 3 : 0
        }
        return sys
    }

    /// The words in an entity's id and name: "sensor.deye_pv1_power" gives deye, pv1, power.
    static func words(_ e: Entity) -> Set<String> {
        let text = (String(e.id.drop { $0 != "." }.dropFirst()) + " " + e.name).lowercased()
        return Set(text.split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }

    /// Whether the name carries a number after one of the words: "cell 3", "cell_03_voltage", "cell3".
    static func isNumbered(_ e: Entity, prefixes: [String]) -> Bool {
        let text = (String(e.id.drop { $0 != "." }.dropFirst()) + " " + e.name).lowercased()
        return prefixes.contains { p in
            text.range(of: "(^|[^a-z])\(p)[ _]?[0-9]{1,3}([^0-9]|$)", options: .regularExpression) != nil
        }
    }

    static func number(_ e: Entity) -> Int? {
        let text = String(e.id.drop { $0 != "." }.dropFirst())
        guard let r = text.range(of: "[0-9]{1,3}", options: .regularExpression) else { return nil }
        return Int(text[r])
    }
}

// MARK: Where the power goes

/// The flows between the four ends, in watts, worked out the way Home Assistant's own
/// energy cards do: the sun serves the battery and grid export first that the readings
/// show, and the house takes what's left.
struct PowerFlows {
    var solarToHome = 0.0, solarToBattery = 0.0, solarToGrid = 0.0
    var gridToHome = 0.0, gridToBattery = 0.0
    var batteryToHome = 0.0, batteryToGrid = 0.0

    init(solar: Double, battery: Double, grid: Double) {
        var sun = max(solar, 0)
        let charge = max(-battery, 0), discharge = max(battery, 0)
        let imported = max(grid, 0), exported = max(-grid, 0)
        solarToBattery = min(sun, charge)
        sun -= solarToBattery
        gridToBattery = min(max(charge - solarToBattery, 0), imported)
        solarToGrid = min(sun, exported)
        sun -= solarToGrid
        solarToHome = sun
        batteryToGrid = min(max(exported - solarToGrid, 0), discharge)
        batteryToHome = discharge - batteryToGrid
        gridToHome = max(imported - gridToBattery, 0)
    }
}

// MARK: Feed

/// What the page fetches rather than watches: the Energy dashboard setup, today's totals
/// from Home Assistant's statistics, and the last day of solar power.
@MainActor
final class EnergyFeed: ObservableObject {
    @Published var prefs: EnergyPrefs?
    /// Today's change for each statistic, in kWh.
    @Published var today: [String: Double] = [:]
    /// Solar power over the last 24 hours, in watts, one value per half hour.
    @Published var solarDay: [Double] = []
    private var loadedPrefs = false

    func loadPrefs(_ store: HomeStore) async {
        guard !loadedPrefs else { return }
        if let json = try? await store.command(["type": "energy/get_prefs"]) as? JSON {
            prefs = EnergyPrefs(json)
            loadedPrefs = true
        } else {
            prefs = EnergyPrefs()
        }
    }

    func refresh(_ store: HomeStore, solar: [Entity]) async {
        if let prefs {
            var totals: [String: Double] = [:]
            for id in Set(prefs.statistics) {
                let result = try? await store.command([
                    "type": "recorder/statistic_during_period",
                    "statistic_id": id,
                    "calendar": ["period": "day"],
                    "types": ["change"],
                    "units": ["energy": "kWh"],
                ]) as? JSON
                if let change = (result?["change"] as? NSNumber)?.doubleValue { totals[id] = change }
            }
            today = totals
        }
        await loadSolarDay(store, solar: solar)
    }

    private func loadSolarDay(_ store: HomeStore, solar: [Entity]) async {
        guard !solar.isEmpty else { solarDay = []; return }
        let end = Date(), start = end.addingTimeInterval(-24 * 3600)
        let iso = ISO8601DateFormatter()
        guard let result = try? await store.command([
            "type": "history/history_during_period",
            "start_time": iso.string(from: start),
            "end_time": iso.string(from: end),
            "entity_ids": solar.map(\.id),
            "minimal_response": true,
            "no_attributes": true,
            "significant_changes_only": false,
        ]) as? JSON else { return }

        let buckets = 48
        var sums = [Double](repeating: 0, count: buckets)
        var any = false
        for entity in solar {
            let scale = (EnergyUnits.watts(Entity(id: entity.id, state: "1", attributes: entity.attributes)) ?? 1)
            let samples = (result[entity.id] as? [JSON] ?? []).compactMap { row -> (Double, Double)? in
                guard let s = (row["s"] as? String).flatMap(Double.init) else { return nil }
                let t = (row["lu"] as? NSNumber)?.doubleValue ?? (row["lc"] as? NSNumber)?.doubleValue ?? start.timeIntervalSince1970
                return (t, s * scale)
            }
            .sorted { $0.0 < $1.0 }
            guard !samples.isEmpty else { continue }
            any = true
            // Each half hour holds the last reading before its middle.
            var j = 0
            var current = samples[0].1
            for b in 0..<buckets {
                let t = start.timeIntervalSince1970 + (Double(b) + 0.5) * 1800
                while j < samples.count, samples[j].0 <= t { current = samples[j].1; j += 1 }
                sums[b] += max(current, 0)
            }
        }
        solarDay = any ? sums : []
    }
}

// MARK: Page

/// Inverters, batteries and solar: where the power is coming from and going to right now,
/// how full the battery is, what the sun has made today, and the inverter's health.
struct EnergyPage: View {
    @EnvironmentObject var store: HomeStore
    @StateObject private var feed = EnergyFeed()
    let shown: Bool
    /// False while the menu bar panel is closed, so the flow stops animating.
    let visible: Bool
    @State private var openDevice: String?

    var body: some View {
        ScreenFlow(route: openDevice, depth: openDevice == nil ? 0 : 1) { deviceID in
            if let id = deviceID {
                DeviceDetail(deviceID: id) { openDevice = nil }.id(id)
            } else {
                overview
            }
        }
        // Only once signed in: a command sent while the socket is still authenticating is
        // taken by Home Assistant as a malformed sign-in, and the connection is refused.
        .task(id: visible && store.status == .connected) {
            guard visible, store.status == .connected else { return }
            await feed.loadPrefs(store)
            while !Task.isCancelled {
                let sys = EnergySystem.read(store, prefs: feed.prefs)
                await feed.refresh(store, solar: sys.solar)
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    private var overview: some View {
        let sys = EnergySystem.read(store, prefs: feed.prefs)
        return VStack(alignment: .leading, spacing: 14) {
            PageHeader(eyebrow: eyebrow(sys), title: "Energy") { EmptyView() }
                .reveal(shown, 0)

            if sys.isEmpty {
                // A home's own devices can still report their use without any solar or battery.
                HomeUseCard(visible: visible).reveal(shown, 1)
                EnergyHowTo().reveal(shown, 1)
            } else {
                if sys.hasSolar || sys.hasBattery || sys.hasGrid {
                    PowerFlowCard(sys: sys, visible: visible).reveal(shown, 1)
                }
                HomeUseCard(visible: visible).reveal(shown, 2)
                if sys.hasBattery {
                    BatteryCard(sys: sys).reveal(shown, 2)
                }
                if sys.hasSolar {
                    SolarCard(sys: sys, feed: feed).reveal(shown, 3)
                }
                TodayCard(sys: sys, feed: feed).reveal(shown, 4)
                if sys.hasInverter {
                    InverterCard(sys: sys) { id in withAnimation(.glide) { openDevice = id } }.reveal(shown, 5)
                }
                if !sys.cells.isEmpty {
                    CellsCard(cells: sys.cells, temperatures: sys.cellTemperatures).reveal(shown, 6)
                }
                let others = sys.devices.filter { $0.kind != .inverter }
                if !others.isEmpty {
                    Text("DEVICES").eyebrow().padding(.leading, 4).reveal(shown, 7)
                    VStack(spacing: 8) {
                        ForEach(others) { d in
                            DeviceCard(device: d) { withAnimation(.glide) { openDevice = d.id } }
                        }
                    }
                    .reveal(shown, 7)
                }
                if feed.prefs?.isSet == false {
                    DashboardHint().reveal(shown, 8)
                }
            }
        }
    }

    private func eyebrow(_ sys: EnergySystem) -> String {
        var parts: [String] = []
        if let s = sys.solarWatts { parts.append("Solar \(EnergyUnits.power(s))") }
        if let c = sys.chargePercent { parts.append("Battery \(Int(c.rounded()))%") }
        if parts.isEmpty, let l = sys.loadWatts { parts.append("Using \(EnergyUnits.power(l))") }
        return parts.isEmpty ? "Inverters, batteries, solar" : parts.joined(separator: " · ")
    }
}

// MARK: Power flow

/// Solar at the top, the grid and the house to either side, the battery below, and the
/// inverter in the middle where every path meets. Light runs along each path in the
/// direction the power is going, faster and fuller the more there is.
private struct PowerFlowCard: View {
    let sys: EnergySystem
    let visible: Bool
    /// Reduce Motion: the particles drift at a third of the pace.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Node {
        let key: String
        let title: String
        let color: Color
        let present: Bool
        let value: String
        let detail: String?
    }

    var body: some View {
        let solar = sys.solarWatts ?? 0, battery = sys.batteryWatts ?? 0, grid = sys.gridWatts ?? 0
        let flows = PowerFlows(solar: solar, battery: battery, grid: grid)
        Bezel(radius: 26, inset: 4) {
            GeometryReader { g in
                let w = g.size.width
                let at = positions(width: w)
                ZStack {
                    TimelineView(.animation(minimumInterval: 1 / 30, paused: !visible)) { timeline in
                        Canvas { ctx, _ in
                            draw(ctx, flows: flows, at: at, time: timeline.date.timeIntervalSinceReferenceDate * (reduceMotion ? 0.33 : 1))
                        }
                    }
                    hub.position(at["hub"]!)
                    ForEach(nodes(), id: \.key) { n in
                        node(n, at: at[n.key]!)
                    }
                }
            }
            .frame(height: 290)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary(flows))
    }

    private func positions(width w: CGFloat) -> [String: CGPoint] {
        ["solar": CGPoint(x: w / 2, y: 46), "grid": CGPoint(x: 56, y: 140), "home": CGPoint(x: w - 56, y: 140),
         "battery": CGPoint(x: w / 2, y: 238), "hub": CGPoint(x: w / 2, y: 140)]
    }

    private func nodes() -> [Node] {
        let charge = sys.chargePercent.map { "\(Int($0.rounded()))%" }
        let b = sys.batteryWatts ?? 0
        return [
            Node(key: "solar", title: "Solar", color: EnergyPalette.solar, present: sys.hasSolar,
                 value: sys.solarWatts.map(EnergyUnits.power) ?? "No reading", detail: nil),
            Node(key: "grid", title: "Grid", color: EnergyPalette.grid, present: sys.hasGrid,
                 value: sys.gridWatts.map(EnergyUnits.power) ?? "Not connected",
                 detail: sys.gridWatts.map { $0 > 20 ? "Buying" : $0 < -20 ? "Selling" : "Idle" }),
            Node(key: "home", title: "Home", color: EnergyPalette.home, present: true,
                 value: sys.loadWatts.map(EnergyUnits.power) ?? "No reading", detail: nil),
            Node(key: "battery", title: "Battery", color: EnergyPalette.battery, present: sys.hasBattery,
                 value: charge ?? (sys.batteryWatts.map(EnergyUnits.power) ?? "No reading"),
                 detail: sys.batteryWatts == nil ? nil : b < -20 ? "Charging \(EnergyUnits.power(b))"
                     : b > 20 ? "Using \(EnergyUnits.power(b))" : "Resting"),
        ]
    }

    @ViewBuilder
    private var hub: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Theme.fg.opacity(0.1), .clear], center: .center, startRadius: 0, endRadius: 40))
                .frame(width: 80, height: 80)
            if sys.hasInverter {
                DeviceArtView(kind: .inverter, active: true, accent: EnergyPalette.accent(.inverter), size: 46)
            } else {
                Circle().fill(Theme.fg.opacity(0.85)).frame(width: 8, height: 8)
                    .glow(color: Theme.fg.opacity(0.6), radius: 6)
            }
        }
    }

    /// The circle sits exactly on its point; the label goes beside it for the ends on the
    /// vertical line (so it stays off the wiring) and below it for the ends at the sides.
    private func node(_ n: Node, at p: CGPoint) -> some View {
        let beside = n.key == "solar" || n.key == "battery"
        return ZStack {
            ZStack {
                Circle().fill(RadialGradient(colors: [n.color.opacity(n.present ? 0.24 : 0.06), Theme.fg.opacity(0.03)],
                                             center: .center, startRadius: 0, endRadius: 30))
                Circle().strokeBorder(LinearGradient(colors: [n.color.opacity(n.present ? 0.6 : 0.15), n.color.opacity(0.08)],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 1)
                icon(n)
            }
            .frame(width: 56, height: 56)
            .background(Circle().fill(Theme.base))
            .position(p)
            VStack(alignment: beside ? .leading : .center, spacing: 1) {
                Text(n.value).font(.system(size: 14, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(n.present ? Theme.ink : Theme.faint)
                Text(n.detail ?? n.title).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.muted)
            }
            .lineLimit(1)
            .frame(width: 130, alignment: beside ? .leading : .center)
            .position(beside ? CGPoint(x: p.x + 40 + 65, y: p.y) : CGPoint(x: p.x, y: p.y + 51))
        }
        .opacity(n.present ? 1 : 0.6)
    }

    @ViewBuilder
    private func icon(_ n: Node) -> some View {
        switch n.key {
        case "solar": DeviceArtView(kind: .solarPanel, active: n.present && (sys.solarWatts ?? 0) > 10, accent: n.color, size: 46)
        case "battery": DeviceArtView(kind: .battery, active: n.present, accent: n.color, size: 46)
        case "grid": Image(systemName: "bolt.fill").font(.system(size: 19, weight: .regular)).foregroundStyle(n.color)
        default: Image(systemName: "house.fill").font(.system(size: 19, weight: .regular)).foregroundStyle(n.color)
        }
    }

    private func draw(_ ctx: GraphicsContext, flows: PowerFlows, at: [String: CGPoint], time: TimeInterval) {
        let hub = at["hub"]!
        let routes: [(String, String, Double, Color)] = [
            ("solar", "home", flows.solarToHome, EnergyPalette.solar),
            ("solar", "battery", flows.solarToBattery, EnergyPalette.solar),
            ("solar", "grid", flows.solarToGrid, EnergyPalette.solar),
            ("grid", "home", flows.gridToHome, EnergyPalette.grid),
            ("grid", "battery", flows.gridToBattery, EnergyPalette.grid),
            ("battery", "home", flows.batteryToHome, EnergyPalette.battery),
            ("battery", "grid", flows.batteryToGrid, EnergyPalette.battery),
        ]
        // The quiet wiring between every end that's there, so the shape reads at rest.
        let present = ["solar": sys.hasSolar, "grid": sys.hasGrid, "battery": sys.hasBattery, "home": true]
        for key in ["solar", "grid", "home", "battery"] where present[key] == true {
            var line = Path()
            line.move(to: at[key]!)
            line.addLine(to: hub)
            ctx.stroke(line, with: .color(Theme.fg.opacity(0.07)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        for (from, to, watts, color) in routes where watts > 5 {
            let a = at[from]!, b = at[to]!
            var path = Path()
            path.move(to: a)
            path.addQuadCurve(to: b, control: hub)
            let strength = min(max(log10(watts / 10) / 3, 0.15), 1)
            ctx.stroke(path, with: .color(color.opacity(0.14 + 0.2 * strength)), style: StrokeStyle(lineWidth: 1.5 + 1.5 * strength, lineCap: .round))

            // Light running along the path.
            let count = Int(2 + 4 * strength)
            let speed = 0.16 + 0.3 * strength
            for i in 0..<count {
                let t = (time * speed + Double(i) / Double(count)).truncatingRemainder(dividingBy: 1)
                // Fade in near the source and out near the destination, so dots never pop.
                let fade = min(t / 0.15, (1 - t) / 0.15, 1)
                let p = point(a, hub, b, t)
                let r = 2.2 + 1.2 * strength
                var glow = ctx
                glow.addFilter(.blur(radius: r * 1.6))
                glow.blendMode = .plusLighter
                glow.fill(Path(ellipseIn: CGRect(x: p.x - r * 2, y: p.y - r * 2, width: r * 4, height: r * 4)),
                          with: .color(color.opacity(0.55 * fade)))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r / 2, y: p.y - r / 2, width: r, height: r)),
                         with: .color(Theme.fg.opacity(0.95 * fade)))
            }
        }
    }

    private func point(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u * u * a.x + 2 * u * t * c.x + t * t * b.x, y: u * u * a.y + 2 * u * t * c.y + t * t * b.y)
    }

    private func summary(_ f: PowerFlows) -> String {
        var parts: [String] = []
        if let s = sys.solarWatts { parts.append("Solar producing \(EnergyUnits.power(s))") }
        if let b = sys.batteryWatts { parts.append(b < -20 ? "battery charging at \(EnergyUnits.power(b))" : b > 20 ? "battery supplying \(EnergyUnits.power(b))" : "battery resting") }
        if let g = sys.gridWatts { parts.append(g > 20 ? "buying \(EnergyUnits.power(g)) from the grid" : g < -20 ? "selling \(EnergyUnits.power(g)) to the grid" : "grid idle") }
        if let l = sys.loadWatts { parts.append("home using \(EnergyUnits.power(l))") }
        return parts.joined(separator: ", ")
    }
}

// MARK: Battery

private struct BatteryCard: View {
    let sys: EnergySystem

    var body: some View {
        let soc = sys.chargePercent
        let w = sys.batteryWatts
        Bezel(radius: 24, inset: 4, lit: (w ?? 0) < -20, tint: EnergyPalette.battery) {
            HStack(spacing: 18) {
                ChargeRing(percent: soc, charging: (w ?? 0) < -20)
                VStack(alignment: .leading, spacing: 6) {
                    Text("BATTERY").eyebrow()
                    Text(state(soc: soc, watts: w)).font(.system(size: 16, weight: .semibold))
                    if let eta = eta(soc: soc, watts: w) {
                        Text(eta).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    let facts = readouts()
                    if !facts.isEmpty {
                        HStack(spacing: 12) {
                            ForEach(facts, id: \.0) { fact in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(fact.1).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                                    Text(fact.0).font(.system(size: 11)).foregroundStyle(Theme.faint)
                                }
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .accessibilityElement(children: .combine)
    }

    private func state(soc: Double?, watts: Double?) -> String {
        guard let w = watts else { return soc.map { $0 >= 99 ? "Full" : "Charge \(Int($0.rounded()))%" } ?? "Battery" }
        if w < -20 { return "Charging at \(EnergyUnits.power(w))" }
        if w > 20 { return "Supplying \(EnergyUnits.power(w))" }
        if let soc, soc >= 99 { return "Full" }
        return "Resting"
    }

    private func eta(soc: Double?, watts: Double?) -> String? {
        guard let soc, let w = watts, let capacity = sys.capacityWattHours, abs(w) > 20 else { return nil }
        if w < 0 {
            let hours = capacity * (100 - soc) / 100 / abs(w)
            return soc >= 99 ? nil : "Full in about \(EnergyUnits.duration(hours: hours))"
        }
        let hours = capacity * soc / 100 / w
        return "Lasts about \(EnergyUnits.duration(hours: hours)) at this rate"
    }

    private func readouts() -> [(String, String)] {
        var out: [(String, String)] = []
        if let v = sys.batteryVoltage.flatMap({ Double($0.state) }) { out.append(("Voltage", String(format: "%.1f V", v))) }
        if let a = sys.batteryCurrent.flatMap({ Double($0.state) }) { out.append(("Current", String(format: "%.1f A", abs(a)))) }
        if let t = sys.batteryTemperature, let v = Double(t.state) {
            out.append(("Temperature", "\(Int(v.rounded()))\(t.str("unit_of_measurement") ?? "°")"))
        }
        if let c = sys.capacityWattHours { out.append(("Size", EnergyUnits.energy(c / 1000))) }
        return Array(out.prefix(3))
    }
}

/// How full the battery is, as a ring that glows while it charges.
private struct ChargeRing: View {
    let percent: Double?
    let charging: Bool

    var body: some View {
        let p = min(max((percent ?? 0) / 100, 0), 1)
        let color = (percent ?? 100) < 20 ? Theme.live : (percent ?? 100) < 45 ? EnergyPalette.solar : EnergyPalette.battery
        ZStack {
            Circle().stroke(Theme.fg.opacity(0.07), lineWidth: 9)
            Circle().trim(from: 0, to: p)
                .stroke(AngularGradient(colors: [color.opacity(0.55), color], center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(360 * p)),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .glow(color: color.opacity(charging ? 0.6 : 0.25), radius: charging ? 10 : 5)
            VStack(spacing: 0) {
                Text(percent.map { "\(Int($0.rounded()))" } ?? "?")
                    .font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                    + Text("%").font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundColor(Theme.muted)
                if charging {
                    Image(systemName: "bolt.fill").font(.system(size: 11)).foregroundStyle(color)
                }
            }
        }
        .frame(width: 104, height: 104)
        .animation(.glide, value: p)
        .accessibilityLabel(percent.map { "Battery \(Int($0.rounded())) percent" } ?? "Battery charge unknown")
    }
}

// MARK: Solar

private struct SolarCard: View {
    let sys: EnergySystem
    @ObservedObject var feed: EnergyFeed

    var body: some View {
        let now = sys.solarWatts
        let producing = (now ?? 0) > 10
        Bezel(radius: 24, inset: 4, lit: producing, tint: EnergyPalette.solar) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    DeviceArtView(kind: .solarPanel, active: producing, accent: EnergyPalette.solar, size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SOLAR").eyebrow()
                        Text(now.map(EnergyUnits.power) ?? "No reading")
                            .font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text(producing ? "Producing now" : "Not producing right now")
                            .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                    if let today = todayKWh {
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("TODAY").eyebrow()
                            Text(EnergyUnits.energy(today)).font(.system(size: 16, weight: .semibold)).monospacedDigit()
                        }
                    }
                }
                if feed.solarDay.contains(where: { $0 > 0 }) {
                    Sparkline(values: feed.solarDay, color: EnergyPalette.solar)
                        .frame(height: 56)
                    HStack {
                        Text("Last 24 hours").font(.system(size: 11.5)).foregroundStyle(Theme.faint)
                        Spacer()
                        if let peak = feed.solarDay.max() {
                            Text("Peak \(EnergyUnits.power(peak))").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private var todayKWh: Double? {
        if let prefs = feed.prefs, !prefs.solar.isEmpty {
            let values = prefs.solar.compactMap { feed.today[$0] }
            if !values.isEmpty { return values.reduce(0, +) }
        }
        return EnergyUnits.kilowattHours(sys.solarToday)
    }
}

/// A day's curve: a soft filled area under a bright line.
private struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1, let top = values.max(), top > 0 else { return }
            let step = size.width / CGFloat(values.count - 1)
            func y(_ v: Double) -> CGFloat { size.height - CGFloat(v / top) * (size.height - 4) - 1 }
            var line = Path()
            for (i, v) in values.enumerated() {
                let p = CGPoint(x: CGFloat(i) * step, y: y(v))
                if i == 0 { line.move(to: p) } else {
                    let prev = CGPoint(x: CGFloat(i - 1) * step, y: y(values[i - 1]))
                    line.addCurve(to: p, control1: CGPoint(x: prev.x + step / 2, y: prev.y), control2: CGPoint(x: p.x - step / 2, y: p.y))
                }
            }
            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()
            ctx.fill(area, with: .linearGradient(Gradient(colors: [color.opacity(0.3), color.opacity(0)]),
                                                 startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

// MARK: Today

/// Today's totals from the Energy dashboard: what the sun made, what came from and went
/// to the grid, and what went in and out of the battery.
private struct TodayCard: View {
    let sys: EnergySystem
    @ObservedObject var feed: EnergyFeed

    var body: some View {
        let tiles = self.tiles
        if !tiles.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("TODAY").eyebrow().padding(.leading, 4)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(tiles, id: \.0) { tile in
                        HStack(spacing: 10) {
                            Image(systemName: tile.2).font(.system(size: 13, weight: .medium)).foregroundStyle(tile.3)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(tile.3.opacity(0.12)))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(EnergyUnits.energy(tile.1)).font(.system(size: 14, weight: .semibold)).monospacedDigit()
                                Text(tile.0).font(.system(size: 11.5)).foregroundStyle(Theme.muted).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.fg.opacity(0.035))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.75)))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private var tiles: [(String, Double, String, Color)] {
        guard let prefs = feed.prefs else { return [] }
        func sum(_ ids: [String]) -> Double? {
            let v = ids.compactMap { feed.today[$0] }
            return v.isEmpty ? nil : v.reduce(0, +)
        }
        var out: [(String, Double, String, Color)] = []
        if let v = sum(prefs.solar) { out.append(("Solar made", v, "sun.max.fill", EnergyPalette.solar)) }
        if let v = sum(prefs.gridIn) { out.append(("From the grid", v, "arrow.down.left", EnergyPalette.grid)) }
        if let v = sum(prefs.gridOut) { out.append(("To the grid", v, "arrow.up.right", EnergyPalette.grid)) }
        if let v = sum(prefs.batteryIn) { out.append(("Into battery", v, "battery.100.bolt", EnergyPalette.battery)) }
        if let v = sum(prefs.batteryOut) { out.append(("From battery", v, "battery.50", EnergyPalette.battery)) }
        return out
    }
}

// MARK: Inverter

private struct InverterCard: View {
    let sys: EnergySystem
    let open: (String) -> Void

    var body: some View {
        let device = sys.devices.first { $0.kind == .inverter }
        Bezel(radius: 24, inset: 4) {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    if let device { open(device.id) }
                } label: {
                    HStack(spacing: 12) {
                        DeviceBadge(kind: .inverter, active: true, accent: EnergyPalette.accent(.inverter), size: 46)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device?.name ?? "Inverter").font(.system(size: 14, weight: .semibold)).lineLimit(1)
                            if let maker = [device?.info.manufacturer, device?.info.model].compactMap({ $0 }).joined(separator: " · ").nonEmpty {
                                Text(maker).font(.system(size: 11.5)).foregroundStyle(Theme.muted).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                        if device != nil {
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.faint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .disabled(device == nil)
                .accessibilityLabel("Open \(device?.name ?? "inverter")")

                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                        HStack {
                            Text(row.0).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                            Spacer()
                            Text(row.1).font(.system(size: 12.5, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(row.2 ?? Theme.ink).lineLimit(1)
                        }
                        .padding(.vertical, 8)
                        .accessibilityElement(children: .combine)
                        if i < rows.count - 1 { Rectangle().fill(Theme.hairline).frame(height: 0.75) }
                    }
                }
            }
            .padding(14)
        }
    }

    private var rows: [(String, String, Color?)] {
        var out: [(String, String, Color?)] = []
        if let m = sys.inverterMode { out.append(("Mode", m.state.pretty, nil)) }
        if let l = sys.outputLoad, let v = Double(l.state) { out.append(("Output load", "\(Int(v.rounded()))%", nil)) }
        if let w = sys.loadWatts { out.append(("Powering the house", EnergyUnits.power(w), nil)) }
        if let t = sys.inverterTemperature, let v = Double(t.state) {
            out.append(("Temperature", "\(Int(v.rounded()))\(t.str("unit_of_measurement") ?? "°")", nil))
        }
        if sys.faults.isEmpty {
            out.append(("Faults", "None", Theme.ok))
        } else {
            for f in sys.faults.prefix(3) {
                out.append((f.name, f.domain == "binary_sensor" ? "Problem" : f.state.pretty, Theme.live))
            }
        }
        return out
    }
}

// MARK: Cells

/// Each cell's voltage in a compact grid, the lowest and highest picked out, and the spread
/// between them: the first sign of a pack drifting out of balance.
private struct CellsCard: View {
    let cells: [Entity]
    let temperatures: [Entity]

    var body: some View {
        let volts = cells.map(voltage)
        let low = volts.compactMap { $0 }.min(), high = volts.compactMap { $0 }.max()
        Bezel(radius: 24, inset: 4) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("CELLS").eyebrow()
                    Spacer()
                    if let low, let high {
                        Text("Spread \(Int(((high - low) * 1000).rounded())) mV")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(Array(cells.enumerated()), id: \.element.id) { i, cell in
                        let v = volts[i]
                        let tint: Color? = v == nil ? nil : v == low ? Theme.air("cool") : v == high ? EnergyPalette.solar : nil
                        VStack(spacing: 1) {
                            Text("\(EnergySystem.number(cell) ?? i + 1)").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.faint)
                            Text(v.map { String(format: "%.3f", $0) } ?? "?").font(.system(size: 12.5, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(tint ?? Theme.ink)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill((tint ?? Theme.fg).opacity(tint == nil ? 0.035 : 0.1)))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Cell \(EnergySystem.number(cell) ?? i + 1), \(v.map { String(format: "%.3f volts", $0) } ?? "no reading")")
                    }
                }
                if !temperatures.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "thermometer.medium").font(.system(size: 12)).foregroundStyle(Theme.muted)
                        Text(temperatures.compactMap { t in Double(t.state).map { "\(Int($0.rounded()))°" } }.joined(separator: "  "))
                            .font(.system(size: 12.5, weight: .medium)).monospacedDigit().foregroundStyle(Theme.muted)
                    }
                }
            }
            .padding(14)
        }
    }

    private func voltage(_ e: Entity) -> Double? {
        guard let v = Double(e.state) else { return nil }
        return e.str("unit_of_measurement") == "mV" ? v / 1000 : v
    }
}

// MARK: Getting started

/// A note for systems that are connected but not yet set up in the Energy dashboard.
private struct DashboardHint: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle").font(.system(size: 14)).foregroundStyle(Theme.muted)
            Text("Set up the Energy dashboard in Home Assistant (Settings, Dashboards, Energy) so Hearth knows exactly which sensor is which, and can show today's totals.")
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 6)
    }
}

/// How to bring an inverter, batteries and solar into Home Assistant.
struct EnergyHowTo: View {
    private let steps: [(DeviceKind, String, String)] = [
        (.inverter, "Inverters built into Home Assistant",
         "Enphase Envoy, SolarEdge, Fronius, SMA, GoodWe, Growatt, Solax and APsystems each have an integration in Settings, Devices and services."),
        (.inverter, "Deye, Sunsynk and Wi-Fi logger inverters",
         "Solarman, from HACS, reads the Solarman Wi-Fi stick directly on your network. Many hybrid inverters sold under other names use the same stick. Sunsynk also has a community integration."),
        (.inverter, "Voltronic, MUST and other off-grid inverters",
         "These are often sold under other brand names, which may include CWORTH. Connect over USB or serial with a community add-on, or through a Solarman-style Wi-Fi logger if yours has one."),
        (.battery, "Lithium batteries",
         "BMS BLE, from HACS, reads JK, Daly and many other battery BMSs over Bluetooth, and ESPHome works too. Tesla Powerwall and Victron over Bluetooth are built in."),
        (.solarPanel, "Then set up the Energy dashboard",
         "In Home Assistant, open Settings, Dashboards, Energy, and add your solar, battery and grid sensors. Hearth reads that setup first."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TryDemoCard(message: "Watch a day of sun, battery and grid on a sample house, sped up.").padding(.bottom, 4)
            Text("CONNECT THROUGH HOME ASSISTANT").eyebrow().padding(.leading, 4)
            Bezel(radius: 22, inset: 3) {
                VStack(spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 12) {
                            DeviceBadge(kind: step.0, accent: EnergyPalette.accent(step.0), size: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.1).font(.system(size: 13, weight: .semibold))
                                Text(step.2).font(.system(size: 12)).foregroundStyle(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .accessibilityElement(children: .combine)
                        if i < steps.count - 1 { Rectangle().fill(Theme.hairline).frame(height: 0.75).padding(.leading, 62) }
                    }
                }
            }
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
