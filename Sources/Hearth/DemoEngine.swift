import Foundation
import SwiftUI

/// Sample homes that move on their own, so people can see what each section does before they
/// connect anything. A demo plays inside its own `HomeStore`, which never talks to Home
/// Assistant: the same pages and cards draw it, and their buttons are answered here.
@MainActor
final class DemoEngine: ObservableObject {
    enum Kind: String, CaseIterable {
        case energy, vehicles, gadgets
    }

    /// How fast simulated time runs, so a whole day or a whole charge can go by while you watch.
    enum Speed: Double, CaseIterable, Identifiable {
        case real = 1, minute = 60, tenMinutes = 600
        var id: Double { rawValue }
        var label: String { "\(Int(rawValue))×" }
    }

    let kind: Kind
    let store = HomeStore()
    @Published var speed: Speed
    @Published private(set) var car: DemoCar
    /// The simulated time of day, for the energy demo's sun.
    @Published private(set) var clock: Date

    private var energy = EnergyModel()
    private var vehicles = VehicleModel()
    private var gadgets = GadgetModel()
    private var lastTick = Date()

    init(_ kind: Kind) {
        self.kind = kind
        speed = kind == .gadgets ? .minute : .tenMinutes
        car = DemoCar.all[1]
        // Late morning: the sun is up, the battery is filling, and there's power to spare.
        clock = Calendar.current.startOfDay(for: Date()).addingTimeInterval(11.25 * 3600)
        load()
        warmUp()
    }

    /// One step before the first frame, so a demo is already moving when it appears.
    private func warmUp() {
        switch kind {
        case .energy: energy.advance(seconds: 60, at: clock)
        case .vehicles: vehicles.advance(seconds: 60, real: 0.1, car: car)
        case .gadgets: gadgets.advance(seconds: 60, real: 0.1)
        }
        store.playDemo(update: entities)
    }

    /// Picks another car; the demo starts its charge again with that car's battery.
    func choose(_ car: DemoCar) {
        self.car = car
        let model = CarModel.from(manufacturer: car.maker, model: car.model)
        CarPaints.shared.setDemo(model.palette[0], for: "demo-car")
        vehicles = VehicleModel()
        load()
        warmUp()
    }

    /// Moves the demo on by the real time since the last step. Call it on a short timer while visible.
    func step() {
        let now = Date()
        let real = min(now.timeIntervalSince(lastTick), 2)
        lastTick = now
        let simulated = real * speed.rawValue
        clock = clock.addingTimeInterval(simulated)
        switch kind {
        case .energy: energy.advance(seconds: simulated, at: clock)
        case .vehicles: vehicles.advance(seconds: simulated, real: real, car: car)
        case .gadgets: gadgets.advance(seconds: simulated, real: real)
        }
        store.playDemo(update: entities)
    }

