#if DEBUG
import AppKit
import SwiftUI

/// Interactive appearance review with a tiny in-memory service simulator. This
/// returns before normal startup and cannot connect to a saved Home Assistant.
@MainActor
enum ClimateReview {
    static func open() -> NSWindow {
        let store = HomeStore()
        let id = "climate.preview_workspace"
        let climate = Entity(id: id, state: "cool", attributes: ["friendly_name": "Workspace", "temperature": 24,
            "current_temperature": 25.5, "min_temp": 16, "max_temp": 30, "target_temp_step": 0.5,
            "hvac_modes": ["off", "cool", "auto", "dry", "fan_only"],
            "fan_modes": ["auto", "low", "medium", "high"], "fan_mode": "high",
            "swing_modes": ["off", "on"], "swing_mode": "on", "supported_features": 128])
        let entities = [climate,
            Entity(id: "number.preview_workspace_sleep_timer", state: "0", attributes: ["min": 0, "max": 8]),
            Entity(id: "switch.preview_workspace_lighting", state: "on", attributes: [:])]
        store.playDemo(devices: [DeviceInfo(id: "preview-ac", name: "Workspace air conditioner", manufacturer: "Demo Climate", model: "Sample AC")],
                       entities: entities, deviceOf: Dictionary(uniqueKeysWithValues: entities.map { ($0.id, "preview-ac") })) { [weak store] body in
            MainActor.assumeIsolated {
                guard let store, var entity = store.entities[id] else { return nil }
                let data = body["service_data"] as? JSON ?? [:]
                switch body["service"] as? String {
                case "set_temperature": entity.attributes["temperature"] = data["temperature"]
                case "set_hvac_mode": entity.state = data["hvac_mode"] as? String ?? entity.state
                case "set_fan_mode": entity.attributes["fan_mode"] = data["fan_mode"]
                case "set_swing_mode": entity.attributes["swing_mode"] = data["swing_mode"]
                case "turn_off" where body["domain"] as? String == "climate": entity.state = "off"
                case "turn_on" where body["domain"] as? String == "climate": entity.state = "cool"
                default: break
                }
                store.playDemo(update: [entity])
                return nil
            }
        }
        let content = ScrollView {
            ClimatePage(entityID: id, shown: true)
                .padding(22).padding(.bottom, 54)
        }
        .scrollIndicators(.never)
        .frame(width: Theme.panelSize.width, height: Theme.panelSize.height)
        .foregroundStyle(Theme.ink).background(Theme.base)
        .environmentObject(store).environmentObject(ActivityLog(previewItems: []))
        .preferredColorScheme(.dark)
        let window = NSWindow(contentRect: NSRect(x: 200, y: 180, width: Theme.panelSize.width, height: Theme.panelSize.height),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Hearth · Offline AC Review · Feathered edge"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return window
    }
}
#endif
