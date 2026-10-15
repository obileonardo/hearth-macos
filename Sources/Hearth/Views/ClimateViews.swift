import SwiftUI

/// Reads a Home Assistant climate entity in the terms the panel needs.
struct Climate {
    let e: Entity

    var on: Bool { e.state != "off" && !e.isUnavailable }
    var mode: String { e.state }
    var room: Double? { e.num("current_temperature").flatMap { $0.isFinite ? $0 : nil } }
    var target: Double? { e.num("temperature").flatMap { $0.isFinite ? $0 : nil } }
    var temperatureRange: ClosedRange<Double>? { ClimateTemperatureScale.range(e) }
    var minTemp: Double { temperatureRange?.lowerBound ?? 16 }
    var maxTemp: Double { temperatureRange?.upperBound ?? 30 }
    var step: Double { ClimateTemperatureScale.step(e) }
    var modes: [String] {
        let order = ["cool", "heat", "heat_cool", "auto", "dry", "fan_only"]
        return e.list("hvac_modes").filter { $0 != "off" }.sorted {
            (order.firstIndex(of: $0) ?? 99) < (order.firstIndex(of: $1) ?? 99)
        }
    }
    var fanModes: [String] {
        e.list("fan_modes").sorted { Self.fanRank($0) < Self.fanRank($1) }
    }

    /// Where a fan speed sits from slowest to fastest, with auto first.
    static func fanRank(_ fan: String) -> Double {
        let f = fan.lowercased().replacingOccurrences(of: "-", with: "_")
        if f.contains("auto") { return 0 }
        if ["quiet", "silent", "slow"].contains(f) { return 0.5 }
        if f.hasPrefix("low") { return f.contains("mid") || f.contains("medium") ? 1.5 : 1 }
        if f.hasPrefix("mid") || f.hasPrefix("medium") { return f.contains("high") ? 2.5 : 2 }
        if f.hasPrefix("high") { return 3 }
        if ["turbo", "max", "power", "powerful", "strong"].contains(f) { return 4 }
        return 2
    }

    /// Short labels that fit six to a row: "low_mid" becomes "Low+", "mid_high" becomes "Med+".
    /// Names it doesn't know are shown as Home Assistant gives them.
    static func fanLabel(_ fan: String) -> String {
        let known = [
            "auto": "Auto", "quiet": "Quiet", "silent": "Quiet", "low": "Low", "low_mid": "Low+",
            "low_medium": "Low+", "mid": "Med", "medium": "Med", "mid_high": "Med+", "medium_high": "Med+",
            "high": "High", "turbo": "Max", "max": "Max", "power": "Max", "powerful": "Max",
        ]
        return known[fan.lowercased().replacingOccurrences(of: "-", with: "_")] ?? fan.pretty
    }

    var swingModes: [String] { e.list("swing_modes") }
    var presets: [String] { e.list("preset_modes") }
    var fan: String? { e.str("fan_mode") }
    var swingMode: String? { e.str("swing_mode") }
    var preset: String? { e.str("preset_mode") }
    var swinging: Bool { swingMode.map { !["off", "stop", "fixed"].contains($0.lowercased()) } ?? false }
    var ecoPreset: String? { presets.first { ["eco", "energy_saving", "power_save"].contains($0.lowercased()) } }
    var eco: Bool { preset != nil && preset == ecoPreset }
    var canTurnOn: Bool { ((e.num("supported_features").flatMap(Int.init(exactly:)) ?? 0) & 128) != 0 }

    var intensity: Double {
        let f = (fan ?? "").lowercased()
        if ["high", "strong", "turbo", "max", "powerful"].contains(where: f.contains) { return 1 }
        if ["mid", "medium"].contains(where: f.contains) { return 0.62 }
        if ["low", "quiet", "silent", "slow"].contains(where: f.contains) { return 0.3 }
        return 0.55
    }

    var action: String {
        guard on else { return e.isUnavailable ? "Offline" : "Off" }
        switch e.str("hvac_action") ?? mode {
        case "cooling", "cool": return "Cooling"
        case "heating", "heat": return "Heating"
        case "drying", "dry": return "Drying"
        case "fan", "fan_only": return "Fan only"
        case "idle": return "Holding"
        default: return Theme.modeName(mode)
        }
    }