    /// Runs the demo until the task is cancelled.
    func run() async {
        lastTick = Date()
        while !Task.isCancelled {
            step()
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    // MARK: Building the sample home

    private func load() {
        let (devices, ownership) = sampleDevices
        store.playDemo(devices: devices, entities: entities, deviceOf: ownership) { [weak self] body in
            MainActor.assumeIsolated { self?.answer(body) }
        }
    }

    private var sampleDevices: ([DeviceInfo], [String: String]) {
        let devices: [DeviceInfo]
        switch kind {
        case .energy:
            devices = [
                DeviceInfo(id: "demo-inverter", name: "Hybrid inverter", manufacturer: "Demo Solar", model: "8 kW hybrid inverter"),
                DeviceInfo(id: "demo-battery", name: "Home battery", manufacturer: "Demo Solar", model: "LiFePO4 battery pack 10 kWh"),
                DeviceInfo(id: "demo-panels", name: "Roof panels", manufacturer: "Demo Solar", model: "Solar panel array, 12 × 450 W"),
            ] + EnergyModel.appliances.map { a in
                DeviceInfo(id: "demo-\(a.slug)", name: a.name, manufacturer: a.maker, model: a.model)
            }
        case .vehicles:
            devices = [
                DeviceInfo(id: "demo-car", name: car.name, manufacturer: car.maker, model: car.model),
                DeviceInfo(id: "demo-charger", name: "Driveway charger", manufacturer: "Wallbox", model: "Pulsar Plus"),
                DeviceInfo(id: "demo-vacuum", name: "Robot vacuum", manufacturer: "Roborock", model: "S8 Pro Ultra"),
                DeviceInfo(id: "demo-mower", name: "Garden mower", manufacturer: "Husqvarna", model: "Automower 430X"),
                DeviceInfo(id: "demo-jet", name: "Electric jet", manufacturer: "Demo Aero", model: "eVTOL"),
            ]
        case .gadgets:
            devices = [
                DeviceInfo(id: "demo-printer", name: "Workshop P1S", manufacturer: "Bambu Lab", model: "P1S"),
                DeviceInfo(id: "demo-ps5", name: "PlayStation 5", manufacturer: "Sony Interactive Entertainment", model: "PlayStation 5"),
                DeviceInfo(id: "demo-mac", name: "Studio Mac mini", manufacturer: "Apple", model: "Mac mini (M4)"),
            ]
        }
        // Entity ids start with their device's name, as Home Assistant names them: sensor.model_y_battery_level.
        let bySlug = devices.map { (Self.slug($0.name), $0.id) }.sorted { $0.0.count > $1.0.count }
        let ownership = Dictionary(uniqueKeysWithValues: entities.map { e in
            let object = String(e.id.drop { $0 != "." }.dropFirst())
            return (e.id, bySlug.first { object.hasPrefix($0.0 + "_") || object == $0.0 }?.1 ?? devices[0].id)
        })
        return (devices, ownership)
    }

    /// "Model Y" to model_y, the way Home Assistant turns a device's name into entity ids.
    nonisolated static func slug(_ name: String) -> String {
        name.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: "_")
    }

    private var entities: [Entity] {
        switch kind {
        case .energy: energy.entities(at: clock)
        case .vehicles: vehicles.entities(car: car)
        case .gadgets: gadgets.entities
        }
    }

    // MARK: Answering the pages

    /// Everything a page would have asked Home Assistant, answered from the simulation.
    private func answer(_ body: JSON) -> Any? {
        switch body["type"] as? String {
        case "call_service":
            let domain = body["domain"] as? String ?? ""
            let service = body["service"] as? String ?? ""
            let target = (body["target"] as? JSON)?["entity_id"] as? String ?? ""
            let data = body["service_data"] as? JSON ?? [:]
            switch kind {
            case .energy: break
            case .vehicles: vehicles.handle(domain, service, target, data)
            case .gadgets: gadgets.handle(domain, service, target)
            }
            store.playDemo(update: entities)
            return nil
        case "energy/get_prefs":
            return kind == .energy ? EnergyModel.prefs : nil
        case "recorder/statistic_during_period":
            guard kind == .energy, let id = body["statistic_id"] as? String else { return nil }
            return ["change": energy.today(id)]
        case "history/history_during_period":
            guard kind == .energy else { return nil }
            return energy.history(clock: clock)
        default:
            return nil
        }
    }
}

// MARK: Cars to choose from

struct DemoCar: Identifiable, Equatable {
    let maker: String
    let model: String
    /// Usable battery, in kWh.
    let capacity: Double
    /// WLTP range on a full battery, in km.
    let range: Double
    /// Fastest home (AC) charging, in kW.
    let homeCharging: Double

    var id: String { maker + model }
    var name: String { model }
    var title: String { "\(maker) \(model)" }

