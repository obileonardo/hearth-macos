import SwiftUI

/// A device and everything Home Assistant knows about it, ready to draw.
struct HomeDevice: Identifiable {
    let info: DeviceInfo
    let entities: [Entity]
    var id: String { info.id }
    var name: String { info.name }
    var domains: Set<String> { Set(entities.map(\.domain)) }
    var kind: DeviceKind {
        let k = DeviceKind.classify(manufacturer: info.manufacturer, model: info.model, name: info.name, domains: domains)
        return k == .generic && looksLikeCar ? .electricCar : k
    }

    func first(_ domain: String) -> Entity? { entities.first { $0.domain == domain } }
    func entity(key: String) -> Entity? { entities.first { EntityCatalog.key($0, deviceName: name) == key } }

    /// Online unless something says otherwise.
    var online: Bool {
        if let c = entities.first(where: { $0.id.hasSuffix("_connectivity") }) { return c.state == "on" }
        let live = entities.filter { !["sensor", "event", "button", "notify", "image"].contains($0.domain) }
        return live.isEmpty || live.contains { !$0.isUnavailable }
    }

    /// The light or tint that represents it.
    var accent: Color {
        switch kind {
        case .smartSpeaker, .speakerGroup: Color.accent(0.36, 0.8, 1.0)
        case .doorbell: Color.accent(0.45, 0.75, 1.0)
        case .securityHub, .securityHubPro: Theme.ok
        case .printer3D, .gameConsole, .computer: Self.gadgetAccent(kind)
        case .electricCar, .evCharger, .robotVacuum, .lawnMower, .aircraft, .robot: Self.vehicleAccent(kind)
        case .airConditioner: first("climate").map { Theme.air($0.state) } ?? Theme.air("cool")
        default: Theme.sand
        }
    }

    /// One line on what it's doing right now.
    var summary: String {
        if !online { return "Offline" }
        switch kind {
        case .indoorCamera, .outdoorCamera, .doorbell:
            if entities.contains(where: { $0.domain == "binary_sensor" && $0.id.contains("person") && $0.state == "on" }) { return "Person in view" }
            if entities.contains(where: { $0.domain == "binary_sensor" && $0.id.contains("motion") && $0.state == "on" }) { return "Movement now" }
            if let cam = entity(key: "camera_enabled"), cam.state == "off" { return "Camera off" }
            if let md = entity(key: "motion_detection") { return md.state == "on" ? "Watching" : "Detection off" }
            return "Camera"
        case .smartSpeaker:
            if let dnd = entity(key: "do_not_disturb"), dnd.state == "on" { return "Do not disturb" }
            if let player = first("media_player"), player.state == "playing" { return player.str("media_title") ?? "Playing" }
            if let t = entity(key: "temperature"), let v = Double(t.state) { return "\(Int(v.rounded()))\(t.str("unit_of_measurement") ?? "°")" }
            return "Ready"
        case .securityHub, .securityHubPro:
            if let alarm = first("alarm_control_panel"), !alarm.isUnavailable { return alarm.state.pretty }
            if let mode = entity(key: "current_mode"), !["unknown", "unavailable"].contains(mode.state) { return mode.state.pretty }
            return "Hub"
        case .airConditioner:
            return first("climate").map { Climate(e: $0).action } ?? "Air conditioner"
        case .printer3D:
            return PrintJob(self).summary
        case .electricCar, .evCharger, .robotVacuum, .lawnMower, .aircraft, .robot:
            return VehicleStatus(self, kind: kind).summary(kind)
        case .gameConsole, .computer:
            if let player = first("media_player") {
                if player.state == "playing", let title = player.str("media_title") { return title }
                return ["off", "standby"].contains(player.state) ? "Asleep" : player.state.pretty
            }
            return "Online"
        default:
            // The first thing that can be on or off says what it's doing.
            if let main = entities.first(where: { ["light", "switch", "fan", "cover", "lock", "media_player"].contains($0.domain) }) {
                return Readout.text(main) == main.state.pretty ? main.state.pretty : Readout.text(main)
            }
            return info.model ?? "Ready"
        }
    }
}

extension HomeStore {
    func homeDevice(_ id: String) -> HomeDevice? {
        devices[id].map { HomeDevice(info: $0, entities: entities(ofDevice: id)) }
    }

    func homeDevices(inArea areaID: String?) -> [HomeDevice] {
        devices(inArea: areaID).map { HomeDevice(info: $0, entities: entities(ofDevice: $0.id)) }
    }
}