    /// A short name for the header: "Workspace Air Conditioner" becomes "Workspace".
    static func shortName(_ name: String) -> String {
        var n = name
        for suffix in [" Air Conditioner", " Air Conditioning", " Aircon", " AC", " A/C"] where n.hasSuffix(suffix) {
            n = String(n.dropLast(suffix.count))
        }
        return n.isEmpty ? name : n
    }
}

extension HomeStore {
    func togglePower(_ c: Climate) {
        let id = c.e.id
        if c.on {
            optimistic(id) { $0.state = "off" }
            call("climate", "turn_off", id)
        } else if c.canTurnOn {
            optimistic(id) { $0.state = c.modes.first(where: { $0 == "cool" }) ?? c.modes.first ?? "cool" }
            call("climate", "turn_on", id)
        } else if let mode = c.modes.first(where: { $0 == "cool" }) ?? c.modes.first {
            optimistic(id) { $0.state = mode }
            call("climate", "set_hvac_mode", id, ["hvac_mode": mode])
        }
    }
}

func degrees(_ v: Double) -> String {
    guard v.isFinite else { return "—" }
    if let whole = Int(exactly: v) { return "\(whole)" }
    return v.formatted(.number.precision(.fractionLength(0...3)))
}

// MARK: Page

struct ClimatePage: View {
    @EnvironmentObject var store: HomeStore
    let entityID: String
    let shown: Bool