    static let all: [DemoCar] = [
        DemoCar(maker: "Tesla", model: "Model 3", capacity: 60, range: 513, homeCharging: 11),
        DemoCar(maker: "Tesla", model: "Model Y", capacity: 75, range: 533, homeCharging: 11),
        DemoCar(maker: "BYD", model: "Atto 3", capacity: 60.5, range: 420, homeCharging: 7),
        DemoCar(maker: "BYD", model: "Seal", capacity: 82.5, range: 570, homeCharging: 11),
        DemoCar(maker: "Hyundai", model: "Ioniq 5", capacity: 77.4, range: 507, homeCharging: 11),
        DemoCar(maker: "Kia", model: "EV6", capacity: 77.4, range: 528, homeCharging: 11),
        DemoCar(maker: "BMW", model: "i4", capacity: 80.7, range: 590, homeCharging: 11),
        DemoCar(maker: "Polestar", model: "Polestar 2", capacity: 78, range: 551, homeCharging: 11),
    ]
}

// MARK: Energy: a house with solar, a battery and the grid

private struct EnergyModel {
    static let capacity = 10.2  // kWh
    var soc = 58.0
    var solarToday = 3.1, gridInToday = 2.4, gridOutToday = 0.2, batteryInToday = 1.1, batteryOutToday = 2.6
    var solar = 0.0, load = 0.0, battery = 0.0, grid = 0.0
    var cloud = 1.0
    var dayOfLastTick = 0
    /// What each appliance in the demo home draws, in W, adding up to the house load.
    var applianceWatts: [String: Double] = [:]
    /// What each has used today, in kWh.
    var applianceToday: [String: Double] = ["living_room_air_conditioner": 1.9, "kitchen_fridge": 0.62, "lounge_tv": 0.05,
                                            "studio_mac_mini": 0.31, "hallway_lights": 0.12, "kitchen_sockets": 1.4]

    struct Appliance {
        let slug: String
        let name: String
        let maker: String
        let model: String
    }

    /// The demo home's appliances. Each reports its power and its energy today, like a smart plug.
    static let appliances: [Appliance] = [
        Appliance(slug: "living_room_air_conditioner", name: "Living room air conditioner", maker: "Demo Air", model: "Split air conditioner 3.5 kW"),
        Appliance(slug: "kitchen_fridge", name: "Kitchen fridge", maker: "Demo Kitchen", model: "Fridge freezer"),
        Appliance(slug: "lounge_tv", name: "Lounge TV", maker: "Demo Vision", model: "65 inch OLED TV"),
        Appliance(slug: "studio_mac_mini", name: "Studio Mac mini", maker: "Apple", model: "Mac mini (M4)"),
        Appliance(slug: "hallway_lights", name: "Hallway lights", maker: "Demo Light", model: "Smart lights"),
        Appliance(slug: "kitchen_sockets", name: "Kitchen sockets", maker: "Demo Plug", model: "Smart plug strip"),
    ]

    /// Splits the house load between the appliances: the fridge cycling, the Mac idling, the TV
    /// and lights in the evening, the air conditioner taking the afternoon and evening peaks,
    /// and the kitchen sockets the rest.
    static func split(load: Double, at date: Date) -> [String: Double] {
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        let h = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
        func bump(_ centre: Double, _ width: Double, _ height: Double) -> Double {
            height * exp(-pow((h - centre) / width, 2))
        }
        let fridge = (h * 60).truncatingRemainder(dividingBy: 40) < 18 ? 118.0 : 3.0
        let mac = 28 + 9 * sin(h * 1.7)
        let tv = (h >= 18 && h < 23.5) || (h >= 7 && h < 8) ? 96.0 : 0.6
        let lights = (h >= 18.5 && h < 23.5) ? 140.0 : (h >= 6 && h < 8 ? 55.0 : 6.0)
        let fixed = fridge + mac + tv + lights
        let ac = max(min(bump(13, 2.5, 650) * 0.8 + bump(19.5, 1.8, 2300) * 0.6, load - fixed - 40), 0)
        let sockets = max(load - fixed - ac, 0)
        return ["living_room_air_conditioner": ac, "kitchen_fridge": fridge, "lounge_tv": tv,
                "studio_mac_mini": mac, "hallway_lights": lights, "kitchen_sockets": sockets]
    }

