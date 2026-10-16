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
              let current = entity.num("temperature"), current.isFinite, value.isFinite,
              let range = ClimateTemperatureScale.range(entity), range.contains(value) else { return nil }
        return DeviceCommand(domain: "climate", service: "set_temperature", entityID: entity.id,
                             data: ["temperature": value])
    }
}

/// Shared by command validation and the UI so malformed attributes cannot create
/// an invalid ClosedRange, and fractional capabilities retain their precision.
enum ClimateTemperatureScale {
    static func range(_ entity: Entity) -> ClosedRange<Double>? {
        let low = entity.num("min_temp") ?? 16
        let high = entity.num("max_temp") ?? 30
        guard low.isFinite, high.isFinite, low <= high, (high - low).isFinite else { return nil }
        return low...high
    }

    static func step(_ entity: Entity) -> Double {
        guard let step = entity.num("target_temp_step"), step.isFinite, step > 0 else { return 1 }
        return step
    }

    static func snapped(_ value: Double, range: ClosedRange<Double>, step: Double) -> Double {
        guard value.isFinite, step.isFinite, step > 0 else { return range.lowerBound }
        let bounded = min(max(value, range.lowerBound), range.upperBound)
        if bounded == range.lowerBound || bounded == range.upperBound { return bounded }
        let units = ((bounded - range.lowerBound) / step).rounded()
        guard units.isFinite else { return bounded }
        // Use the advertised lower bound as the grid origin, not zero. Clamp
        // again because a fractional upper bound may fall between two steps.
        return min(max(range.lowerBound + units * step, range.lowerBound), range.upperBound)
    }
}
