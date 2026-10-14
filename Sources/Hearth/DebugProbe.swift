import AppKit
import Foundation

/// A command-line check of a real Home Assistant through the app's own connection, for
/// testing with the same login the app uses:
///
///     Hearth --probe "dump climate.living_room; call switch.turn_on switch.lamp; wait 3"
///
/// Steps, separated by `;`:
/// - `dump <entity_id>`: state and attributes
/// - `find <text>`: entity ids containing the text, with their states
/// - `call <domain.service> <entity_id> [json]`: run a service, then report the state after
/// - `cmd <json>`: send a raw WebSocket command and print the result
/// - `snap <camera or image entity>`: fetch its picture
/// - `rest <GET|POST|DELETE> <path> [json]`: call the REST API, for setup flows the WebSocket API doesn't offer
/// - `energy`: which sensors the Energy page picked, and the numbers it worked out
/// - `wait <seconds>`
@MainActor
enum DebugProbe {
    static func run(_ script: String, store: HomeStore) {
        Task { @MainActor in
            for _ in 0..<40 where store.status != .connected { try? await Task.sleep(for: .milliseconds(500)) }
            guard store.status == .connected else {
                out("FAIL not connected: \(store.status)")
                exit(1)
            }
            out("connected: \(store.entities.count) entities, \(store.devices.count) devices, \(store.areas.count) areas")
            for step in script.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }) where !step.isEmpty {
                await perform(step, store: store)
            }
            exit(0)
        }
    }

    private static func perform(_ step: String, store: HomeStore) async {
        let parts = step.split(separator: " ", maxSplits: 3).map(String.init)
        switch parts.first {
        case "dump":
            guard parts.count > 1, let e = store.entities[parts[1]] else { return out("MISSING \(parts.dropFirst().joined())") }
            out("\(e.id) = \(e.state) \(json(e.attributes))")
        case "find":
            let needle = parts.dropFirst().joined(separator: " ").lowercased()
            for e in store.entities.values.sorted(by: { $0.id < $1.id }) where e.id.contains(needle) {
                out("  \(e.id) = \(e.state)")
            }
        case "call":
            guard parts.count >= 3 else { return out("usage: call domain.service entity [json]") }
            let ds = parts[1].split(separator: ".")
            let data = parts.count > 3 ? (try? JSONSerialization.jsonObject(with: Data(parts[3].utf8))) as? JSON ?? [:] : [:]
            let before = store.entities[parts[2]]?.state ?? "?"
            do {
                try await store.command(["type": "call_service", "domain": String(ds[0]), "service": String(ds[1]),
                                         "service_data": data, "target": ["entity_id": parts[2]]])
                for _ in 0..<20 where store.entities[parts[2]]?.state == before {
                    try? await Task.sleep(for: .milliseconds(500))
                }
                let after = store.entities[parts[2]]
                out("OK \(parts[1]) \(parts[2]): \(before) -> \(after?.state ?? "?")")
            } catch {
                out("FAIL \(parts[1]) \(parts[2]): \(error.localizedDescription)")
            }
        case "cmd":
            let body = parts.dropFirst().joined(separator: " ")
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? JSON else { return out("bad json") }
            do { out("OK \(json(try await store.command(obj) ?? "null"))") } catch { out("FAIL \(error.localizedDescription)") }
        case "snap":
            guard parts.count > 1 else { return }
            let id = parts[1]
            let image = id.hasPrefix("image.") ? await store.image(id) : await store.snapshot(id)
            out(image.map { "OK picture \(id): \(Int($0.size.width))x\(Int($0.size.height))" } ?? "FAIL no picture from \(id)")
        case "rest":
            guard parts.count >= 3, let base = store.baseURL else { return out("usage: rest METHOD path [json]") }
            do {
                var req = URLRequest(url: base.appendingPathComponent(parts[2]))
                req.httpMethod = parts[1]
                req.setValue("Bearer \(try await store.validAccessToken())", forHTTPHeaderField: "Authorization")
                if parts.count > 3 {
                    req.httpBody = Data(parts[3].utf8)
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
                let (data, response) = try await URLSession.shared.data(for: req)
                out("\((response as? HTTPURLResponse)?.statusCode ?? 0) \(String(decoding: data, as: UTF8.self))")
            } catch {
                out("FAIL \(error.localizedDescription)")
            }
        case "energy":
            let prefs = (try? await store.command(["type": "energy/get_prefs"]) as? JSON).map(EnergyPrefs.init)
            let sys = EnergySystem.read(store, prefs: prefs)
            out("prefs set: \(prefs?.isSet ?? false); devices: \(sys.devices.map { "\($0.name) (\($0.kind.rawValue))" })")
            out("solar: \(sys.solar.map(\.id)) battery: \(sys.battery?.id ?? "-") charge/discharge: \(sys.batteryCharging?.id ?? "-")/\(sys.batteryDischarging?.id ?? "-")")
            out("grid: \(sys.grid?.id ?? "-") import/export: \(sys.gridImport?.id ?? "-")/\(sys.gridExport?.id ?? "-") load: \(sys.load?.id ?? "-")")
            out("soc: \(sys.charge?.id ?? "-") volts: \(sys.batteryVoltage?.id ?? "-") amps: \(sys.batteryCurrent?.id ?? "-") temp: \(sys.batteryTemperature?.id ?? "-") capacity: \(sys.batteryCapacity?.id ?? "-") status: \(sys.batteryStatus?.id ?? "-")")
            out("mode: \(sys.inverterMode?.id ?? "-") inverter temp: \(sys.inverterTemperature?.id ?? "-") output load: \(sys.outputLoad?.id ?? "-") faults: \(sys.faults.map(\.id))")
            out("cells: \(sys.cells.count) cell temps: \(sys.cellTemperatures.map(\.id)) solar today: \(sys.solarToday?.id ?? "-")")
            out("watts: solar \(sys.solarWatts ?? .nan) battery \(sys.batteryWatts ?? .nan) grid \(sys.gridWatts ?? .nan) load \(sys.loadWatts ?? .nan)")
        case "wait":
            try? await Task.sleep(for: .seconds(Double(parts.count > 1 ? parts[1] : "1") ?? 1))
        default:
            out("unknown step: \(step)")
        }
    }

    private static func json(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value) || value is [Any] || value is JSON,
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return "\(value)" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func out(_ s: String) {
        print(s)
        fflush(stdout)
    }
}
