import SwiftUI

// MARK: What a vehicle is doing

/// Charge, range, charging and whereabouts, read from whatever a car, charger, robot vacuum or
/// mower integration offers. Integrations name things differently, so each reading is found by
/// device class first and by the usual names second.
struct VehicleStatus {
    enum Charge: Equatable {
        case charging, plugged, done, unplugged

        var text: String {
            switch self {
            case .charging: "Charging"
            case .plugged: "Plugged in"
            case .done: "Charged"
            case .unplugged: "Not plugged in"
            }
        }
    }

    let battery: Double?
    let range: String?
    let charge: Charge?
    let chargeRate: String?
    let timeToFull: String?
    let chargeLimit: Double?
    let sessionEnergy: String?
    let location: String?
    let lock: Entity?
    let chargeSwitch: Entity?
    let climate: Entity?
    let vacuum: Entity?
    let mower: Entity?

    /// `kind` is passed when it's already known, and must be while the kind itself is being
    /// worked out (`looksLikeCar`), so the two don't ask each other forever.
    init(_ device: HomeDevice, kind: DeviceKind? = nil) {
        let kind = kind ?? device.kind
        let live = device.entities.filter { !$0.isUnavailable }
        func key(_ e: Entity) -> String { EntityCatalog.key(e, deviceName: device.name) }
        func cls(_ e: Entity) -> String? { e.str("device_class") }
        func find(_ domains: Set<String>, _ match: (Entity, String) -> Bool) -> Entity? {
            live.first { domains.contains($0.domain) && match($0, key($0)) }
        }

        vacuum = live.first { $0.domain == "vacuum" }
        mower = live.first { $0.domain == "lawn_mower" }

        // Charge level: a battery sensor, or the robot's own attribute.
        let batterySensor = find(["sensor"]) { e, k in
            (cls(e) == "battery" || ["battery", "battery_level", "state_of_charge", "soc", "charge_level", "battery_percentage"].contains(k)
                || k.hasSuffix("_battery_level") || k.hasSuffix("state_of_charge"))
                && e.str("unit_of_measurement") == "%"
        }
        battery = batterySensor.flatMap { Double($0.state) } ?? vacuum?.num("battery_level")

        range = find(["sensor"]) { e, k in
            k.contains("range") && ["km", "mi", "m"].contains(e.str("unit_of_measurement") ?? "")
        }.flatMap { e in
            Double(e.state).map { "\(Int($0.rounded())) \(e.str("unit_of_measurement") ?? "km")" }
        }

        chargeLimit = find(["number", "sensor"]) { _, k in k.contains("charge_limit") || k.hasSuffix("charge_target") || k == "target_soc" }
            .flatMap { Double($0.state) }

        // Charging: a text state, a charging flag, then whether a cable is in.
        let stateSensor = find(["sensor"]) { e, k in
            ["charging", "charging_state", "charge_state", "charging_status", "charger_status", "status", "charge_mode_status",
             "status_description"].contains(k)
                && Double(e.state) == nil
        }
        let chargingFlag = find(["binary_sensor"]) { e, k in cls(e) == "battery_charging" || k == "charging" || k.hasSuffix("_charging") }
        let pluggedFlag = find(["binary_sensor"]) { e, k in
            cls(e) == "plug" || ["plugged_in", "charge_cable", "charger_connected", "charge_port_connected", "charging_cable", "plug",
                                 "cable_connected", "ev_connected", "car_connected"].contains(k)
        }
        var charge: Charge?
        if let text = stateSensor?.state.lowercased() {
            charge = Self.charge(from: text)
        }
        if charge == nil, chargingFlag?.state == "on" { charge = .charging }
        if charge == nil, let plugged = pluggedFlag {
            charge = plugged.state == "on" ? .plugged : .unplugged
        }
        if charge == .plugged, let b = battery, let limit = chargeLimit, b >= limit - 1 { charge = .done }
        self.charge = charge

        // Power first: Tesla's "charge rate" is range gained per hour (km/h), not kW.
        chargeRate = (find(["sensor"]) { e, k in cls(e) == "power" && (k.contains("charg") || kind == .evCharger) }
            ?? find(["sensor"]) { e, k in
                ["charge_rate", "charging_power", "charger_power", "charge_power", "charging_rate"].contains(k)
                    && cls(e) != "speed"
            })
            .flatMap(Self.power)

        timeToFull = find(["sensor"]) { _, k in
            ["time_to_full_charge", "time_to_full", "charging_remaining_time", "remaining_charge_time", "charge_time_remaining",
             "time_to_complete", "charging_time_remaining", "time_to_charge"].contains(k)
        }.flatMap(Self.timeLeft)

        sessionEnergy = find(["sensor"]) { e, k in
            (k.contains("energy_added") || k.contains("session_energy") || k == "added_energy" || k == "charge_energy")
                && cls(e) == "energy"
        }.flatMap { e in Double(e.state).map { "\(String(format: "%.1f", $0)) \(e.str("unit_of_measurement") ?? "kWh")" } }

        location = live.first { $0.domain == "device_tracker" }.map { t in
            switch t.state {
            case "home": "Home"
            case "not_home": "Away"
            default: t.state.pretty
            }
        }

        lock = live.first { $0.domain == "lock" && !key($0).contains("charge") } ?? live.first { $0.domain == "lock" }
        chargeSwitch = find(["switch"]) { _, k in
            (k == "charge" || k.contains("charging") || k.hasSuffix("_charge") || k == "charger")
                && !["port", "limit", "cable", "schedul", "lock"].contains { k.contains($0) }
        }
        // The cabin climate, not Tesla's cabin overheat protection (which sorts first).
        let climates = live.filter { $0.domain == "climate" }
        climate = climates.first { key($0) == "climate" }
            ?? climates.first { !key($0).contains("overheat") } ?? climates.first
    }