    /// The sun's power at a time of day: rising at six, peaking after noon, gone by seven.
    static func sun(at date: Date, cloud: Double = 1) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        let h = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
        guard h > 6, h < 19 else { return 0 }
        return 5400 * pow(sin(.pi * (h - 6) / 13), 1.4) * cloud
    }

    /// What the house draws: a quiet base, breakfast, and the evening with cooking and the AC.
    static func house(at date: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let h = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
        func bump(_ centre: Double, _ width: Double, _ height: Double) -> Double {
            height * exp(-pow((h - centre) / width, 2))
        }
        return 420 + bump(7.5, 1, 1100) + bump(13, 2.5, 650) + bump(19.5, 1.8, 2300)
    }

    mutating func advance(seconds: Double, at date: Date) {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        if day != dayOfLastTick {
            if dayOfLastTick != 0 {
                solarToday = 0; gridInToday = 0; gridOutToday = 0; batteryInToday = 0; batteryOutToday = 0
                for k in applianceToday.keys { applianceToday[k] = 0 }
            }
            dayOfLastTick = day
        }
        // Clouds drift past now and then.
        cloud = min(max(cloud + Double.random(in: -0.04...0.04) * min(seconds / 60, 4), 0.55), 1)
        solar = Self.sun(at: date, cloud: cloud)
        load = Self.house(at: date) * Double.random(in: 0.97...1.03)
        let surplus = solar - load
        if surplus > 0 {
            let charge = soc < 99.5 ? min(surplus, 3600) : 0
            battery = -charge
            grid = -(surplus - charge)
        } else {
            let discharge = soc > 12 ? min(-surplus, 4200) : 0
            battery = discharge
            grid = -surplus - discharge
        }
        let hours = seconds / 3600
        applianceWatts = Self.split(load: load, at: date)
        for (k, w) in applianceWatts { applianceToday[k, default: 0] += w / 1000 * hours }
        soc = min(max(soc - battery / 1000 * hours / Self.capacity * 100, 0), 100)
        solarToday += solar / 1000 * hours
        if grid > 0 { gridInToday += grid / 1000 * hours } else { gridOutToday += -grid / 1000 * hours }
        if battery < 0 { batteryInToday += -battery / 1000 * hours } else { batteryOutToday += battery / 1000 * hours }
    }