    @State private var dragTarget: Double?
    @State private var sendTask: Task<Void, Never>?
    @State private var pendingMode: String?
    @State private var climateFailure: String?
    @State private var climateFailureReport: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let e = store.entities[entityID] {
            page(Climate(e: e))
        }
    }

    private func page(_ c: Climate) -> some View {
        let target = dragTarget ?? c.target
        let air = Theme.air(c.on ? c.mode : "off")
        let maker = store.device(of: entityID)?.manufacturer.map { $0 == "LGE" ? "LG" : $0 }
        let sensors = store.siblings(of: entityID, domain: "sensor")
        let energy = sensors.first { $0.id.hasSuffix("energy_today") }
        let filter = sensors.first { $0.id.contains("filter") }

        return VStack(spacing: 0) {
            // Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text([maker, "Air conditioner"].compactMap { $0 }.joined(separator: " · ").uppercased())
                        .eyebrow()
                    Text(Climate.shortName(c.e.name))
                        .font(.system(size: 22, weight: .semibold))
                        .tracking(-0.4)
                }
                Spacer()
                PowerButton(on: c.on, tint: air) { store.togglePower(c) }
            }
            .reveal(shown, 0)

            // The unit
            ACUnitView(power: c.on ? 1 : 0, mode: c.mode, intensity: c.intensity, swing: c.swinging,
                       width: 246, display: c.on ? target.map(degrees) : nil, reach: 0.46)
                .animation(.glide, value: c.on)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
                .reveal(shown, 1)

            // Temperature and status
            HStack(alignment: .lastTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(target.map(degrees) ?? "—")
                        .font(.system(size: 76, weight: .thin))
                        .tracking(-3)
                        .monospacedDigit()
                        .contentTransition(reduceMotion || target == nil ? .opacity : .numericText(value: target ?? 0))
                        // Own this transaction locally: page transitions clear
                        // inherited animation, while the number should still roll.
                        .animation(reduceMotion ? .easeOut(duration: 0.1) : .snap, value: target)
                    if target != nil {
                        Text("°")
                            .font(.system(size: 40, weight: .ultraLight))
                            .foregroundStyle(Theme.muted)
                            .offset(y: -30)
                    }
                }
                .foregroundStyle(c.on ? Theme.ink : Theme.faint)
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    StatusPill(text: c.action, tint: air, live: c.on)
                    if let room = c.room {
                        Label("Room \(degrees(room))°", systemImage: "thermometer.medium")
                    }
                    if let energy, let used = Self.energyText(energy) {
                        Label("\(used) today", systemImage: "bolt")
                    } else if let filter, let left = Double(filter.state), let whole = Int(exactly: left.rounded(.towardZero)) {
                        Label("Filter \(whole)\(filter.str("unit_of_measurement") ?? "%")", systemImage: "aqi.low")
                    }
                }
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.muted)
                .labelStyle(TrailingIconLabel())
                .padding(.bottom, 10)
            }
            .padding(.top, -6)
            .reveal(shown, 2)

            // Target slider
            if c.target != nil, let range = c.temperatureRange {
                TemperatureControl(value: target ?? range.lowerBound, range: range, step: c.step, tint: air, active: c.on) {
                    setTarget(c, $0)
                }
                .reveal(shown, 3)
            }

            // Mode
            if !c.modes.isEmpty {
                Segmented(options: c.modes, selected: c.on ? c.mode : nil, tint: air, id: "mode") { mode in
                    Image(systemName: Theme.modeSymbol(mode)).font(.system(size: 14, weight: .light))
                    Text(Theme.modeName(mode)).font(.system(size: 12, weight: .medium))
                } onSelect: { mode in
                    setMode(c, mode)
                }
                .padding(.top, 10)
                .reveal(shown, 4)
                if let pendingMode {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.small)
                        Text("Switching to \(Theme.modeName(pendingMode))…")
                            .font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                    }
                    .padding(.top, 8)
                    .accessibilityElement(children: .combine)
                }
            }

            // Fan speed: one bar to drag across.
            if !c.fanModes.isEmpty {
                FanControl(modes: c.fanModes, selected: c.fan, tint: air, running: c.on) { fan in
                    store.optimistic(entityID) { $0.attributes["fan_mode"] = fan }
                    store.call("climate", "set_fan_mode", entityID, ["fan_mode": fan])
                }
                .padding(.top, 8)
                .reveal(shown, 5)
            }

            // Quick settings
            HStack(spacing: 6) {
                if !c.swingModes.isEmpty {
                    QuickChip(symbol: "wind", label: "Swing", on: c.swinging, tint: air) {
                        let next = c.swinging
                            ? (c.swingModes.first { ["off", "stop", "fixed"].contains($0.lowercased()) } ?? "off")
                            : (c.swingModes.first { ["on", "vertical", "both", "auto"].contains($0.lowercased()) } ?? c.swingModes.first ?? "on")
                        store.optimistic(entityID) { $0.attributes["swing_mode"] = next }
                        store.call("climate", "set_swing_mode", entityID, ["swing_mode": next])
                    }
                }
                if let sleep = siblings(c, "number").first(where: { $0.id.hasSuffix("sleep_timer") }) {
                    let hours = Double(sleep.state) ?? 0
                    QuickChip(symbol: "moon.zzz", label: hours > 0 ? "Sleep \(degrees(hours))h" : "Sleep", on: hours > 0, tint: air) {
                        let lo = sleep.num("min") ?? 0, hi = sleep.num("max") ?? 12
                        let options = [0.0, 1, 2, 4, 6, 8].filter { $0 >= lo && $0 <= hi }.map { degrees($0) }
                        PopupMenu.show(options, selected: degrees(hours), label: { $0 == "0" ? "Off" : "Off in \($0) hours" }) { v in
                            store.optimistic(sleep.id) { $0.state = v }
                            store.call("number", "set_value", sleep.id, ["value": Double(v) ?? 0])
                        }
                    }
                }
                if let light = siblings(c, "switch").first(where: { $0.id.hasSuffix("lighting") }) {
                    QuickChip(symbol: "lightbulb", label: "Display", on: light.state == "on", tint: air) {
                        let on = light.state == "on"
                        store.optimistic(light.id) { $0.state = on ? "off" : "on" }
                        store.call("switch", on ? "turn_off" : "turn_on", light.id)
                    }
                }
                if let eco = c.ecoPreset {
                    QuickChip(symbol: "leaf", label: "Eco", on: c.eco, tint: Theme.ok) { setEco(c, eco: eco) }
                }
            }
            .padding(.top, 8)
            .reveal(shown, 6)
        }
        .disabled(c.e.isUnavailable || pendingMode != nil)
        .alert("Couldn’t change the air conditioner", isPresented: Binding(get: { climateFailure != nil }, set: { if !$0 { climateFailure = nil } })) {
            Button("OK") { climateFailure = nil }
            if let climateFailureReport {
                Button("Copy diagnostic details") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(climateFailureReport, forType: .string)
                }
            }
        } message: { Text(climateFailure ?? "") }
        .onDisappear { sendTask?.cancel() }
        .onChange(of: store.authenticationGeneration) { _, _ in
            sendTask?.cancel()
            dragTarget = nil
            pendingMode = nil
            climateFailure = nil
            climateFailureReport = nil
        }
    }

    /// Energy in the unit the sensor reports, stepping Wh up to kWh past a thousand.
    static func energyText(_ sensor: Entity) -> String? {
        guard let value = Double(sensor.state), value.isFinite else { return nil }
        let unit = sensor.str("unit_of_measurement") ?? "kWh"
        if unit == "Wh", value >= 1000 {
            return "\((value / 1000).formatted(.number.precision(.fractionLength(0...1)))) kWh"
        }
        return "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)"
    }

    private func siblings(_ c: Climate, _ domain: String) -> [Entity] {
        store.siblings(of: entityID, domain: domain)
    }

    private func setMode(_ c: Climate, _ mode: String) {
        guard pendingMode == nil, let action = ClimateCommand.mode(c.e, requested: mode) else { return }
        let previousTemperature = sendTask
        sendTask?.cancel()
        dragTarget = nil
        pendingMode = mode
        let epoch = store.authenticationGeneration
        Task {
            // A temperature command already on the wire finishes first; a merely
            // debounced value is cancelled before it can target the new mode.
            await previousTemperature?.value
            defer { if epoch == store.authenticationGeneration { pendingMode = nil } }
            guard epoch == store.authenticationGeneration else { return }
            do {
                try await ClimateModeRecovery.perform(action, initial: c.e, send: { request in
                    _ = try await store.command(request.body, authenticationEpoch: epoch)
                }, refresh: { await store.refreshEntity(entityID, authenticationEpoch: epoch) })
                guard epoch == store.authenticationGeneration else { return }
                if store.isDemo { store.optimistic(entityID) { $0.state = mode } }
                for _ in 0..<20 {
                    guard epoch == store.authenticationGeneration else { return }
                    if store.entities[entityID]?.state == mode { return }
                    try await Task.sleep(for: .milliseconds(250))
                }
                _ = await store.refreshEntity(entityID, authenticationEpoch: epoch)
                guard epoch == store.authenticationGeneration else { return }
                if store.entities[entityID]?.state != mode {
                    climateFailureReport = ClimateDiagnostics.report(initial: c.e, reported: store.entities[entityID], requestedMode: mode, outcome: .unconfirmed)
                    climateFailure = "Home Assistant accepted the request but has not reported \(Theme.modeName(mode)). Check the unit before retrying."
                }
            } catch {
                _ = await store.refreshEntity(entityID, authenticationEpoch: epoch)
                guard epoch == store.authenticationGeneration else { return }
                if store.entities[entityID]?.state != mode {
                    climateFailureReport = ClimateDiagnostics.report(initial: c.e, reported: store.entities[entityID], requestedMode: mode, outcome: .rejected, error: error)
                    climateFailure = "Home Assistant couldn’t switch to \(Theme.modeName(mode)). The last reported mode is still shown.\n\n\(error.localizedDescription)"
                }
            }
        }
    }

    /// Local preview responds immediately. Only the settled value is sent, and
    /// actual Home Assistant attributes remain authoritative after a rejection.
    private func setTarget(_ c: Climate, _ value: Double) {
        guard pendingMode == nil else { return }
        if value != dragTarget { Haptic.tick() }
        withAnimation(.snap) { dragTarget = value }
        sendTask?.cancel()
        let epoch = store.authenticationGeneration
        sendTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, epoch == store.authenticationGeneration else { return }
            guard let current = store.entities[entityID],
                  let action = ClimateCommand.temperature(current, value: value) else {
                if dragTarget == value { dragTarget = nil }
                return
            }
            do {
                try await store.command(action.body, authenticationEpoch: epoch)
                guard epoch == store.authenticationGeneration else { return }
                if store.isDemo { store.optimistic(entityID) { $0.attributes["temperature"] = value } }
                for _ in 0..<20 {
                    if Task.isCancelled || epoch != store.authenticationGeneration { return }
                    if let reported = store.entities[entityID]?.num("temperature"), abs(reported - value) < 0.001 { break }
                    try await Task.sleep(for: .milliseconds(250))
                }
                if !Task.isCancelled {
                    _ = await store.refreshEntity(entityID, authenticationEpoch: epoch)
                    guard !Task.isCancelled, epoch == store.authenticationGeneration, dragTarget == value else { return }
                    if dragTarget == value,
                       store.entities[entityID]?.num("temperature").map({ abs($0 - value) < 0.001 }) != true {
                        climateFailureReport = ClimateDiagnostics.report(initial: current, reported: store.entities[entityID], outcome: .unconfirmed)
                        climateFailure = "Home Assistant accepted the request but has not reported \(degrees(value))°. Check the unit before retrying."
                    }
                }
            } catch {
                guard !Task.isCancelled, epoch == store.authenticationGeneration else { return }
                _ = await store.refreshEntity(entityID, authenticationEpoch: epoch)
                guard !Task.isCancelled, epoch == store.authenticationGeneration, dragTarget == value else { return }
                climateFailureReport = ClimateDiagnostics.report(initial: current, reported: store.entities[entityID], outcome: .rejected, error: error)
                climateFailure = error.localizedDescription
            }
            // A newer drag owns its preview; finishing an older command cannot
            // clear that value or reset the displayed number.
            if !Task.isCancelled, epoch == store.authenticationGeneration, dragTarget == value { dragTarget = nil }
        }
    }

    private func setEco(_ c: Climate, eco: String) {
        let off = c.presets.first { ["none", "comfort", "home", "normal"].contains($0.lowercased()) }
        guard let preset = c.eco ? off : eco else { return }
        store.optimistic(entityID) { $0.attributes["preset_mode"] = preset }
        store.call("climate", "set_preset_mode", entityID, ["preset_mode": preset])
    }
}