    /// Words integrations use for charging, mapped onto four states.
    static func charge(from text: String) -> Charge? {
        let t = text.replacingOccurrences(of: "_", with: " ")
        // A charger that says just "ready" (Wallbox, Tesla Wall Connector) has no car plugged in.
        if t == "ready" || t == "available" { return .unplugged }
        if ["complete", "finished", "full", "done", "charged"].contains(where: t.contains) { return .done }
        if ["disconnect", "unplug", "not connected", "no power", "no car"].contains(where: t.contains) { return .unplugged }
        if t == "charging" || t.hasPrefix("charging") || t == "starting" { return .charging }
        if ["connected", "plugged", "ready", "waiting", "awaiting", "stopped", "paused", "scheduled"].contains(where: t.contains) {
            return .plugged
        }
        return nil
    }

    static func power(_ e: Entity) -> String? {
        guard let v = Double(e.state), v > 0 else { return nil }
        let unit = e.str("unit_of_measurement") ?? "kW"
        if unit == "W" { return v >= 1000 ? "\(String(format: "%.1f", v / 1000)) kW" : "\(Int(v)) W" }
        return "\(String(format: v < 10 ? "%.1f" : "%.0f", v)) \(unit)"
    }

    /// Minutes until full, from a duration or a finish time.
    static func timeLeft(_ e: Entity) -> String? {
        var minutes: Double?
        if e.str("device_class") == "timestamp" {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: e.state) ?? ISO8601DateFormatter().date(from: e.state) {
                minutes = date.timeIntervalSinceNow / 60
            }
        } else if let v = Double(e.state) {
            switch e.str("unit_of_measurement") ?? "min" {
            case "h": minutes = v * 60
            case "s": minutes = v / 60
            default: minutes = v
            }
        }
        guard let m = minutes, m >= 1 else { return nil }
        let total = Int(m.rounded())
        let h = total / 60, min = total % 60
        return h > 0 ? (min > 0 ? "\(h) h \(min) min to full" : "\(h) h to full") : "\(min) min to full"
    }

    var isCharging: Bool { charge == .charging }

    var percent: String? { battery.map { "\(Int($0.rounded()))%" } }

    /// What a robot vacuum or mower is doing, in plain words.
    var roverState: String? {
        guard let e = vacuum ?? mower else { return nil }
        switch e.state {
        case "cleaning": return "Cleaning"
        case "mowing": return "Mowing"
        case "docked": return battery.map { $0 < 99 ? "Docked, charging" : "Docked" } ?? "Docked"
        case "returning": return "Heading home"
        case "paused": return "Paused"
        case "idle": return "Idle"
        case "error": return e.str("status").map { "Needs help: \($0)" } ?? "Needs help"
        default: return e.state.pretty
        }
    }

    var roverBusy: Bool { ["cleaning", "mowing", "returning"].contains((vacuum ?? mower)?.state ?? "") }

    func summary(_ kind: DeviceKind) -> String {
        switch kind {
        case .robotVacuum, .lawnMower:
            return [roverState, percent].compactMap { $0 }.joined(separator: " · ").nonEmpty ?? "Ready"
        case .evCharger:
            return [charge?.text ?? "Ready", chargeRate].compactMap { $0 }.joined(separator: " · ")
        default:
            let first = isCharging ? "Charging" : location
            return [first, percent].compactMap { $0 }.joined(separator: " · ").nonEmpty ?? charge?.text ?? "Ready"
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

extension HomeDevice {
    /// The light each vehicle kind glows with.
    static func vehicleAccent(_ kind: DeviceKind) -> Color {
        switch kind {
        case .electricCar, .evCharger: Color.accent(0.42, 0.92, 0.7)
        case .robotVacuum: Color.accent(0.5, 0.8, 1.0)
        case .lawnMower: Color.accent(0.62, 0.9, 0.42)
        case .aircraft: Color.accent(0.62, 0.74, 1.0)
        default: Color.accent(0.72, 0.66, 1.0)
        }
    }

    /// A car that no maker rule caught, but that has a charge level, a range or charge limit,
    /// and a location or a lock.
    var looksLikeCar: Bool {
        let s = VehicleStatus(self, kind: .generic)
        return s.battery != nil && (s.range != nil || s.chargeLimit != nil) && (s.location != nil || s.lock != nil)
    }
}

// MARK: Page

/// Electric cars, chargers, robot vacuums, mowers, aircraft and robots: the ones Home
/// Assistant knows, then the ones listed by hand.
struct VehiclesPage: View {
    @EnvironmentObject var store: HomeStore
    @ObservedObject private var list = GadgetStore.shared
    let shown: Bool
    let visible: Bool
    @Binding var openDevice: String?
    @State private var editing: UUID?
    @State private var adding = false
    /// In a demo, only the sample devices show: nothing from your own list, and nothing to add.
    @Environment(\.sectionChrome) private var chrome
    private var demo: Bool { chrome?.demoOn == true }

    private var fromHome: [HomeDevice] {
        var found = store.devices.values
            .filter { !$0.isService }
            .compactMap { store.homeDevice($0.id) }
            .filter { DeviceKind.vehicles.contains($0.kind) && !$0.entities.isEmpty }
        // Robots Home Assistant knows but hasn't put on a device, like the demo's vacuums.
        let claimed = Set(found.flatMap { $0.entities.map(\.id) })
        for e in store.entities.values where ["vacuum", "lawn_mower"].contains(e.domain) && !claimed.contains(e.id)
            && store.registry[e.id]?.deviceID == nil {
            found.append(HomeDevice(info: DeviceInfo(id: e.id, name: e.name), entities: [e]))
        }
        found += Self.preview
        let order = DeviceKind.vehicles
        return found.sorted {
            let a = order.firstIndex(of: $0.kind) ?? 0, b = order.firstIndex(of: $1.kind) ?? 0
            return a != b ? a < b : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        ScreenFlow(route: openDevice, depth: openDevice == nil ? 0 : 1) { deviceID in
            if let id = deviceID {
                DeviceDetail(deviceID: id) { openDevice = nil }.id(id)
            } else {
                overview
            }
        }
        .task(id: visible) {
            guard visible else { return }
            while !Task.isCancelled {
                await list.checkAll(Gadget.Kind.vehicleKinds)
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private var overview: some View {
        let home = fromHome
        let cars = home.filter { $0.kind == .electricCar }
        let chargers = home.filter { $0.kind == .evCharger }
        let rovers = home.filter { [.robotVacuum, .lawnMower].contains($0.kind) }
        let others = home.filter { [.aircraft, .robot].contains($0.kind) }
        let manual = demo ? [] : list.gadgets.filter { Gadget.Kind.vehicleKinds.contains($0.kind) }
        let charging = home.filter { VehicleStatus($0).isCharging }.count
        let total = home.count + manual.count
        return VStack(alignment: .leading, spacing: 14) {
            PageHeader(eyebrow: total == 0 ? "Cars, robots, aircraft"
                       : "\(total) vehicle\(total == 1 ? "" : "s")\(charging > 0 ? " · \(charging) charging" : "")",
                       title: "Vehicles") {
                if !demo {
                    Button {
                        withAnimation(.glide) {
                            editing = nil
                            adding.toggle()
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .light))
                            .rotationEffect(.degrees(adding ? 45 : 0))
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Theme.fg.opacity(0.05)).overlay(Circle().strokeBorder(Theme.hairline)))
                    }
                    .buttonStyle(PressStyle())
                    .help(adding ? "Cancel" : "Add a vehicle by hand")
                    .accessibilityLabel(adding ? "Cancel" : "Add a vehicle by hand")
                }
            }
            .reveal(shown, 0)

            if adding {
                GadgetEditor(gadget: nil, kinds: Gadget.Kind.vehicleKinds, noun: "vehicle") { g in
                    list.save(g)
                    withAnimation(.glide) { adding = false }
                } onCancel: {
                    withAnimation(.glide) { adding = false }
                }
                .transition(.dissolve)
            }

            section(cars.count == 1 ? "CAR" : "CARS", cars, order: 1) { CarCard(device: $0) { open($0) } }
            section(chargers.count == 1 ? "CHARGER" : "CHARGERS", chargers, order: 2) { ChargerCard(device: $0) { open($0) } }
            section("ROBOTS", rovers, order: 3) { RoverCard(device: $0) { open($0) } }
            section("MORE", others, order: 4) { d in DeviceCard(device: d) { open(d.id) } }

            if !manual.isEmpty {
                Text("ADDED BY HAND").eyebrow().padding(.leading, 4).reveal(shown, 5)
                VStack(spacing: 8) {
                    ForEach(manual) { g in
                        if editing == g.id {
                            GadgetEditor(gadget: g, kinds: Gadget.Kind.vehicleKinds, noun: "vehicle") { changed in
                                list.save(changed)
                                withAnimation(.glide) { editing = nil }
                            } onCancel: {
                                withAnimation(.glide) { editing = nil }
                            } onDelete: {
                                withAnimation(.glide) {
                                    list.remove(g.id)
                                    editing = nil
                                }
                            }
                            .transition(.dissolve)
                        } else {
                            ManualGadgetRow(gadget: g, reach: list.reach[g.id] ?? .unknown) {
                                withAnimation(.glide) {
                                    adding = false
                                    editing = g.id
                                }
                            }
                            .transition(.dissolve)
                        }
                    }
                }
                .reveal(shown, 6)
            }

            if home.isEmpty {
                ConnectGuide(steps: Self.howTo,
                             note: "Electric aircraft, drones and anything else without a Home Assistant integration yet, you can list by hand.",
                             showsAdd: manual.isEmpty && !adding) {
                    withAnimation(.glide) { adding = true }
                }
                .reveal(shown, 7)
            }
        }
        .animation(.glide, value: adding)
        .animation(.glide, value: editing)
        .animation(.glide, value: manual)
    }

    @ViewBuilder
    private func section<Card: View>(_ title: String, _ devices: [HomeDevice], order: Int,
                                     @ViewBuilder card: @escaping (HomeDevice) -> Card) -> some View {
        if !devices.isEmpty {
            Text(title).eyebrow().padding(.leading, 4).reveal(shown, order)
            VStack(spacing: 10) {
                ForEach(devices) { card($0) }
            }
            .reveal(shown, order)
        }
    }

    /// Devices without a real registry entry (robots with no device) have nothing to open.
    private func open(_ id: String) {
        guard store.devices[id] != nil else { return }
        withAnimation(.glide) { openDevice = id }
    }

    static let howTo: [ConnectGuide.Step] = [
        .init(kind: .electricCar, title: "Tesla",
              detail: "Add Tesla Fleet, built into Home Assistant, or Teslemetry or Tessie. Charge, range, location, locks and climate show up here."),
        .init(kind: .electricCar, title: "Other electric cars",
              detail: "BMW, Renault and Nissan are built in. Kia and Hyundai, Volkswagen, Polestar, Rivian and Mercedes come from HACS. BYD has community integrations only, so a charger integration is the surest way to see it charge."),
        .init(kind: .evCharger, title: "Chargers",
              detail: "Wallbox, Easee, Zaptec, ChargePoint and the Tesla Wall Connector show charging for whichever car is plugged in."),
        .init(kind: .robotVacuum, title: "Robot vacuums",
              detail: "Roborock, Ecovacs and iRobot Roomba are built in. Dreame comes from HACS. Start, pause and send them home from here."),
        .init(kind: .lawnMower, title: "Robot mowers",
              detail: "Husqvarna Automower is built into Home Assistant."),
        .init(kind: .aircraft, title: "Aircraft and drones",
              detail: "Home Assistant has no integration for electric aircraft or drones yet. Add one by hand to keep it on your list."),
    ]

    // MARK: Preview

    /// `-vehiclePreview YES` adds a made-up car, charger and mower, so the cards can be checked
    /// without owning them. Development only.
    static var preview: [HomeDevice] {
        guard UserDefaults.standard.bool(forKey: "vehiclePreview") else { return [] }
        func e(_ id: String, _ state: String, _ attrs: JSON = [:]) -> Entity { Entity(id: id, state: state, attributes: attrs) }
        let soon = ISO8601DateFormatter().string(from: Date().addingTimeInterval(84 * 60))
        let car = HomeDevice(info: DeviceInfo(id: "preview-car", name: "Model Y", manufacturer: "Tesla", model: "Model Y"), entities: [
            e("sensor.model_y_battery_level", "78", ["device_class": "battery", "unit_of_measurement": "%"]),
            e("sensor.model_y_battery_range", "312", ["device_class": "distance", "unit_of_measurement": "km"]),
            e("sensor.model_y_charging", "charging", ["device_class": "enum"]),
            e("sensor.model_y_charger_power", "7.2", ["device_class": "power", "unit_of_measurement": "kW"]),
            e("sensor.model_y_time_to_full_charge", soon, ["device_class": "timestamp"]),
            e("number.model_y_charge_limit", "90", ["unit_of_measurement": "%"]),
            e("device_tracker.model_y_location", "home"),
            e("lock.model_y_lock", "locked"),
            e("switch.model_y_charge", "on"),
            e("climate.model_y_climate", "off"),
        ])
        let byd = HomeDevice(info: DeviceInfo(id: "preview-byd", name: "Atto 3", manufacturer: "BYD", model: "Atto 3"), entities: [
            e("sensor.atto_3_battery", "16", ["device_class": "battery", "unit_of_measurement": "%"]),
            e("sensor.atto_3_range", "64", ["device_class": "distance", "unit_of_measurement": "km"]),
            e("binary_sensor.atto_3_plugged_in", "off", ["device_class": "plug"]),
            e("device_tracker.atto_3", "Office"),
            e("lock.atto_3_doors", "unlocked"),
        ])
        let charger = HomeDevice(info: DeviceInfo(id: "preview-charger", name: "Driveway charger", manufacturer: "Wallbox", model: "Pulsar Plus"),
                                 entities: [
                                     e("sensor.driveway_charger_status", "Charging"),
                                     e("sensor.driveway_charger_charging_power", "7.2", ["device_class": "power", "unit_of_measurement": "kW"]),
                                     e("sensor.driveway_charger_added_energy", "18.4", ["device_class": "energy", "unit_of_measurement": "kWh"]),
                                 ])
        let mower = HomeDevice(info: DeviceInfo(id: "preview-mower", name: "Garden mower", manufacturer: "Husqvarna", model: "Automower 430X"),
                               entities: [
                                   e("lawn_mower.garden_mower", "mowing"),
                                   e("sensor.garden_mower_battery", "64", ["device_class": "battery", "unit_of_measurement": "%"]),
                               ])
        let jet = HomeDevice(info: DeviceInfo(id: "preview-jet", name: "Electric jet", manufacturer: "Example", model: "eVTOL"),
                             entities: [e("sensor.electric_jet_battery", "92", ["device_class": "battery", "unit_of_measurement": "%"])])
        return [car, byd, charger, mower, jet]
    }
}

// MARK: Car

struct CarCard: View {
    @EnvironmentObject var store: HomeStore
    let device: HomeDevice
    let open: (String) -> Void
    @State private var confirmUnlock = false

    var body: some View {
        let s = VehicleStatus(device)
        let tint = HomeDevice.vehicleAccent(.electricCar)
        let level = s.battery ?? 0
        let barTint = s.isCharging ? tint : level < 20 ? Theme.live : Theme.fg.opacity(0.88)
        Bezel(radius: 24, inset: 4, lit: device.online && s.isCharging, tint: tint) {
            VStack(alignment: .leading, spacing: 14) {
                Button { open(device.id) } label: {
                    HStack(spacing: 12) {
                        HomeCarArt(device: device, size: 76)
                            .frame(width: 76, height: 52)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(device.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                            HStack(spacing: 5) {
                                PulseDot(color: !device.online ? Theme.live : s.isCharging ? tint : Theme.muted, size: 5,
                                         live: device.online && s.isCharging)
                                Text(device.online ? (s.charge?.text ?? s.location ?? "Parked") : "Offline")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(device.online ? Theme.ink : Theme.live)
                            }
                            Text([device.info.manufacturer, device.info.model].compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.faint).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.faint)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("\(device.name), \(s.summary(.electricCar)). Open details")

                CarPaintPicker(device: device)

                if let battery = s.battery {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text("\(Int(battery.rounded()))").font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                            Text("%").font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(Theme.muted)
                            Spacer()
                            if let range = s.range {
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(range).font(.system(size: 15, weight: .semibold)).monospacedDigit()
                                    Text("range").font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Battery \(Int(battery.rounded())) percent\(s.range.map { ", \($0) range" } ?? "")")
                        BatteryBar(value: battery / 100, limit: s.chargeLimit.map { $0 / 100 }, tint: barTint, charging: s.isCharging)
                        let details = [s.isCharging ? s.chargeRate : nil, s.isCharging ? s.timeToFull : nil,
                                       s.chargeLimit.map { "limit \(Int($0))%" }].compactMap { $0 }
                        if !details.isEmpty {
                            Text(details.joined(separator: " · ")).font(.system(size: 12)).foregroundStyle(Theme.muted)
                        }
                    }
                }

                if s.location != nil || s.lock != nil {
                    HStack(spacing: 8) {
                        if let place = s.location { chip("location.fill", "Location", place) }
                        if let lock = s.lock { chip(lock.state == "locked" ? "lock.fill" : "lock.open", "Doors", lock.state.pretty) }
                    }
                }

                let actions = actionList(s)
                if !actions.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(actions, id: \.title) { a in
                            ActionPill(symbol: a.symbol, title: a.title, tint: a.tint, filled: a.filled, action: a.run)
                        }
                    }
                }
            }
            .padding(14)
        }
        .animation(.glide, value: confirmUnlock)
    }

    private struct Action {
        let symbol: String
        let title: String
        var tint: Color = Theme.ink
        var filled = false
        let run: () -> Void
    }

    private func actionList(_ s: VehicleStatus) -> [Action] {
        var list: [Action] = []
        if let lock = s.lock {
            if lock.state == "locked" {
                list.append(Action(symbol: confirmUnlock ? "exclamationmark.lock" : "lock.open",
                                   title: confirmUnlock ? "Confirm unlock" : "Unlock",
                                   tint: confirmUnlock ? Theme.live : Theme.ink, filled: confirmUnlock) {
                    if confirmUnlock {
                        confirmUnlock = false
                        store.optimistic(lock.id) { $0.state = "unlocking" }
                        store.call("lock", "unlock", lock.id)
                    } else {
                        confirmUnlock = true
                        Task {
                            try? await Task.sleep(for: .seconds(4))
                            confirmUnlock = false
                        }
                    }
                })
            } else {
                list.append(Action(symbol: "lock", title: "Lock") {
                    store.optimistic(lock.id) { $0.state = "locking" }
                    store.call("lock", "lock", lock.id)
                })
            }
        }
        if let sw = s.chargeSwitch, s.charge != .unplugged {
            let on = sw.state == "on"
            list.append(Action(symbol: on ? "bolt.slash" : "bolt.fill", title: on ? "Stop charging" : "Charge",
                               tint: on ? Theme.ink : HomeDevice.vehicleAccent(.electricCar)) {
                store.optimistic(sw.id) { $0.state = on ? "off" : "on" }
                store.call("switch", on ? "turn_off" : "turn_on", sw.id)
            })
        }
        if let climate = s.climate {
            let on = climate.state != "off"
            list.append(Action(symbol: "fan", title: on ? "Climate off" : "Climate on") {
                store.optimistic(climate.id) { $0.state = on ? "off" : "heat_cool" }
                store.call("climate", on ? "turn_off" : "turn_on", climate.id)
            })
        }
        return list
    }

    private func chip(_ symbol: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11.5, weight: .light)).foregroundStyle(Theme.muted)
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.muted)
            Spacer(minLength: 4)
            Text(value).font(.system(size: 13, weight: .semibold)).lineLimit(1)
        }
        .padding(.horizontal, 11)
        .frame(height: 32)
        .frame(maxWidth: .infinity)
        .background(Capsule().fill(Theme.fg.opacity(0.05)).overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.75)))
        .accessibilityElement(children: .combine)
    }
}