    func entities(at date: Date) -> [Entity] {
        func e(_ id: String, _ value: Double, _ unit: String, _ cls: String?, digits: Int = 0) -> Entity {
            var attrs: JSON = ["unit_of_measurement": unit, "state_class": "measurement"]
            if let cls { attrs["device_class"] = cls }
            attrs["friendly_name"] = id.drop { $0 != "." }.dropFirst().replacingOccurrences(of: "_", with: " ").capitalized
            return Entity(id: id, state: String(format: "%.\(digits)f", value), attributes: attrs, lastChanged: date)
        }
        func text(_ id: String, _ value: String) -> Entity {
            Entity(id: id, state: value, attributes: ["friendly_name": id.drop { $0 != "." }.dropFirst().replacingOccurrences(of: "_", with: " ").capitalized])
        }
        let volts = 51.2 + (soc - 50) * 0.045
        let throughput = abs(battery) + solar
        var list: [Entity] = [
            e("sensor.hybrid_inverter_pv_power", solar, "W", "power"),
            e("sensor.hybrid_inverter_battery_power", battery, "W", "power"),
            e("sensor.hybrid_inverter_grid_power", grid, "W", "power"),
            e("sensor.hybrid_inverter_load_power", load, "W", "power"),
            e("sensor.hybrid_inverter_output_load", load / 8000 * 100, "%", nil),
            e("sensor.hybrid_inverter_temperature", 33 + throughput / 600, "°C", "temperature", digits: 1),
            text("sensor.hybrid_inverter_work_mode", solar > load ? "Self use" : soc > 12 ? "Battery first" : "Grid"),
            text("sensor.hybrid_inverter_fault", "No fault"),
            e("sensor.hybrid_inverter_pv_energy_today", solarToday, "kWh", "energy", digits: 2),
            e("sensor.hybrid_inverter_grid_import_today", gridInToday, "kWh", "energy", digits: 2),
            e("sensor.hybrid_inverter_grid_export_today", gridOutToday, "kWh", "energy", digits: 2),
            e("sensor.home_battery_charge_today", batteryInToday, "kWh", "energy", digits: 2),
            e("sensor.home_battery_discharge_today", batteryOutToday, "kWh", "energy", digits: 2),
            e("sensor.home_battery_soc", soc, "%", "battery"),
            e("sensor.home_battery_voltage", volts, "V", "voltage", digits: 1),
            e("sensor.home_battery_current", -battery / volts, "A", "current", digits: 1),
            e("sensor.home_battery_temperature", 25.5 + abs(battery) / 1400, "°C", "temperature", digits: 1),
            e("sensor.home_battery_capacity", Self.capacity, "kWh", "energy_storage", digits: 1),
            e("sensor.roof_panels_pv_power", solar, "W", "power"),
        ]
        // Sixteen cells, each a few millivolts from the next, as a real pack drifts.
        let offsets: [Double] = [2, 8, -1, 11, 5, 7, -8, 9, 6, 4, 10, 8, 3, 6, 1, 7]
        let cell = 3.18 + soc * 0.0016
        for (i, o) in offsets.enumerated() {
            list.append(e("sensor.home_battery_cell_\(i + 1)_voltage", cell + o / 1000, "V", "voltage", digits: 3))
        }
        for i in 1...3 {
            list.append(e("sensor.home_battery_temperature_\(i)", 25 + Double(i) * 0.6 + abs(battery) / 1500, "°C", "temperature", digits: 1))
        }
        // The demo home's appliances, each with a smart plug's power and energy today.
        let split = applianceWatts.isEmpty ? Self.split(load: max(load, 420), at: date) : applianceWatts
        for a in Self.appliances {
            list.append(e("sensor.\(a.slug)_power", split[a.slug] ?? 0, "W", "power", digits: 1))
            var today = e("sensor.\(a.slug)_energy_today", applianceToday[a.slug] ?? 0, "kWh", "energy", digits: 2)
            today.attributes["state_class"] = "total_increasing"
            list.append(today)
        }
        return list
    }

    /// The Energy dashboard setup the demo pretends to have.
    static let prefs: JSON = [
        "energy_sources": [
            ["type": "solar", "stat_energy_from": "sensor.hybrid_inverter_pv_energy_today", "stat_rate": "sensor.hybrid_inverter_pv_power"],
            ["type": "battery", "stat_energy_from": "sensor.home_battery_discharge_today",
             "stat_energy_to": "sensor.home_battery_charge_today", "stat_rate": "sensor.hybrid_inverter_battery_power"],
            ["type": "grid", "flow_from": [["stat_energy_from": "sensor.hybrid_inverter_grid_import_today"]],
             "flow_to": [["stat_energy_to": "sensor.hybrid_inverter_grid_export_today"]], "stat_rate": "sensor.hybrid_inverter_grid_power"],
        ] as [JSON],
    ]

    func today(_ id: String) -> Double {
        switch id {
        case "sensor.hybrid_inverter_pv_energy_today": solarToday
        case "sensor.hybrid_inverter_grid_import_today": gridInToday
        case "sensor.hybrid_inverter_grid_export_today": gridOutToday
        case "sensor.home_battery_charge_today": batteryInToday
        case "sensor.home_battery_discharge_today": batteryOutToday
        default: 0
        }
    }