// MARK: Controls

/// A glowing power key. On, it lights up in the colour of the air: a lit white key in the dark,
/// a solid disc of the air's colour on paper, where a white key on white wouldn't read as on.
struct PowerButton: View {
    let on: Bool
    var tint: Color = .white
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let light = scheme == .light
        Button(action: action) {
            ZStack {
                if on {
                    if light {
                        Circle().fill(LinearGradient(colors: [tint.opacity(0.88), tint], startPoint: .top, endPoint: .bottom))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.75).padding(0.5))
                    } else {
                        Key(shape: Circle())
                        Circle().strokeBorder(Theme.fg.opacity(0.6), lineWidth: 0.75)
                    }
                } else {
                    Circle().fill(light ? AnyShapeStyle(Color.white) : AnyShapeStyle(Theme.fg.opacity(0.06)))
                    Circle().strokeBorder(light ? Theme.cardEdge : Theme.fg.opacity(0.12), lineWidth: light ? 0.5 : 0.75)
                }
                Image(systemName: "power")
                    .font(.system(size: 15, weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? (light ? Color.white : Theme.onKey) : Theme.ink)
            }
            .frame(width: 42, height: 42)
            .cardShadow()
            .background {
                if on {
                    // A radial halo has transparent edges instead of relying on
                    // a shadow texture whose backing rectangle can show through.
                    Circle().fill(RadialGradient(colors: [tint.opacity(light ? 0.08 : 0.13), .clear],
                                                 center: .center, startRadius: 18, endRadius: 30))
                        .frame(width: 60, height: 60).allowsHitTesting(false)
                }
            }
            .padding(3)
            .background {
                if !light {
                    Circle().fill(Theme.fg.opacity(0.025)).overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 0.75))
                }
            }
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Power")
        .accessibilityValue(on ? "On" : "Off")
        .animation(.glide, value: on)
        .help(on ? "Turn off" : "Turn on")
    }
}