/// A charge bar with a tick at the charge limit, and light running along it while charging.
struct BatteryBar: View {
    let value: Double
    var limit: Double?
    let tint: Color
    var charging = false
    var height: CGFloat = 10
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.fg.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.65), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, w * min(max(value, 0), 1)))
                    .glow(color: tint.opacity(charging ? 0.6 : 0.25), radius: charging ? 7 : 3)
                    .overlay(alignment: .leading) {
                        if charging && !reduceMotion {
                            TimelineView(.animation(minimumInterval: 1 / 30)) { t in
                                let phase = t.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.2) / 2.2
                                let fill = max(height, w * value)
                                LinearGradient(colors: [.clear, Color.white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                                    .frame(width: 46)
                                    .offset(x: -46 + (fill + 46) * phase)
                                    .frame(width: fill, alignment: .leading)
                                    .clipShape(Capsule())
                                    .blendMode(.plusLighter)
                            }
                        }
                    }
                if let limit, limit > 0, limit < 1 {
                    Capsule().fill(Theme.fg.opacity(0.7)).frame(width: 2, height: height + 6)
                        .offset(x: w * limit - 1)
                }
            }
        }
        .frame(height: height)
        .animation(.glide, value: value)
        .accessibilityHidden(true)
    }
}

/// A pill-shaped action button, filled when it needs attention.
struct ActionPill: View {
    let symbol: String
    let title: String
    var tint: Color = Theme.ink
    var filled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                Text(title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85)
            }
            .foregroundStyle(filled ? Theme.onAccent : tint)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(filled ? AnyShapeStyle(tint) : AnyShapeStyle(Theme.fg.opacity(0.07))))
            .overlay(Capsule().strokeBorder(filled ? .clear : Theme.hairline, lineWidth: 0.75))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(title)
    }
}