// MARK: Rows

/// The shared row shell: a small icon plate, a label with a line of explanation, and a control.
struct ControlRow<Trailing: View>: View {
    let symbol: String
    let label: String
    var detail: String?
    var tint: Color = Theme.sand
    var lit = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(lit ? tint : Theme.muted)
                .frame(width: 28, height: 28)
                .background(Circle().fill(lit ? tint.opacity(0.14) : Theme.fg.opacity(0.05)))
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 13, weight: .semibold))
                if let detail {
                    Text(detail).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

/// A switch drawn in the panel's language: a capsule that glows warm when on.
struct GlowSwitch: View {
    let isOn: Bool
    var tint: Color = Theme.sand
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Capsule()
                .fill(isOn ? AnyShapeStyle(LinearGradient(colors: [tint, tint.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                           : AnyShapeStyle(Theme.fg.opacity(0.1)))
                .frame(width: 36, height: 21)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle().fill(.white).frame(width: 17, height: 17).padding(2)
                        .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                }
                .glow(color: isOn ? tint.opacity(0.4) : .clear, radius: 6)
        }
        .buttonStyle(PressStyle())
        .animation(.snap, value: isOn)
    }
}

/// Draws the right control for any entity.
struct EntityControl: View {
    @EnvironmentObject var store: HomeStore
    let entity: Entity
    let copy: EntityCopy
    var tint: Color = Theme.sand

    @State private var draft: Double?
    @State private var message = ""

    var body: some View {
        switch entity.domain {
        case "switch", "input_boolean", "light", "fan", "siren":
            let on = entity.state == "on"
            ControlRow(symbol: copy.symbol, label: copy.label, detail: copy.detail, tint: tint, lit: on) {
                GlowSwitch(isOn: on, tint: tint) {
                    store.optimistic(entity.id) { $0.state = on ? "off" : "on" }
                    store.call(entity.domain, on ? "turn_off" : "turn_on", entity.id)
                }
                .disabled(entity.isUnavailable)
            }
        case "number":
            numberRow
        case "select", "input_select":
            ControlRow(symbol: copy.symbol, label: copy.label, detail: copy.detail, tint: tint) {
                Button {
                    PopupMenu.show(entity.list("options"), selected: entity.state) { option in
                        store.optimistic(entity.id) { $0.state = option }
                        store.call(entity.domain, "select_option", entity.id, ["option": option])
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(entity.state.pretty).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.faint)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.fg.opacity(0.07)))
                }
                .buttonStyle(PressStyle())
            }
        case "button":
            ControlRow(symbol: copy.symbol, label: copy.label, detail: copy.detail, tint: tint) {
                Button("Run") { store.call("button", "press", entity.id) }
                    .buttonStyle(PressStyle())
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.fg.opacity(0.08)))
            }
        case "notify":
            ControlRow(symbol: copy.symbol, label: copy.label, detail: nil, tint: tint) {
                HStack(spacing: 6) {
                    HearthField(label: copy.label, placeholder: copy.detail ?? "Message", text: $message, chrome: false, onSubmit: send)
                        .frame(width: 150)
                    Button(action: send) {
                        Image(systemName: "arrow.up").font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(Theme.onCTA).frame(width: 22, height: 22).background(Circle().fill(Theme.cta))
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Send")
                    .disabled(message.isEmpty)
                }
                .padding(.leading, 10).padding(.trailing, 3).padding(.vertical, 3)
                .background(Capsule().fill(Theme.fg.opacity(0.07)))
            }
        case "media_player":
            MediaRow(entity: entity, tint: tint)
        default:
            ControlRow(symbol: copy.symbol, label: copy.label, detail: copy.detail, tint: tint,
                       lit: entity.domain == "binary_sensor" && entity.state == "on") {
                Text(Readout.text(entity)).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
        }
    }

    private func send() {
        guard !message.isEmpty else { return }
        store.call("notify", "send_message", entity.id, ["message": message])
        message = ""
        Haptic.tick()
    }

    @ViewBuilder private var numberRow: some View {
        let lo = entity.num("min") ?? 0, hi = entity.num("max") ?? 100, step = entity.num("step") ?? 1
        let value = draft ?? Double(entity.state) ?? lo
        let unit = entity.str("unit_of_measurement").map { " \($0)" } ?? ""
        VStack(spacing: 2) {
            ControlRow(symbol: copy.symbol, label: copy.label, detail: copy.detail, tint: tint, lit: value > lo) {
                Text("\(value.formatted(.number.precision(.fractionLength(step < 1 ? 1 : 0))))\(unit)")
                    .font(.system(size: 13, weight: .medium)).monospacedDigit().foregroundStyle(Theme.muted)
            }
            ThinSlider(value: value, range: lo...max(hi, lo + step), step: step, tint: tint) { v in
                draft = v
            } onEnd: { v in
                store.optimistic(entity.id) { $0.state = String(v) }
                store.call("number", "set_value", entity.id, ["value": v])
                draft = nil
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
    }
}

/// A slim slider for settings, sending once the drag ends.
struct ThinSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    var tint: Color = Theme.sand
    let onChange: (Double) -> Void
    let onEnd: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let f = (value - range.lowerBound) / max(range.upperBound - range.lowerBound, 0.0001)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.fg.opacity(0.08)).frame(height: 4)
                Capsule().fill(LinearGradient(colors: [tint.opacity(0.3), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(4, w * f), height: 4)
                Circle().fill(.white).frame(width: 13, height: 13)
                    .glow(color: tint.opacity(0.6), radius: 5)
                    .offset(x: max(0, min(w - 13, w * f - 6.5)))
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in onChange(snap(g.location.x / w)) }
                .onEnded { g in onEnd(snap(g.location.x / w)) })
        }
        .frame(height: 16)
    }

    private func snap(_ f: Double) -> Double {
        let raw = range.lowerBound + min(max(f, 0), 1) * (range.upperBound - range.lowerBound)
        return (raw / step).rounded() * step
    }
}

