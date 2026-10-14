import Foundation

/// The only data shared with WidgetKit. No tokens, addresses, photographs,
/// account information, or raw Home Assistant attributes are serialized.
struct HearthWidgetSnapshot: Codable, Equatable {
    static let schema = 1
    var schemaVersion = schema
    var updatedAt: Date
    var connection: String
    var climate: ClimateReading?
    var activity: ActivityReading?
    var energy: EnergyReading
    var playing: PlayingReading?
    var deviceCount: Int
    var roomCount: Int

    struct ClimateReading: Codable, Equatable {
        var entityID: String
        var name: String
        var mode: String
        var target: Double?
        var room: Double?
        var available: Bool
    }
    struct ActivityReading: Codable, Equatable {
        var title: String
        var symbol: String
        var date: Date
    }
    struct EnergyReading: Codable, Equatable {
        var batteryPercent: Double?
        var solarWatts: Double?
        var homeWatts: Double?
        var hasReadings: Bool { batteryPercent != nil || solarWatts != nil || homeWatts != nil }
    }
    struct PlayingReading: Codable, Equatable {
        var title: String
        var artist: String?
    }

    static func empty(at date: Date = .now) -> Self {
        Self(updatedAt: date, connection: "Connect Hearth", climate: nil, activity: nil,
             energy: EnergyReading(), playing: nil, deviceCount: 0, roomCount: 0)
    }
    static func sample(at date: Date = .now) -> Self {
        Self(updatedAt: date, connection: "Sample", climate:
                ClimateReading(entityID: "climate.workspace", name: "Workspace", mode: "cool", target: 24, room: 26, available: true),
             activity: ActivityReading(title: "Someone rang the doorbell", symbol: "bell", date: date),
             energy: EnergyReading(batteryPercent: 76, solarWatts: 1450, homeWatts: 820),
             playing: nil, deviceCount: 18, roomCount: 7)
    }
}

enum HearthWidgetTimeline {
    static func stale(_ snapshot: HearthWidgetSnapshot, at date: Date) -> Bool {
        date.timeIntervalSince(snapshot.updatedAt) >= 300
    }
    static func dates(_ snapshot: HearthWidgetSnapshot, now: Date) -> [Date] {
        [now, max(now.addingTimeInterval(1), snapshot.updatedAt.addingTimeInterval(300))]
    }
    static func refresh(after date: Date) -> Date { date.addingTimeInterval(900) }
}

enum HearthWidgetLink {
    private static let pages: Set<String> = ["rooms", "activity", "energy", "speakers", "devices", "security", "map"]
    static func url(page: String) -> URL {
        URL(string: "hearth://widget/\(pages.contains(page) ? page : "rooms")")!
    }
    static func climateURL(entityID: String?) -> URL {
        guard let entityID, validClimateID(entityID) else { return url(page: "rooms") }
        var components = URLComponents(string: "hearth://widget/climate")!
        components.queryItems = [URLQueryItem(name: "entity", value: entityID)]
        return components.url!
    }
    static func destination(_ url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "hearth", components.host == "widget",
              components.user == nil, components.password == nil, components.port == nil,
              components.fragment == nil else { return nil }
        let page = String(components.path.dropFirst())
        if page == "climate" {
            guard let items = components.queryItems, items.count == 1,
                  items[0].name == "entity", let entity = items[0].value,
                  validClimateID(entity) else { return nil }
            return entity
        }
        guard components.query == nil, pages.contains(page) else { return nil }
        return page
    }
    private static func validClimateID(_ value: String) -> Bool {
        guard value.hasPrefix("climate."), value.count > 8, value.count <= 255 else { return false }
        return value.dropFirst(8).utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 95 }
    }
}

/// App and extension resolve the same entitlement-authorized container. There
/// is no fallback to guessed paths or the user's Application Support directory.
struct HearthWidgetStore {
    let folder: URL
    static var configuredGroup: String? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "HearthWidgetAppGroup") as? String,
              !group.isEmpty else { return nil }
        return group
    }
    static func shared() -> Self? {
        guard let group = configuredGroup,
              let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        return Self(folder: folder.appendingPathComponent("HearthWidgets", isDirectory: true))
    }
    var file: URL { folder.appendingPathComponent("snapshot.json") }
    func write(_ snapshot: HearthWidgetSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        guard data.count <= 65_536 else { throw StoreError.tooLarge }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    func read() -> HearthWidgetSnapshot? {
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 65_536,
              let data = try? Data(contentsOf: file),
              let result = try? JSONDecoder().decode(HearthWidgetSnapshot.self, from: data),
              result.schemaVersion == HearthWidgetSnapshot.schema else { return nil }
        return result
    }
    enum StoreError: Error { case tooLarge }
}