    /// The last day of solar, as Home Assistant's history would give it, ending at the demo's clock.
    func history(clock: Date) -> JSON {
        let now = Date()
        var rows: [JSON] = []
        for step in stride(from: 24 * 60, through: 0, by: -10) {
            let t = now.addingTimeInterval(-Double(step) * 60)
            let simulated = clock.addingTimeInterval(-Double(step) * 60)
            let wobble = 0.85 + 0.15 * sin(Double(step) / 37)
            rows.append(["s": String(format: "%.0f", Self.sun(at: simulated, cloud: wobble)), "lu": t.timeIntervalSince1970])
        }
        return ["sensor.hybrid_inverter_pv_power": rows]
    }
}

// MARK: Vehicles: a car that charges, drives and comes home

private struct VehicleModel {
    enum Phase { case charging, done, away, returning }
    var phase = Phase.charging
    var battery = 34.0
    var limit = 90.0
    var power = 0.0
    var added = 0.0
    var locked = true
    var chargeOn = true
    var climate = "off"
    var phaseTime = 0.0
    var vacuum = "cleaning", vacuumBattery = 72.0, vacuumTime = 0.0
    var mower = "mowing", mowerBattery = 64.0, mowerTime = 0.0
    var jet = 92.0

    mutating func advance(seconds: Double, real: Double, car: DemoCar) {
        phaseTime += real
        switch phase {
        case .charging:
            if chargeOn {
                // Full speed to 80%, then easing off towards the limit.
                let taper = battery < 80 ? 1 : max(0.25, 1 - (battery - 80) / 25)
                power = car.homeCharging * taper
                let gained = power * seconds / 3600
                added += gained
                battery = min(battery + gained / car.capacity * 100, limit)
                if battery >= limit - 0.05 { phase = .done; phaseTime = 0; power = 0 }
            } else {
                power = 0
            }
        case .done:
            power = 0
            if phaseTime > 8 { phase = .away; phaseTime = 0; chargeOn = false; locked = true }
        case .away:
            battery = max(battery - real * 7, 31)
            if phaseTime > 8 { phase = .returning; phaseTime = 0 }
        case .returning:
            if phaseTime > 2 { phase = .charging; phaseTime = 0; chargeOn = true; added = 0 }
        }

        vacuumTime += real
        switch vacuum {
        case "cleaning":
            vacuumBattery = max(vacuumBattery - real * 0.6, 20)
            if vacuumTime > 30 || vacuumBattery <= 20 { vacuum = "returning"; vacuumTime = 0 }
        case "returning":
            if vacuumTime > 5 { vacuum = "docked"; vacuumTime = 0 }
        case "docked":
            vacuumBattery = min(vacuumBattery + real * 1.5, 100)
            if vacuumTime > 25 { vacuum = "cleaning"; vacuumTime = 0 }
        default: break
        }
        mowerTime += real
        switch mower {
        case "mowing":
            mowerBattery = max(mowerBattery - real * 0.4, 25)
            if mowerTime > 40 || mowerBattery <= 25 { mower = "returning"; mowerTime = 0 }
        case "returning":
            if mowerTime > 6 { mower = "docked"; mowerTime = 0 }
        case "docked":
            mowerBattery = min(mowerBattery + real * 1.2, 100)
            if mowerTime > 30 { mower = "mowing"; mowerTime = 0 }
        default: break
        }
    }