// MARK: Robot vacuum and mower

struct RoverCard: View {
    @EnvironmentObject var store: HomeStore
    let device: HomeDevice
    let open: (String) -> Void

    var body: some View {
        let s = VehicleStatus(device)
        let tint = HomeDevice.vehicleAccent(device.kind)
        let busy = s.roverBusy
        Bezel(radius: 24, inset: 4, lit: device.online && busy, tint: tint) {
            VStack(alignment: .leading, spacing: 12) {
                Button { open(device.id) } label: {
                    HStack(spacing: 12) {
                        DeviceArtView(kind: device.kind, active: device.online, accent: tint, size: 56)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(device.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                            HStack(spacing: 5) {
                                PulseDot(color: device.online ? (busy ? tint : Theme.ok) : Theme.live, size: 5, live: device.online && busy)
                                Text(device.online ? (s.roverState ?? "Ready") : "Offline")
                                    .font(.system(size: 13, weight: .medium)).lineLimit(1)
                                    .foregroundStyle(device.online ? Theme.ink : Theme.live)
                            }
                            if let p = s.percent {
                                Text("Battery \(p)").font(.system(size: 12)).foregroundStyle(Theme.muted)
                            }
                        }
                        Spacer(minLength: 0)
                        if store.devices[device.id] != nil {
                            Image(systemName: "chevron.right").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.faint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())

                if let b = s.battery {
                    BatteryBar(value: b / 100, tint: b < 20 ? Theme.live : tint, charging: (s.vacuum ?? s.mower)?.state == "docked" && b < 99,
                               height: 6)
                }

                if let robot = s.vacuum ?? s.mower, device.online {
                    let mower = robot.domain == "lawn_mower"
                    HStack(spacing: 8) {
                        if busy {
                            ActionPill(symbol: "pause.fill", title: "Pause") { run(robot, "pause", busy: false) }
                        } else {
                            ActionPill(symbol: "play.fill", title: mower ? "Mow" : "Clean", tint: tint) {
                                run(robot, mower ? "start_mowing" : "start", busy: true)
                            }
                        }
                        if robot.state != "docked" {
                            ActionPill(symbol: "house.fill", title: "Dock") { run(robot, mower ? "dock" : "return_to_base", busy: true) }
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    private func run(_ robot: Entity, _ service: String, busy: Bool) {
        let next: String = switch service {
        case "pause": "paused"
        case "dock", "return_to_base": "returning"
        default: robot.domain == "lawn_mower" ? "mowing" : "cleaning"
        }
        store.optimistic(robot.id) { $0.state = next }
        store.call(robot.domain, service, robot.id)
    }
}

// MARK: Charger

struct ChargerCard: View {
    let device: HomeDevice
    let open: (String) -> Void

    var body: some View {
        let s = VehicleStatus(device)
        let tint = HomeDevice.vehicleAccent(.evCharger)
        Button { open(device.id) } label: {
            Bezel(radius: 22, inset: 3, lit: device.online && s.isCharging, tint: tint) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        DeviceArtView(kind: .evCharger, active: device.online && s.charge != .unplugged, accent: tint, size: 52)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(device.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                            HStack(spacing: 5) {
                                PulseDot(color: device.online ? (s.isCharging ? tint : Theme.ok) : Theme.live, size: 5,
                                         live: device.online && s.isCharging)
                                Text(device.online ? (s.charge.map { $0 == .unplugged ? "No car" : $0.text } ?? "Ready") : "Offline")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(device.online ? Theme.ink : Theme.live)
                            }
                            Text([device.info.manufacturer, device.info.model].compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.faint).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.faint)
                    }
                    if s.chargeRate != nil || s.sessionEnergy != nil {
                        HStack(spacing: 8) {
                            if let p = s.chargeRate { reading("bolt.fill", "Power", p) }
                            if let e = s.sessionEnergy { reading("gauge.with.dots.needle.33percent", "This session", e) }
                        }
                    }
                }
                .padding(12)
            }
        }
        .buttonStyle(PressStyle())
    }

    private func reading(_ symbol: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11.5, weight: .light)).foregroundStyle(Theme.muted)
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
            Spacer(minLength: 4)
            Text(value).font(.system(size: 13, weight: .semibold)).monospacedDigit()
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .frame(maxWidth: .infinity)
        .background(Capsule().fill(Theme.fg.opacity(0.05)).overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.75)))
    }
}
