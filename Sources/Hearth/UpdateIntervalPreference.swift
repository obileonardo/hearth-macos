import Foundation

/// Presentation and timing share one bounded interpretation of saved intervals.
/// Reading a legacy or malformed value never rewrites the user's preference.
enum UpdateIntervalPreference: CaseIterable {
    case cameraRefresh, statusRotation

    var key: String {
        switch self {
        case .cameraRefresh: "camera.refresh"
        case .statusRotation: "status.interval"
        }
    }

    var defaultSeconds: Double {
        switch self {
        case .cameraRefresh: 60
        case .statusRotation: 6
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .cameraRefresh: 30...480
        case .statusRotation: 4...60
        }
    }

    private var presets: [Double] {
        switch self {
        case .cameraRefresh: [30, 60, 90, 120, 180, 240, 360, 480]
        case .statusRotation: [4, 6, 10, 20, 30, 45, 60]
        }
    }

    func seconds(for stored: Double) -> Double {
        guard stored.isFinite, stored > 0 else { return defaultSeconds }
        return min(max(stored, range.lowerBound), range.upperBound)
    }

    func saved(in defaults: UserDefaults = .standard) -> Double {
        seconds(for: defaults.object(forKey: key) as? Double ?? defaultSeconds)
    }

    func label(for stored: Double) -> String {
        let value = seconds(for: stored)
        if let whole = Int(exactly: value) { return String(whole) }
        // Preserve an in-range fractional choice exactly rather than showing an
        // integer that would silently replace it when selected in the menu.
        return String(value)
    }

    func choices(including stored: Double) -> [String] {
        let current = seconds(for: stored)
        let values = presets.contains(current) ? presets : presets + [current]
        return values.sorted().map { label(for: $0) }
    }

    func seconds(fromChoice choice: String) -> Double? {
        guard let value = Double(choice), value.isFinite, range.contains(value) else { return nil }
        return value
    }
}