struct StatusPill: View {
    let text: String
    let tint: Color
    let live: Bool

    var body: some View {
        HStack(spacing: 6) {
            PulseDot(color: live ? tint : Theme.faint, live: live)
            Text(text).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(live ? Theme.ink : Theme.muted)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(Theme.fg.opacity(0.05)).overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.75)))
    }
}

struct TrailingIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.title
            configuration.icon.font(.system(size: 11.5, weight: .light))
        }
    }
}

/// The set point: a precise track with a tick for every degree, held in a bezel between
/// two step keys. Dragging steps with a light haptic tick.
struct TemperatureControl: View {
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let tint: Color
    let active: Bool
    let onChange: (Double) -> Void

    var body: some View {
        Bezel(radius: 24, inset: 4) {
            HStack(spacing: 4) {
                key("minus") { change(value - step) }
                track
                key("plus") { change(value + step) }
            }
            .padding(3)
        }
        .padding(.top, 2)
    }

    private func change(_ proposed: Double) {
        let snapped = ClimateTemperatureScale.snapped(proposed, range: range, step: step)
        if snapped != value { onChange(snapped) }
    }

    private func key(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .light))
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.fg.opacity(0.05)))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(symbol == "minus" ? "Cooler" : "Warmer")
    }

    private var track: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let span = range.upperBound - range.lowerBound
            let f = span > 0 ? (min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / span : 0
            let x = 8 + (w - 16) * f
            ZStack(alignment: .leading) {
                // Ticks, one per degree, longer every five.
                Canvas { ctx, size in
                    let intervals = Int(min(120, max(1, ceil(span))))
                    for i in 0...intervals {
                        let tx = 8 + (size.width - 16) * CGFloat(i) / CGFloat(intervals)
                        let degree = range.lowerBound + span * Double(i) / Double(intervals)
                        let long = abs(degree.truncatingRemainder(dividingBy: 5)) < 0.001
                        let lit = tx <= x
                        var p = Path()
                        p.move(to: CGPoint(x: tx, y: size.height / 2 - (long ? 7 : 4)))
                        p.addLine(to: CGPoint(x: tx, y: size.height / 2 + (long ? 7 : 4)))
                        ctx.stroke(p, with: .color(Theme.fg.opacity(lit && active ? 0.55 : 0.14)), lineWidth: 0.8)
                    }
                }
                // The lit span.
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0), tint.opacity(active ? 0.32 : 0.08)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: x + 10, height: 30)
                    .blur(radius: 6)
                // The thumb.
                Capsule()
                    .fill(LinearGradient(colors: [.white, Theme.keyEnd], startPoint: .top, endPoint: .bottom))
                    .frame(width: 5, height: 28)
                    .glow(color: active ? tint.opacity(0.9) : .clear, radius: 8)
                    .offset(x: x - 2.5)
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let p = min(max((g.location.x - 8) / max(w - 16, 1), 0), 1)
                change(range.lowerBound + p * span)
            })
        }
        .frame(height: 38)
        .animation(.snap, value: value)
    }
}

