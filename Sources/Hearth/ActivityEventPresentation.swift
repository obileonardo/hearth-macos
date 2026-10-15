import Foundation

/// Category icons stay stable; event icons use actual capabilities when available.
/// Never infer a heater or air conditioner from a household device's name.
enum ActivityEventPresentation {
    static func symbol(kind: ActivityLog.Kind, entity: Entity?) -> String {
        guard let entity else { return kind == .climate ? "thermometer.medium" : kind.symbol }
        if ["problem", "safety"].contains(entity.str("device_class") ?? "") {
            return "exclamationmark.triangle.fill"
        }
        guard kind == .climate else { return kind.symbol }
        let modes = entity.list("hvac_modes")
        if modes.contains("cool") || modes.contains("heat_cool") { return "air.conditioner.horizontal.fill" }
        if modes.contains("heat") || entity.domain == "water_heater" { return "heater.vertical.fill" }
        return "thermometer.medium"
    }

    static func climateLabel(_ entity: Entity) -> String {
        switch symbol(kind: .climate, entity: entity) {
        case "air.conditioner.horizontal.fill": return "AC"
        case "heater.vertical.fill": return "heating"
        default: return "climate"
        }
    }

    static func emptyMessage(for kind: ActivityLog.Kind?) -> String {
        switch kind {
        case .person: return "People detected by your cameras will appear here."
        case .doorbell: return "Doorbell events will appear here."
        case .motion: return "Motion detected around your home will appear here."
        case .security: return "Alarm updates will appear here."
        case .climate: return "Air conditioning and heating updates will appear here."
        case .pet: return "Pet detections will appear here."
        case .sound: return "Sound detections will appear here."
        case nil: return "People, the doorbell and other home events will appear here."
        }
    }
}
