import AppKit
import Combine
import Foundation

// MARK: Models

/// The person signed in to Home Assistant.
struct HAUser {
    var id: String
    var name: String
    var username: String?
    var isAdmin: Bool
    var isOwner: Bool
}

/// What the server says about itself (`get_config`).
struct HAServer {
    var locationName: String
    var version: String
    var timeZone: String
    var units: String
    var externalURL: String?
    var internalURL: String?
    var state: String
    var safeMode: Bool
}

/// One configured integration (a config entry).
struct HAEntry: Identifiable, Hashable {
    var id: String
    var domain: String
    var title: String
    var state: String
    var reason: String?
    var disabledBy: String?
    var source: String
    var supportsUnload: Bool

    /// Set up and working.
    var isHealthy: Bool { state == "loaded" || state == "not_loaded" && disabledBy != nil }
    /// Something went wrong setting it up.
    var isFailing: Bool { ["setup_error", "setup_retry", "failed_unload", "migration_error"].contains(state) }

    var stateText: String {
        if disabledBy != nil { return "Turned off" }
        switch state {
        case "loaded": return "Working"
        case "setup_retry": return "Retrying"
        case "setup_error": return "Couldn't start"
        case "migration_error": return "Needs attention"
        case "failed_unload": return "Stuck"
        case "not_loaded": return "Not running"
        case "setup_in_progress": return "Starting"
        default: return state.pretty
        }
    }
}

/// An integration that can be added, from Home Assistant's catalogue.
struct HACatalogItem: Identifiable, Hashable {
    var id: String { domain }
    var domain: String
    var name: String
    var isCustom: Bool
    var kind: String?
}

/// A room, with what's in it.
struct HAAreaRow: Identifiable, Hashable {
    var id: String
    var name: String
    var floorID: String?
}

/// A device, for moving between rooms and renaming.
struct HADeviceRow: Identifiable, Hashable {
    var id: String
    var name: String
    var givenName: String?
    var manufacturer: String?
    var model: String?
    var areaID: String?
    var isService: Bool
    var shownName: String { givenName ?? name }
}

// MARK: Setup flows

/// One field in a setup form, read from Home Assistant's `data_schema`.
struct FlowField: Identifiable {
    enum Kind {
        case text(secure: Bool, multiline: Bool)
        case number(min: Double?, max: Double?, step: Double?)
        case boolean
        case select(options: [(value: String, label: String)], multiple: Bool, custom: Bool)
        /// A selector Hearth doesn't draw; it gets a text field and a way to finish in Home Assistant.
        case unsupported(String)
    }
    var id: String { name }
    var name: String
    var required: Bool
    var kind: Kind
    var defaultValue: Any?
    /// For select fields whose option labels come from translations.
    var translationKey: String?
}

/// Where a setup flow is, as Home Assistant describes it.
struct FlowStep {
    enum Kind: String { case form, createEntry = "create_entry", abort, menu, progress, external, externalDone = "external_done", unknown }
    var kind: Kind
    var flowID: String
    var handler: String
    var stepID: String?
    var fields: [FlowField]
    var errors: [String: String]
    var placeholders: [String: String]
    var menu: [(value: String, label: String?)]
    var url: URL?
    var reason: String?
    var title: String?
    var lastStep: Bool?