/// A segmented selector whose highlight glides between options.
struct Segmented<Option: Hashable, Label: View>: View {
    let options: [Option]
    let selected: Option?
    let tint: Color
    let id: String
    var compact = false
    @ViewBuilder let label: (Option) -> Label
    let onSelect: (Option) -> Void

    var body: some View {
        Tray(radius: compact ? 18 : 20, inset: 3) {
            HStack(spacing: 2) {
                ForEach(Array(options.enumerated()), id: \.element) { index, option in
                    let on = option == selected
                    Button { onSelect(option) } label: {
                        VStack(spacing: compact ? 3 : 4) { label(option) }
                            .frame(maxWidth: .infinity)
                            .frame(height: compact ? 38 : 46)
                            .foregroundStyle(on ? Theme.onKey : Theme.muted)
                            .background {
                                if !on {
                                    Color.clear.hoverFill(RoundedRectangle(cornerRadius: compact ? 13 : 15, style: .continuous))
                                }
                            }
                            .contentShape(Rectangle())
                            .selectionFrame(index)
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .slidingSelection(selected.flatMap { options.firstIndex(of: $0) }, radius: compact ? 13 : 15, glow: tint.opacity(0.35))
            .padding(2)
        }
        .animation(.selectionSlide, value: selected)
    }
}

/// Fan speed as four rising bars, lit to the speed; auto is a small rounded A.
struct FanGlyph: View {
    let rank: Double

    var body: some View {
        if rank == 0 {
            Text("A").font(.system(size: 13, weight: .light, design: .rounded)).frame(height: 13)
        } else {
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(1...4, id: \.self) { i in
                    Capsule().frame(width: 2.2, height: 3 + CGFloat(i) * 2.5).opacity(Double(i) <= rank + 0.5 ? 1 : 0.22)
                }
            }
            .frame(height: 13)
        }
    }
}

/// Fan speed as one control: an Auto key, then a bar of rising steps you drag across,
/// and a fan that spins as fast as the speed you picked.
struct FanControl: View {
    let modes: [String]
    let selected: String?
    let tint: Color
    let running: Bool
    let onSelect: (String) -> Void

    @Environment(\.colorScheme) private var scheme
    private var auto: String? { modes.first { Climate.fanRank($0) == 0 } }
    private var steps: [String] { modes.filter { Climate.fanRank($0) > 0 } }

    var body: some View {
        let isAuto = selected != nil && selected == auto
        let index = steps.firstIndex { $0 == selected }
        Tray(radius: 20, inset: 3) {
            HStack(spacing: 10) {
                if let auto {
                    Button { onSelect(auto) } label: {
                        Text("AUTO").font(.system(size: 11, weight: .bold)).tracking(0.8)
                            .foregroundStyle(isAuto ? Theme.onKey : Theme.muted)
                            .frame(width: 46, height: 30)
                            .background {
                                if isAuto { Key(shape: Capsule(), glow: tint.opacity(0.45)) } else { Capsule().fill(Theme.fg.opacity(0.05)) }
                            }
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Automatic fan speed")
                    .accessibilityAddTraits(isAuto ? .isSelected : [])
                }
                GeometryReader { geo in
                    let n = max(steps.count, 1)
                    let w = geo.size.width
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { i, _ in
                            let lit = index.map { i <= $0 } ?? false
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .fill(lit ? AnyShapeStyle(LinearGradient(colors: [scheme == .light ? tint.opacity(0.62) : .white, tint], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Theme.fg.opacity(0.1)))
                                .frame(height: 8 + CGFloat(i) * (22 / CGFloat(max(n - 1, 1))))
                                .glow(color: lit ? tint.opacity(0.5) : .clear, radius: 4)
                        }
                    }
                    .frame(width: w, height: geo.size.height, alignment: .bottom)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                        let i = min(max(Int(g.location.x / w * CGFloat(n)), 0), n - 1)
                        if steps[i] != selected { Haptic.tick(); onSelect(steps[i]) }
                    })
                }
                .frame(height: 30)
                .animation(.snap, value: selected)
                VStack(spacing: 1) {
                    SpinningFan(speed: running ? (isAuto ? 0.6 : Double((index ?? 0) + 1) / Double(max(steps.count, 1))) : 0, tint: tint)
                    Text(isAuto ? "Auto" : selected.map(Climate.fanLabel) ?? "Fan")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                        .contentTransition(.opacity)
                }
                .frame(width: 44)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
        }
    }
}

/// A fan glyph that turns at the given speed, from still to brisk.
struct SpinningFan: View {
    let speed: Double
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: speed <= 0)) { t in
            Image(systemName: "fan")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(speed > 0 ? tint : Theme.faint)
                .rotationEffect(.degrees(t.date.timeIntervalSinceReferenceDate * 360 * (0.4 + speed * 1.6) * (reduceMotion ? 0.25 : 1)))
        }
        .frame(width: 20, height: 20)
    }
}

