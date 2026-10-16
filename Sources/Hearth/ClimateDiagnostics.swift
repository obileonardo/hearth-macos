import Foundation

/// A user-requested troubleshooting summary, held only by the open climate page.
/// Never includes an entity/name, server address, token, raw provider error,
/// camera data, timestamps or household temperatures. No automatic logging/export.
enum ClimateDiagnostics {
    enum Outcome: String { case rejected, unconfirmed }
    private static let knownModes = ["off", "cool", "heat", "heat_cool", "auto", "dry", "fan_only"]

    static func report(initial: Entity, reported: Entity?, requestedMode: String? = nil,
                       outcome: Outcome, error: Error? = nil) -> String {
        let available = initial.list("hvac_modes")
        let modes = knownModes.filter { available.contains($0) }.joined(separator: ", ")
        let otherModes = available.filter { !knownModes.contains($0) }.count
        let range = ClimateTemperatureScale.range(initial)
        var lines = [
            "Hearth climate diagnostic (redacted)",
            "Action: \(requestedMode == nil ? "set_temperature" : "set_hvac_mode")",
            "Result: \(outcome.rawValue)",
            "Error category: \(category(error))",
            "Initial mode: \(safeMode(initial.state))",
            "Reported mode: \(reported.map { safeMode($0.state) } ?? "not available")",
            "Advertised modes: \(modes.isEmpty ? "none" : modes)",
            "Other advertised modes: \(otherModes)",
            "Target available: \(initial.num("temperature")?.isFinite == true ? "yes" : "no")",
            "Temperature bounds: \(range == nil ? "invalid" : "valid")",
            "Temperature step: \(ClimateTemperatureScale.step(initial))",
        ]
        if let requestedMode { lines.insert("Requested mode: \(safeMode(requestedMode))", at: 2) }
        lines.append("No device identifiers, addresses, credentials or actual temperatures are included.")
        return lines.joined(separator: "\n")
    }

    private static func safeMode(_ mode: String) -> String {
        if knownModes.contains(mode) { return mode }
        if ["unavailable", "unknown"].contains(mode) { return mode }
        return "other"
    }

    private static func category(_ error: Error?) -> String {
        guard let error else { return "none" }
        if error is CancellationError { return "cancelled" }
        if let error = error as? URLError {
            switch error.code {
            case .timedOut: return "network timeout"
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost:
                return "network unavailable"
            default: return "network error"
            }
        }
        let message = error.localizedDescription.lowercased()
        if message.contains("fail device control") { return "vendor rejected device control" }
        if message.contains("not connected") || message.contains("reconnecting") { return "connection unavailable" }
        if message.contains("not confirmed") { return "acknowledgement timeout" }
        return "provider error"
    }
}