    init(_ json: JSON) {
        let type = json["type"] as? String ?? ""
        kind = Kind(rawValue: type) ?? (type == "external_step" ? .external : type == "show_progress" ? .progress : .unknown)
        flowID = json["flow_id"] as? String ?? ""
        handler = json["handler"] as? String ?? ""
        stepID = json["step_id"] as? String
        errors = (json["errors"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
        placeholders = (json["description_placeholders"] as? [String: Any] ?? [:]).compactMapValues { "\($0)" }
        reason = json["reason"] as? String
        title = json["title"] as? String
        lastStep = json["last_step"] as? Bool
        url = (json["url"] as? String).flatMap(URL.init(string:))
        if let list = json["menu_options"] as? [String] {
            menu = list.map { ($0, nil) }
        } else if let dict = json["menu_options"] as? [String: String] {
            menu = dict.map { ($0.key, Optional($0.value)) }.sorted { $0.value < $1.value }
        } else {
            menu = []
        }
        fields = (json["data_schema"] as? [JSON] ?? []).compactMap(FlowStep.field)
    }

    private static func field(_ f: JSON) -> FlowField? {
        guard let name = f["name"] as? String else { return nil }
        let required = f["required"] as? Bool ?? false
        let defaultValue = f["default"] ?? ((f["description"] as? JSON)?["suggested_value"])
        func options(_ raw: Any?) -> [(value: String, label: String)] {
            if let list = raw as? [String] { return list.map { ($0, $0) } }
            if let list = raw as? [JSON] {
                return list.compactMap { o in (o["value"] as? String).map { ($0, o["label"] as? String ?? $0) } }
            }
            if let pairs = raw as? [[Any]] {
                return pairs.compactMap { p in p.count == 2 ? ("\(p[0])", "\(p[1])") : nil }
            }
            if let dict = raw as? [String: Any] {
                return dict.map { ($0.key, "\($0.value)") }.sorted { $0.label < $1.label }
            }
            return []
        }

        if let selector = f["selector"] as? JSON, let (type, config) = selector.first {
            let c = config as? JSON ?? [:]
            switch type {
            case "text":
                let t = c["type"] as? String
                return FlowField(name: name, required: required, kind: .text(secure: t == "password", multiline: c["multiline"] as? Bool ?? false), defaultValue: defaultValue)
            case "number":
                return FlowField(name: name, required: required,
                                 kind: .number(min: c["min"] as? Double, max: c["max"] as? Double, step: c["step"] as? Double),
                                 defaultValue: defaultValue)
            case "boolean", "constant":
                return FlowField(name: name, required: required, kind: .boolean, defaultValue: defaultValue)
            case "select":
                return FlowField(name: name, required: required,
                                 kind: .select(options: options(c["options"]), multiple: c["multiple"] as? Bool ?? false,
                                               custom: c["custom_value"] as? Bool ?? false),
                                 defaultValue: defaultValue, translationKey: c["translation_key"] as? String)
            case "country":
                let codes = c["countries"] as? [String] ?? []
                let opts = codes.map { ($0, Locale.current.localizedString(forRegionCode: $0) ?? $0) }.sorted { $0.1 < $1.1 }
                return FlowField(name: name, required: required, kind: .select(options: opts, multiple: false, custom: false), defaultValue: defaultValue)
            case "language":
                let codes = c["languages"] as? [String] ?? []
                let opts = codes.map { ($0, Locale.current.localizedString(forIdentifier: $0) ?? $0) }.sorted { $0.1 < $1.1 }
                return FlowField(name: name, required: required, kind: .select(options: opts, multiple: false, custom: false), defaultValue: defaultValue)
            default:
                return FlowField(name: name, required: required, kind: .unsupported(type), defaultValue: defaultValue)
            }
        }

        // Older integrations describe fields with voluptuous types instead of selectors.
        switch f["type"] as? String {
        case "string":
            return FlowField(name: name, required: required, kind: .text(secure: (f["format"] as? String) == "password", multiline: false), defaultValue: defaultValue)
        case "integer", "float":
            return FlowField(name: name, required: required,
                             kind: .number(min: f["valueMin"] as? Double, max: f["valueMax"] as? Double, step: f["type"] as? String == "integer" ? 1 : nil),
                             defaultValue: defaultValue)
        case "boolean":
            return FlowField(name: name, required: required, kind: .boolean, defaultValue: defaultValue)
        case "select":
            return FlowField(name: name, required: required, kind: .select(options: options(f["options"]), multiple: false, custom: false), defaultValue: defaultValue)
        case "multi_select":
            return FlowField(name: name, required: required, kind: .select(options: options(f["options"]), multiple: true, custom: false), defaultValue: defaultValue)
        case let other:
            return FlowField(name: name, required: required, kind: .unsupported(other ?? "field"), defaultValue: defaultValue)
        }
    }
}

// MARK: The admin model

/// Everything Hearth shows about the Home Assistant server and its integrations, read live and
/// changed through Home Assistant's own APIs (the same ones its web frontend uses).
@MainActor
final class HAAdmin: ObservableObject {
    static let shared = HAAdmin()

    enum Section: String, CaseIterable, Identifiable {
        case integrations, add, areas, devices
        var id: String { rawValue }
        var title: String {
            switch self {
            case .integrations: "Integrations"
            case .add: "Add integration"
            case .areas: "Areas"
            case .devices: "Devices"
            }
        }
        var symbol: String {
            switch self {
            case .integrations: "puzzlepiece.extension"
            case .add: "plus.circle"
            case .areas: "square.split.2x2"
            case .devices: "cpu"
            }
        }
    }

    @Published var section: Section = .integrations
    @Published private(set) var user: HAUser?
    @Published private(set) var server: HAServer?
    @Published private(set) var entries: [HAEntry] = []
    @Published private(set) var areas: [HAAreaRow] = []
    @Published private(set) var floors: [Floor] = []
    @Published private(set) var supportsFloors = false
    @Published private(set) var devices: [HADeviceRow] = []
    @Published private(set) var catalog: [HACatalogItem] = []
    @Published private(set) var latency: Double?
    @Published private(set) var connectedSince: Date?
    @Published private(set) var avatar: NSImage?
    @Published var problem: String?

    private(set) weak var store: HomeStore?
    private var watch: AnyCancellable?

    func attach(_ store: HomeStore) {
        guard self.store !== store else { return }
        self.store = store
        if store.status == .connected { connectedSince = Date() }
        watch = store.$status.removeDuplicates().sink { [weak self] status in
            Task { @MainActor in
                self?.connectedSince = status == .connected ? (self?.connectedSince ?? Date()) : nil
            }
        }
    }

    @discardableResult
    private func command(_ body: JSON) async throws -> Any? {
        guard let store else { throw ProviderError("Not connected") }
        return try await store.command(body)
    }

    // MARK: Account and server

    func refreshAccount() async {
        do {
            if let u = try await command(["type": "auth/current_user"]) as? JSON {
                let creds = u["credentials"] as? [JSON] ?? []
                user = HAUser(id: u["id"] as? String ?? "", name: u["name"] as? String ?? "You",
                              username: creds.isEmpty ? nil : UserDefaults.standard.string(forKey: "ha.username"),
                              isAdmin: u["is_admin"] as? Bool ?? false, isOwner: u["is_owner"] as? Bool ?? false)
            }
            if let c = try await command(["type": "get_config"]) as? JSON {
                let units = c["unit_system"] as? JSON
                server = HAServer(locationName: c["location_name"] as? String ?? "Home",
                                  version: c["version"] as? String ?? "",
                                  timeZone: c["time_zone"] as? String ?? "",
                                  units: (units?["temperature"] as? String) == "°F" ? "US customary" : "Metric",
                                  externalURL: c["external_url"] as? String, internalURL: c["internal_url"] as? String,
                                  state: c["state"] as? String ?? "", safeMode: c["safe_mode"] as? Bool ?? false)
            }
            problem = nil
            async let avatar: Void = loadAvatar()
            async let entries: Void = refreshEntries()
            async let latency: Void = ping()
            _ = await (avatar, entries, latency)
        } catch {
            problem = error.localizedDescription
        }
    }

    /// The person entity that belongs to this user carries their picture.
    private func loadAvatar() async {
        guard let store, let user, avatar == nil,
              let person = store.entities.values.first(where: { $0.domain == "person" && $0.str("user_id") == user.id }),
              let path = person.str("entity_picture") else { return }
        if let data = await store.pictureData(at: path) { avatar = NSImage(data: data) }
    }

    /// Round trip time for a `ping`, in milliseconds.
    func ping() async {
        let start = Date()
        if (try? await command(["type": "ping"])) != nil {
            latency = Date().timeIntervalSince(start) * 1000
        } else {
            latency = nil
        }
    }

    func reloadIntegrations() async throws {
        try await command(["type": "call_service", "domain": "homeassistant", "service": "reload_all", "service_data": [:] as JSON])
    }

    func restart() async throws {
        try await command(["type": "call_service", "domain": "homeassistant", "service": "restart", "service_data": [:] as JSON])
    }

    // MARK: Integrations

    func refreshEntries() async {
        guard let list = try? await command(["type": "config_entries/get"]) as? [JSON] else { return }
        entries = list.map { e in
            HAEntry(id: e["entry_id"] as? String ?? UUID().uuidString, domain: e["domain"] as? String ?? "",
                    title: e["title"] as? String ?? "", state: e["state"] as? String ?? "",
                    reason: e["reason"] as? String, disabledBy: e["disabled_by"] as? String,
                    source: e["source"] as? String ?? "", supportsUnload: e["supports_unload"] as? Bool ?? false)
        }
        .sorted { ($0.isFailing ? 0 : 1, $0.domain, $0.title) < ($1.isFailing ? 0 : 1, $1.domain, $1.title) }
        // Proper names ("LG ThinQ", not "Lg Thinq") from each integration's manifest.
        let missing = Array(Set(entries.map(\.domain)).filter { names[$0] == nil })
        if !missing.isEmpty, let manifests = try? await command(["type": "manifest/list", "integrations": missing]) as? [JSON] {
            for m in manifests {
                if let domain = m["domain"] as? String, let name = m["name"] as? String { names[domain] = name }
            }
            objectWillChange.send()
        }
    }

    func reload(_ entry: HAEntry) async throws {
        try await command(["type": "config_entries/reload", "entry_id": entry.id])
        await refreshEntries()
    }

    func setEnabled(_ entry: HAEntry, _ on: Bool) async throws {
        try await command(["type": "config_entries/disable", "entry_id": entry.id, "disabled_by": on ? NSNull() : "user"])
        await refreshEntries()
    }

    func delete(_ entry: HAEntry) async throws {
        try await command(["type": "config_entries/delete", "entry_id": entry.id])
        await refreshEntries()
    }

    /// Integration names as people know them, keyed by domain, from the catalogue and its translations.
    private(set) var names: [String: String] = [:]

    func name(of domain: String) -> String { names[domain] ?? domain.replacingOccurrences(of: "_", with: " ").capitalized }

    /// Every integration that can be added through a setup flow, built in and from HACS.
    func loadCatalog() async {
        guard catalog.isEmpty, let d = try? await command(["type": "integration/descriptions"]) as? JSON else { return }
        let flowHandlers = Set((try? await rest("GET", "api/config/config_entries/flow_handlers") as? [String]) ?? [])
        var items: [HACatalogItem] = []
        var needsTitle: [String] = []
        for (group, custom) in [("core", false), ("custom", true)] {
            let integrations = (d[group] as? JSON)?["integration"] as? JSON ?? [:]
            for (domain, raw) in integrations {
                guard let info = raw as? JSON else { continue }
                // Brands (Google, Philips) group several integrations; list each one that can be set up.
                if let children = info["integrations"] as? JSON {
                    for (child, rawChild) in children {
                        guard let c = rawChild as? JSON, c["config_flow"] as? Bool == true || flowHandlers.contains(child) else { continue }
                        let name = c["name"] as? String
                        if name == nil { needsTitle.append(child) }
                        items.append(HACatalogItem(domain: child, name: name ?? child, isCustom: custom, kind: c["integration_type"] as? String))
                    }
                    continue
                }
                guard info["config_flow"] as? Bool == true || flowHandlers.contains(domain) else { continue }
                guard info["integration_type"] as? String != "virtual" || info["supported_by"] == nil else { continue }
                let name = info["name"] as? String
                if name == nil { needsTitle.append(domain) }
                items.append(HACatalogItem(domain: domain, name: name ?? domain, isCustom: custom, kind: info["integration_type"] as? String))
            }
        }
        // Names that only live in translations.
        let translated = ((d["core"] as? JSON)?["translated_name"] as? [String] ?? []) + needsTitle
        if !translated.isEmpty, let t = try? await command(["type": "frontend/get_translations", "language": "en",
                                                                 "category": "title", "integration": Array(Set(translated))]) as? JSON,
           let resources = t["resources"] as? JSON {
            for i in items.indices {
                if let title = resources["component.\(items[i].domain).title"] as? String { items[i].name = title }
            }
        }
        var seen = Set<String>()
        catalog = items.filter { seen.insert($0.domain).inserted }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        for item in catalog { names[item.domain] = item.name }
        objectWillChange.send()
    }

    // MARK: Setup flows

    func startFlow(_ domain: String) async throws -> FlowStep {
        let json = try await rest("POST", "api/config/config_entries/flow", ["handler": domain, "show_advanced_options": true])
        return FlowStep(json as? JSON ?? [:])
    }

    func submit(_ flowID: String, _ data: JSON) async throws -> FlowStep {
        let json = try await rest("POST", "api/config/config_entries/flow/\(flowID)", data)
        let step = FlowStep(json as? JSON ?? [:])
        if step.kind == .createEntry { await refreshEntries() }
        return step
    }

    func current(_ flowID: String) async throws -> FlowStep {
        FlowStep(try await rest("GET", "api/config/config_entries/flow/\(flowID)") as? JSON ?? [:])
    }

    func abort(_ flowID: String) async {
        _ = try? await rest("DELETE", "api/config/config_entries/flow/\(flowID)")
    }

    private var translations: [String: [String: String]] = [:]

    /// A flow's words: step titles and descriptions, field labels, errors, abort reasons and option labels.
    func strings(for domain: String) async -> [String: String] {
        if let cached = translations[domain] { return cached }
        var out: [String: String] = [:]
        for category in ["config", "selector"] {
            if let t = try? await command(["type": "frontend/get_translations", "language": "en", "category": category,
                                           "integration": [domain]]) as? JSON,
               let resources = t["resources"] as? JSON {
                for (k, v) in resources { if let s = v as? String { out[k] = s } }
            }
        }
        translations[domain] = out
        return out
    }

    // MARK: Areas and devices

    func refreshAreas() async {
        if let list = try? await command(["type": "config/floor_registry/list"]) as? [JSON] {
            supportsFloors = true
            floors = list.compactMap { f in
                guard let id = f["floor_id"] as? String else { return nil }
                return Floor(id: id, name: f["name"] as? String ?? id, level: f["level"] as? Int ?? 0)
            }.sorted { $0.level < $1.level }
        } else { supportsFloors = false }
        if let list = try? await command(["type": "config/area_registry/list"]) as? [JSON] {
            areas = list.compactMap { a in
                guard let id = a["area_id"] as? String else { return nil }
                return HAAreaRow(id: id, name: a["name"] as? String ?? id, floorID: a["floor_id"] as? String)
            }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        if let list = try? await command(["type": "config/device_registry/list"]) as? [JSON] {
            devices = list.compactMap { d in
                guard let id = d["id"] as? String else { return nil }
                return HADeviceRow(id: id, name: d["name"] as? String ?? "Device", givenName: d["name_by_user"] as? String,
                                   manufacturer: d["manufacturer"] as? String, model: d["model"] as? String,
                                   areaID: d["area_id"] as? String, isService: d["entry_type"] as? String == "service")
            }.sorted { $0.shownName.localizedCaseInsensitiveCompare($1.shownName) == .orderedAscending }
        }
        // Keep the menu bar Rooms page in sync with edits in this window.
        await store?.refreshPlaces()
    }

    func createFloor(_ name: String, level: Int) async throws {
        try await command(["type": "config/floor_registry/create", "name": name, "level": level])
        await refreshAreas()
    }

    func assignFloor(_ floorID: String?, to area: HAAreaRow) async throws {
        try await command(["type": "config/area_registry/update", "area_id": area.id,
                           "floor_id": floorID.map { $0 as Any } ?? NSNull()])
        await refreshAreas()
    }

    func createArea(_ name: String) async throws {
        try await command(["type": "config/area_registry/create", "name": name])
        await refreshAreas()
    }

    func renameArea(_ area: HAAreaRow, to name: String) async throws {
        try await command(["type": "config/area_registry/update", "area_id": area.id, "name": name])
        await refreshAreas()
    }

    func deleteArea(_ area: HAAreaRow) async throws {
        try await command(["type": "config/area_registry/delete", "area_id": area.id])
        await refreshAreas()
    }

    func updateDevice(_ device: HADeviceRow, name: String? = nil, areaID: String?? = nil) async throws {
        var body: JSON = ["type": "config/device_registry/update", "device_id": device.id]
        if let name { body["name_by_user"] = name.isEmpty ? NSNull() : name }
        if let areaID { body["area_id"] = areaID ?? NSNull() }
        try await command(body)
        await refreshAreas()
    }

    // MARK: REST

    /// Home Assistant's REST API, for the setup flows the WebSocket API doesn't run.
    @discardableResult
    func rest(_ method: String, _ path: String, _ body: JSON? = nil) async throws -> Any? {
        guard let store, let base = store.baseURL else { throw ProviderError("Not connected") }
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = method
        req.timeoutInterval = 30
        req.setValue("Bearer \(try await store.validAccessToken())", forHTTPHeaderField: "Authorization")
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = data.isEmpty ? nil : try? JSONSerialization.jsonObject(with: data)
        guard (200..<300).contains(status) else {
            let message = (json as? JSON)?["message"] as? String
            throw ProviderError(message ?? "Home Assistant answered \(status)")
        }
        return json
    }

    // MARK: Brand icons

    private var icons: [String: NSImage] = [:]
    private static let iconFolder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Hearth/brands", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// The integration's brand icon from brands.home-assistant.io, kept on disk after the first fetch.
    func icon(_ domain: String) async -> NSImage? {
        guard !domain.isEmpty, domain.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 95 }) else { return nil }
        if let cached = icons[domain] { return cached }
        let file = Self.iconFolder.appendingPathComponent("\(domain).png")
        if let image = NSImage(contentsOf: file) {
            icons[domain] = image
            return image
        }
        guard let url = URL(string: "https://brands.home-assistant.io/_/\(domain)/icon.png"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200, let image = NSImage(data: data) else { return nil }
        try? data.write(to: file)
        icons[domain] = image
        return image
    }
}