/// A compact capsule toggle for the quick-settings row.
struct QuickChip: View {
    let symbol: String
    let label: String
    let on: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12, weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? tint : Theme.muted)
                Text(label).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    .foregroundStyle(on ? Theme.ink : Theme.muted)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(Capsule().fill(on ? tint.opacity(0.14) : Theme.fg.opacity(0.045)))
            .overlay(Capsule().strokeBorder(on ? tint.opacity(0.5) : Theme.hairline, lineWidth: on ? 1 : 0.75))
            .glow(color: on ? tint.opacity(0.3) : .clear, radius: 8)
            .contentShape(Capsule())
            .hoverFill(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityValue(on ? "On" : "Off")
        .animation(.glide, value: on)
    }
}

/// A small square key that lights up when on.
struct ToggleKey: View {
    let symbol: String
    let label: String
    let on: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Bezel(radius: 18, inset: 3, lit: on, tint: on ? tint : .white) {
                VStack(spacing: 4) {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .light))
                        .symbolEffect(.bounce, value: on)
                    Text(label).font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(on ? Theme.ink : Theme.muted)
                .frame(width: 54, height: 38)
            }
            .glow(color: on ? tint.opacity(0.35) : .clear, radius: 12)
        }
        .buttonStyle(PressStyle())
        .animation(.glide, value: on)
    }
}