/// A speaker's player: what's on, play or pause, and volume.
struct MediaRow: View {
    @EnvironmentObject var store: HomeStore
    let entity: Entity
    var tint: Color = Theme.sand
    @State private var volume: Double?

    var body: some View {
        let playing = entity.state == "playing"
        VStack(spacing: 6) {
            ControlRow(symbol: playing ? "waveform" : "music.note", label: entity.str("media_title") ?? (playing ? "Playing" : "Nothing playing"),
                       detail: entity.str("media_artist"), tint: tint, lit: playing) {
                Button {
                    store.call("media_player", "media_play_pause", entity.id)
                } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill").font(.system(size: 12.5))
                        .frame(width: 28, height: 28).background(Circle().fill(Theme.fg.opacity(0.08)))
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(playing ? "Pause" : "Play")
            }
            if let v = entity.num("volume_level") {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill").font(.system(size: 10.5)).foregroundStyle(Theme.faint)
                    ThinSlider(value: volume ?? v, range: 0...1, step: 0.05, tint: tint) { volume = $0 } onEnd: { v in
                        store.call("media_player", "volume_set", entity.id, ["volume_level": v])
                        volume = nil
                    }
                    Image(systemName: "speaker.wave.3.fill").font(.system(size: 10.5)).foregroundStyle(Theme.faint)
                }
                .padding(.horizontal, 14).padding(.bottom, 8)
            }
        }
    }
}

/// Human readings of sensor values.
enum Readout {
    static func text(_ e: Entity) -> String {
        if e.isUnavailable { return "Unavailable" }
        switch e.domain {
        case "binary_sensor":
            let on = e.state == "on"
            switch e.str("device_class") {
            case "motion", "occupancy", "presence", "moving": return on ? "Detected" : "Clear"
            case "sound": return on ? "Heard" : "Quiet"
            case "door", "window", "opening": return on ? "Open" : "Closed"
            case "connectivity": return on ? "Connected" : "Offline"
            default: return on ? "On" : "Off"
            }
        case "event":
            return relative(e.state)
        default:
            if e.str("device_class") == "timestamp" { return relative(e.state) }
            if e.str("device_class") == "duration", let v = Double(e.state) {
                return v == 0 ? "Off" : "\(v.formatted(.number.precision(.fractionLength(0...1)))) \(e.str("unit_of_measurement") ?? "")"
            }
            if let v = Double(e.state) {
                let unit = e.str("unit_of_measurement") ?? ""
                return "\(v.formatted(.number.precision(.fractionLength(0...1))))\(unit == "%" || unit.hasPrefix("°") ? "" : " ")\(unit)"
            }
            return e.state.pretty
        }
    }

    static func relative(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return iso == "unknown" ? "Never" : iso.pretty }
        return d.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }
}