    mutating func handle(_ domain: String, _ service: String, _ target: String, _ data: JSON) {
        switch (domain, service) {
        case ("lock", "lock"): locked = true
        case ("lock", "unlock"): locked = false
        case ("switch", "turn_on") where target.contains("charge"):
            chargeOn = true
            if phase != .charging, battery < limit - 0.1 { phase = .charging; phaseTime = 0 }
        case ("switch", "turn_off") where target.contains("charge"): chargeOn = false; power = 0
        case ("climate", "turn_on"): climate = "heat_cool"
        case ("climate", "turn_off"): climate = "off"
        case ("climate", "set_hvac_mode"): climate = data["hvac_mode"] as? String ?? climate
        case ("number", "set_value") where target.contains("charge_limit"):
            limit = (data["value"] as? NSNumber)?.doubleValue ?? limit
            if battery < limit - 0.1, phase == .done { phase = .charging; phaseTime = 0 }
        case ("vacuum", "start"): vacuum = "cleaning"; vacuumTime = 0
        case ("vacuum", "pause"): vacuum = "paused"
        case ("vacuum", "return_to_base"): vacuum = "returning"; vacuumTime = 0
        case ("lawn_mower", "start_mowing"): mower = "mowing"; mowerTime = 0
        case ("lawn_mower", "pause"): mower = "paused"
        case ("lawn_mower", "dock"): mower = "returning"; mowerTime = 0
        default: break
        }
    }

    func entities(car: DemoCar) -> [Entity] {
        func e(_ id: String, _ state: String, _ attrs: JSON = [:]) -> Entity { Entity(id: id, state: state, attributes: attrs) }
        let c = DemoEngine.slug(car.name)
        let plugged = phase == .charging || phase == .done
        let charging = phase == .charging && chargeOn && power > 0
        let chargingText = !plugged ? "disconnected" : charging ? "charging" : phase == .done ? "complete" : "stopped"
        var list: [Entity] = [
            e("sensor.\(c)_battery_level", String(format: "%.0f", battery), ["device_class": "battery", "unit_of_measurement": "%"]),
            e("sensor.\(c)_battery_range", String(format: "%.0f", battery / 100 * car.range),
              ["device_class": "distance", "unit_of_measurement": "km"]),
            e("sensor.\(c)_charging", chargingText, ["device_class": "enum"]),
            e("sensor.\(c)_charger_power", String(format: "%.1f", charging ? power : 0), ["device_class": "power", "unit_of_measurement": "kW"]),
            e("number.\(c)_charge_limit", String(format: "%.0f", limit), ["unit_of_measurement": "%", "min": 50, "max": 100, "step": 1]),
            e("device_tracker.\(c)_location", phase == .away ? "not_home" : "home"),
            e("lock.\(c)_lock", locked ? "locked" : "unlocked"),
            e("switch.\(c)_charge", chargeOn ? "on" : "off"),
            e("climate.\(c)_climate", climate, ["hvac_modes": ["off", "heat_cool"], "current_temperature": 24, "temperature": 21]),
        ]
        // Always there, as in Home Assistant, and unknown while it isn't charging.
        let hoursLeft = charging && power > 0 ? (limit - battery) / 100 * car.capacity / power : nil
        list.append(e("sensor.\(c)_time_to_full_charge",
                      hoursLeft.map { ISO8601DateFormatter().string(from: Date().addingTimeInterval($0 * 3600)) } ?? "unknown",
                      ["device_class": "timestamp"]))
        let chargerStatus = !plugged ? "Ready" : charging ? "Charging" : phase == .done ? "Connected: finished" : "Connected: waiting for car demand"
        list += [
            e("sensor.driveway_charger_status_description", chargerStatus),
            e("sensor.driveway_charger_charging_power", String(format: "%.1f", charging ? power : 0), ["device_class": "power", "unit_of_measurement": "kW"]),
            e("sensor.driveway_charger_added_energy", String(format: "%.1f", added), ["device_class": "energy", "unit_of_measurement": "kWh"]),
            e("vacuum.robot_vacuum", vacuum, ["battery_level": Int(vacuumBattery), "status": vacuum.capitalized]),
            e("sensor.robot_vacuum_battery", String(format: "%.0f", vacuumBattery), ["device_class": "battery", "unit_of_measurement": "%"]),
            e("lawn_mower.garden_mower", mower),
            e("sensor.garden_mower_battery", String(format: "%.0f", mowerBattery), ["device_class": "battery", "unit_of_measurement": "%"]),
            e("sensor.electric_jet_battery", String(format: "%.0f", jet), ["device_class": "battery", "unit_of_measurement": "%"]),
        ]
        return list
    }
}

