import Foundation

/// Build only commands advertised by the current Home Assistant climate entity.
/// The view keeps previews separate; a request never changes its reported state.
enum ClimateCommand {
    static func mode(_ entity: Entity, requested: String) -> DeviceCommand? {
        guard entity.domain == "climate", !entity.isUnavailable,
              entity.list("hvac_modes").contains(requested), entity.state != requested else { return nil }
        return DeviceCommand(domain: "climate", service: "set_hvac_mode", entityID: entity.id,
                             data: ["hvac_mode": requested])
    }

    static func temperature(_ entity: Entity, value: Double) -> DeviceCommand? {
        guard entity.domain == "climate", !entity.isUnavailable,
              entity.num("temperature") != nil, value.isFinite else { return nil }
        let low = entity.num("min_temp") ?? 16
        let high = entity.num("max_temp") ?? 30
        guard low.isFinite, high.isFinite, low <= high, (low...high).contains(value) else { return nil }
        return DeviceCommand(domain: "climate", service: "set_temperature", entityID: entity.id,
                             data: ["temperature": value])
    }
}