// MARK: Gadgets: a printer mid-print, a console, a computer

private struct GadgetModel {
    enum Stage: String { case heating = "heatbed_preheating", leveling = "auto_bed_leveling", printing, finished = "idle" }
    var stage = Stage.printing
    var progress = 37.0
    var stageTime = 0.0
    var nozzle = 220.0, bed = 65.0
    var playing = true
    var consoleTime = 0.0
    /// A 1 h 45 min print.
    static let printMinutes = 105.0

    mutating func advance(seconds: Double, real: Double) {
        stageTime += real
        switch stage {
        case .heating:
            nozzle = min(nozzle + real * 18, 220)
            bed = min(bed + real * 5, 65)
            if nozzle >= 220, bed >= 65 { stage = .leveling; stageTime = 0 }
        case .leveling:
            if stageTime > 5 { stage = .printing; stageTime = 0 }
        case .printing:
            progress = min(progress + seconds / 60 / Self.printMinutes * 100, 100)
            nozzle = 220 + Double.random(in: -1...1)
            bed = 65 + Double.random(in: -0.3...0.3)
            if progress >= 100 { stage = .finished; stageTime = 0 }
        case .finished:
            nozzle = max(nozzle - real * 12, 28)
            bed = max(bed - real * 3, 27)
            if stageTime > 10 { stage = .heating; stageTime = 0; progress = 0 }
        }
        consoleTime += real
        if consoleTime > 25 { playing.toggle(); consoleTime = 0 }
    }

    mutating func handle(_ domain: String, _ service: String, _ target: String) {
        switch (domain, service) {
        case ("media_player", "turn_on"), ("media_player", "media_play"): playing = true; consoleTime = 0
        case ("media_player", "turn_off"): playing = false; consoleTime = 0
        default: break
        }
    }

    var entities: [Entity] {
        func e(_ id: String, _ state: String, _ attrs: JSON = [:]) -> Entity { Entity(id: id, state: state, attributes: attrs) }
        let printing = stage != .finished
        let status = stage == .finished ? (progress >= 100 ? "finish" : "idle") : stage == .printing ? "running" : "prepare"
        let remaining = printing ? (100 - progress) / 100 * Self.printMinutes : 0
        return [
            e("sensor.workshop_p1s_print_progress", String(format: "%.0f", progress), ["unit_of_measurement": "%"]),
            e("sensor.workshop_p1s_print_status", status),
            e("sensor.workshop_p1s_current_stage", stage.rawValue),
            e("sensor.workshop_p1s_remaining_time", String(format: "%.0f", remaining), ["unit_of_measurement": "min", "device_class": "duration"]),
            e("sensor.workshop_p1s_nozzle_temperature", String(format: "%.0f", nozzle), ["unit_of_measurement": "°C", "device_class": "temperature"]),
            e("sensor.workshop_p1s_bed_temperature", String(format: "%.0f", bed), ["unit_of_measurement": "°C", "device_class": "temperature"]),
            e("media_player.playstation_5", playing ? "playing" : "off",
              playing ? ["media_title": "Astro Bot", "friendly_name": "PlayStation 5"] : ["friendly_name": "PlayStation 5"]),
            e("binary_sensor.studio_mac_mini_active", "on", ["friendly_name": "Studio Mac mini Active"]),
            e("sensor.studio_mac_mini_frontmost_app", "Xcode", ["friendly_name": "Studio Mac mini Frontmost App"]),
            e("sensor.studio_mac_mini_storage", "61", ["unit_of_measurement": "%", "friendly_name": "Studio Mac mini Storage"]),
        ]
    }
}
