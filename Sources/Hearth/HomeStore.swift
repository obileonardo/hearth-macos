import AppKit
import Foundation

typealias JSON = [String: Any]

/// One Home Assistant entity, as the app sees it.
struct Entity: Identifiable {
    let id: String
    var state: String
    var attributes: JSON
    var lastChanged: Date?

    var domain: String { String(id.prefix { $0 != "." }) }
    var name: String { attributes["friendly_name"] as? String ?? id }
    var isUnavailable: Bool { state == "unavailable" || state == "unknown" }

    func num(_ key: String) -> Double? {
        if let n = attributes[key] as? NSNumber { return n.doubleValue }
        if let s = attributes[key] as? String { return Double(s) }
        return nil
    }
    func str(_ key: String) -> String? { attributes[key] as? String }
    func list(_ key: String) -> [String] {
        (attributes[key] as? [Any])?.map { "\($0)" } ?? []
    }

    init(id: String, state: String, attributes: JSON, lastChanged: Date? = nil) {
        self.id = id
        self.state = state
        self.attributes = attributes
        self.lastChanged = lastChanged
    }

    init?(_ raw: JSON) {
        guard let id = raw["entity_id"] as? String else { return nil }
        self.id = id
        state = raw["state"] as? String ?? "unknown"
        attributes = raw["attributes"] as? JSON ?? [:]
        lastChanged = (raw["last_changed"] as? String).flatMap(Self.parseDate)
    }

    private static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}

/// What the entity registry adds: which device an entity belongs to, and whether
/// Home Assistant considers it a settings or diagnostics entity we should hide.
struct RegistryEntry {
    var deviceID: String?
    var areaID: String?
    var hidden: Bool
    var category: Int?
}

/// A physical device, from Home Assistant's device registry.
struct DeviceInfo: Identifiable {
    var id: String
    var name: String
    var manufacturer: String?
    var model: String?
    var areaID: String?
    /// Home Assistant's own services (Backup, Sun, HACS) register as devices; they aren't hardware.
    var isService = false
    /// Integration domains from the device registry identifiers, not inferred from its name.
    var integrations: Set<String> = []
}

/// A room, from Home Assistant's area registry.
struct Area: Identifiable, Hashable {
    var id: String
    var name: String
    /// Home Assistant's icon name, such as "mdi:sofa".
    var icon: String?
    var floorID: String?
}

struct Floor: Identifiable, Hashable {
    var id: String
    var name: String
    var level: Int
}

/// Talks to Home Assistant over its WebSocket API and keeps every entity up to date.
@MainActor
final class HomeStore: ObservableObject {
    enum Status: Equatable {
        case needsSetup
        /// Home Assistant turned the token down: it was revoked, mistyped, or a different token.
        case rejected
        case connecting
        case connected
        case failed(String)
    }

    @Published private(set) var entities: [String: Entity] = [:]
    @Published private(set) var registry: [String: RegistryEntry] = [:]
    @Published private(set) var devices: [String: DeviceInfo] = [:]
    @Published private(set) var areas: [String: Area] = [:]
    @Published private(set) var floors: [Floor] = []
    @Published private(set) var status: Status = .connecting
    /// Service calls that haven't come back yet, so the footer can say "Syncing".
    @Published private(set) var inFlight = 0
    /// Service metadata is optional: discovery must never prevent the state feed connecting.
    @Published private(set) var services: JSON?
    /// Legacy callers still receive a visible error; controls with callbacks own their error presentation.
    @Published var actionError: String?
    @Published private(set) var temperatureUnit = "°C"
    /// The latest picture from each camera, so tiles have something to show the moment the panel opens.
    @Published private(set) var snapshots: [String: NSImage] = [:]

    /// Fires for every state change, after `entities` is updated.
    var onStateChange: ((_ new: Entity, _ old: Entity?) -> Void)?
    /// Fires each time a connection finishes loading everything.
    var onConnected: (() -> Void)?

    private var socket: URLSessionWebSocketTask?
    /// The socket once Home Assistant has accepted our sign-in. Commands wait for it: anything
    /// sent before then lands in the sign-in exchange and gets the connection refused.
    private var signedInSocket: URLSessionWebSocketTask?
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<Any?, Error>] = [:]
    /// Event handlers for subscriptions other than the main state feed, keyed by message id.
    private var listeners: [Int: (JSON) -> Void] = [:]
    private var generation = 0
    private var retryDelay: Double = 1

    // MARK: Signing in

    /// A terminal launch can override these with HA_URL and HA_TOKEN, for development.
    var baseURL: URL? {
        let env = ProcessInfo.processInfo.environment["HA_URL"]
        let raw = env ?? UserDefaults.standard.string(forKey: "ha.url") ?? "http://localhost:8123"
        return URL(string: raw.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")))
    }

    /// Home Assistant identifies apps by a URL; the instance's own address is what its
    /// web frontend uses, and needs nothing registered.
    private var clientID: String? { baseURL.map { $0.absoluteString + "/" } }

    /// Signed in, with a long-lived refresh token (or a development token from the terminal).
    var isSignedIn: Bool {
        ProcessInfo.processInfo.environment["HA_TOKEN"] != nil || Keychain.get("ha.refresh") != nil
    }

    private var accessToken: String?
    private var accessExpiry = Date.distantPast

    /// Signs in with the Home Assistant username and password, the way the web page does,
    /// and keeps only the refresh token, which renews access without ever asking again.
    func signIn(url: String, username: String, password: String) async throws {
        UserDefaults.standard.set(url.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "ha.url")
        guard let base = baseURL, let clientID else { throw ProviderError("That address doesn't look right") }

        let flow = try await postJSON(base.appendingPathComponent("auth/login_flow"), [
            "client_id": clientID, "handler": ["homeassistant", NSNull()], "redirect_uri": clientID,
        ])
        guard let flowID = flow["flow_id"] as? String else { throw ProviderError("Home Assistant didn't offer a login") }

        let step = try await postJSON(base.appendingPathComponent("auth/login_flow/\(flowID)"), [
            "client_id": clientID, "username": username.trimmingCharacters(in: .whitespaces), "password": password,
        ])
        if (step["errors"] as? JSON)?["base"] != nil { throw ProviderError("Wrong username or password") }
        if step["step_id"] as? String == "mfa" { throw ProviderError("Two-step login is on for this account, which Hearth can't do yet") }
        guard step["type"] as? String == "create_entry", let code = step["result"] as? String else {
            throw ProviderError("Home Assistant didn't finish the login")
        }

        let tokens = try await postForm(base.appendingPathComponent("auth/token"), [
            "grant_type": "authorization_code", "code": code, "client_id": clientID,
        ])
        guard let refresh = tokens["refresh_token"] as? String else { throw ProviderError("Home Assistant didn't sign Hearth in") }
        Keychain.set(refresh, for: "ha.refresh")
        Keychain.set(nil, for: "ha.token")
        remember(tokens)
        connect()
    }

    func signOut() {
        Keychain.set(nil, for: "ha.refresh")
        Keychain.set(nil, for: "ha.token")
        accessToken = nil
        connect()
    }

    private func remember(_ tokens: JSON) {
        accessToken = tokens["access_token"] as? String
        accessExpiry = Date().addingTimeInterval((tokens["expires_in"] as? Double) ?? 1800)
    }

    /// A current access token, renewed from the refresh token when it's about to run out.
    func validAccessToken() async throws -> String {
        if let dev = ProcessInfo.processInfo.environment["HA_TOKEN"] { return dev }
        if let accessToken, accessExpiry > Date().addingTimeInterval(60) { return accessToken }
        guard let base = baseURL, let clientID, let refresh = Keychain.get("ha.refresh") else {
            throw AuthError.signedOut
        }
        let tokens: JSON
        do {
            tokens = try await postForm(base.appendingPathComponent("auth/token"), [
                "grant_type": "refresh_token", "refresh_token": refresh, "client_id": clientID,
            ])
        } catch let error as HTTPStatusError where error.status == 400 || error.status == 401 {
            throw AuthError.rejected
        }
        remember(tokens)
        guard let accessToken else { throw AuthError.rejected }
        return accessToken
    }

    enum AuthError: Error { case signedOut, rejected }

    // MARK: Connection

    func connect() {
        generation += 1
        let gen = generation
        socket?.cancel(with: .goingAway, reason: nil)
        failPending(ProviderError("Reconnecting"))
        services = nil

        guard let base = baseURL, isSignedIn else {
            status = .needsSetup
            return
        }
        status = .connecting
        Task {
            let token: String
            do {
                token = try await validAccessToken()
            } catch AuthError.signedOut {
                if gen == generation { status = .needsSetup }
                return
            } catch AuthError.rejected {
                if gen == generation { status = .rejected }
                return
            } catch {
                await retry(gen)
                return
            }
            guard gen == generation else { return }
            var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
            comps.scheme = comps.scheme == "https" ? "wss" : "ws"
            comps.path = "/api/websocket"
            let task = URLSession.shared.webSocketTask(with: comps.url!)
            task.maximumMessageSize = 64 * 1024 * 1024
            socket = task
            task.resume()
            await run(task, token: token, gen: gen)
        }
    }

    private func run(_ task: URLSessionWebSocketTask, token: String, gen: Int) async {
        do {
            // auth_required, then our token, then auth_ok.
            _ = try await receiveJSON(task)
            try await sendJSON(["type": "auth", "access_token": token], on: task)
            let reply = try await receiveJSON(task)
            guard reply["type"] as? String == "auth_ok" else {
                status = .rejected
                return
            }
            signedInSocket = task
            Task { await self.loadEverything(gen: gen) }
            while gen == generation {
                handle(try await receiveJSON(task))
            }
        } catch {
            guard gen == generation else { return }
            failPending(error)
            await retry(gen)
        }
    }

    private func retry(_ gen: Int) async {
        status = .failed("Can't reach Home Assistant")
        let delay = retryDelay
        retryDelay = min(retryDelay * 2, 30)
        try? await Task.sleep(for: .seconds(delay))
        if gen == generation { connect() }
    }

    private struct HTTPStatusError: Error { let status: Int }

    private func postJSON(_ url: URL, _ body: JSON) async throws -> JSON {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(req)
    }

    private func postForm(_ url: URL, _ fields: [String: String]) async throws -> JSON {
        var comps = URLComponents()
        comps.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data((comps.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        return try await send(req)
    }

    private func send(_ req: URLRequest) async throws -> JSON {
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw HTTPStatusError(status: status) }
        return (try? JSONSerialization.jsonObject(with: data)) as? JSON ?? [:]
    }

    private func loadEverything(gen: Int) async {
        do {
            if let config = try await command(["type": "get_config"]) as? JSON,
               let unit = (config["unit_system"] as? JSON)?["temperature"] as? String {
                temperatureUnit = unit
            }
            if let list = try await command(["type": "config/entity_registry/list_for_display"]) as? JSON,
               let rows = list["entities"] as? [JSON] {
                var reg: [String: RegistryEntry] = [:]
                for row in rows {
                    guard let id = row["ei"] as? String else { continue }
                    reg[id] = RegistryEntry(
                        deviceID: row["di"] as? String,
                        areaID: row["ai"] as? String,
                        hidden: row["hb"] as? Bool ?? false,
                        category: row["ec"] as? Int
                    )
                }
                registry = reg
            }
            if let rows = try await command(["type": "config/device_registry/list"]) as? [JSON] {
                var found: [String: DeviceInfo] = [:]
                for row in rows {
                    guard let id = row["id"] as? String else { continue }
                    found[id] = DeviceInfo(
                        id: id,
                        name: row["name_by_user"] as? String ?? row["name"] as? String ?? "",
                        manufacturer: row["manufacturer"] as? String,
                        model: row["model"] as? String,
                        areaID: row["area_id"] as? String,
                        isService: row["entry_type"] as? String == "service",
                        integrations: DeviceCommand.integrationDomains(row["identifiers"])
                    )
                }
                devices = found
            }
            if let rows = try? await command(["type": "config/area_registry/list"]) as? [JSON] {
                var found: [String: Area] = [:]
                for row in rows {
                    guard let id = row["area_id"] as? String else { continue }
                    found[id] = Area(id: id, name: row["name"] as? String ?? id,
                                     icon: row["icon"] as? String, floorID: row["floor_id"] as? String)
                }
                areas = found
            }
            if let rows = try? await command(["type": "config/floor_registry/list"]) as? [JSON] {
                floors = rows.compactMap { row in
                    guard let id = row["floor_id"] as? String else { return nil }
                    return Floor(id: id, name: row["name"] as? String ?? id, level: row["level"] as? Int ?? 0)
                }
                .sorted { $0.level > $1.level }
            }
            _ = try await command(["type": "subscribe_events", "event_type": "state_changed"])
            if let states = try await command(["type": "get_states"]) as? [JSON] {
                var all: [String: Entity] = [:]
                for raw in states { if let e = Entity(raw) { all[e.id] = e } }
                entities = all
            }
            guard gen == generation else { return }
            status = .connected
            services = nil
            Task { [weak self] in
                guard let self, let found = try? await self.command(["type": "get_services"]) as? JSON,
                      self.generation == gen else { return }
                self.services = found
            }
            retryDelay = 1
            onConnected?()
        } catch {
            if gen == generation { status = .failed(error.localizedDescription) }
        }
    }

    private func handle(_ msg: JSON) {
        switch msg["type"] as? String {
        case "result":
            guard let id = msg["id"] as? Int, let cont = pending.removeValue(forKey: id) else { return }
            if msg["success"] as? Bool == true {
                cont.resume(returning: msg["result"])
            } else {
                let err = msg["error"] as? JSON
                cont.resume(throwing: ProviderError(err?["message"] as? String ?? "Command failed"))
            }
        case "event":
            if let id = msg["id"] as? Int, let listener = listeners[id] {
                listener(msg["event"] as? JSON ?? [:])
                return
            }
            guard let data = (msg["event"] as? JSON)?["data"] as? JSON,
                  let id = data["entity_id"] as? String else { return }
            let old = entities[id]
            if let raw = data["new_state"] as? JSON, let new = Entity(raw) {
                entities[id] = new
                onStateChange?(new, old)
            } else {
                entities[id] = nil
            }
        default:
            break
        }
    }

    // MARK: Subscriptions

    /// Reload room, floor and device placement after a native setup edit, without
    /// interrupting the connection or any live camera subscriptions.
    func refreshPlaces() async {
        guard !isDemo, status == .connected else { return }
        if let rows = try? await command(["type": "config/area_registry/list"]) as? [JSON] {
            areas = Dictionary(uniqueKeysWithValues: rows.compactMap { row in
                guard let id = row["area_id"] as? String else { return nil }
                return (id, Area(id: id, name: row["name"] as? String ?? id,
                                 icon: row["icon"] as? String, floorID: row["floor_id"] as? String))
            })
        }
        if let rows = try? await command(["type": "config/floor_registry/list"]) as? [JSON] {
            floors = rows.compactMap { row in
                guard let id = row["floor_id"] as? String else { return nil }
                return Floor(id: id, name: row["name"] as? String ?? id, level: row["level"] as? Int ?? 0)
            }.sorted { $0.level > $1.level }
        }
        if let rows = try? await command(["type": "config/device_registry/list"]) as? [JSON] {
            devices = Dictionary(uniqueKeysWithValues: rows.compactMap { row in
                guard let id = row["id"] as? String else { return nil }
                return (id, DeviceInfo(id: id, name: row["name_by_user"] as? String ?? row["name"] as? String ?? "",
                                      manufacturer: row["manufacturer"] as? String, model: row["model"] as? String,
                                      areaID: row["area_id"] as? String, isService: row["entry_type"] as? String == "service",
                                      integrations: DeviceCommand.integrationDomains(row["identifiers"])))
            })
        }
    }

    /// Starts a subscription (WebRTC signalling, logbook streams and the like). Events arrive
    /// on `onEvent` until `unsubscribe` is called with the returned id.
    func subscribe(_ body: JSON, onEvent: @escaping (JSON) -> Void) async throws -> Int {
        let id = nextID
        listeners[id] = onEvent
        do {
            try await command(body, id: id)
        } catch {
            listeners[id] = nil
            throw error
        }
        return id
    }

    func unsubscribe(_ id: Int) {
        guard listeners.removeValue(forKey: id) != nil else { return }
        Task { try? await command(["type": "unsubscribe_events", "subscription": id]) }
    }

    // MARK: Rooms and devices

    /// The room an entity is in: its own area, or else its device's.
    func areaID(of entityID: String) -> String? {
        if let own = registry[entityID]?.areaID { return own }
        return registry[entityID]?.deviceID.flatMap { devices[$0]?.areaID }
    }

    /// Every enabled, visible entity that belongs to a device.
    func entities(ofDevice deviceID: String) -> [Entity] {
        entities.values
            .filter { registry[$0.id]?.deviceID == deviceID && registry[$0.id]?.hidden != true }
            .sorted { $0.id < $1.id }
    }

    /// Devices that have at least one entity, in a room (nil for devices with no room).
    func devices(inArea areaID: String?) -> [DeviceInfo] {
        let withEntities = Set(entities.keys.compactMap { registry[$0]?.deviceID })
        return devices.values
            .filter { withEntities.contains($0.id) && $0.areaID == areaID && !$0.isService }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// A picture from an image entity, such as a camera's last event snapshot.
    func image(_ entityID: String) async -> NSImage? {
        guard !isDemo, let base = baseURL, let token = try? await validAccessToken() else { return nil }
        var req = URLRequest(url: base.appendingPathComponent("api/image_proxy/\(entityID)"))
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let image = NSImage(data: data) else { return nil }
        snapshots[entityID] = image
        return image
    }

    // MARK: Commands

    @discardableResult
    func command(_ body: JSON, id fixedID: Int? = nil) async throws -> Any? {
        if let simulator { return try simulator(body) }
        for _ in 0..<100 where signedInSocket == nil || signedInSocket !== socket {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let socket = signedInSocket, socket === self.socket else { throw ProviderError("Not connected") }
        let id = fixedID ?? nextID
        nextID = max(nextID, id) + 1
        var msg = body
        msg["id"] = id
        return try await withCheckedThrowingContinuation { cont in
            pending[id] = cont
            if body["type"] as? String == "call_service" {
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(30))
                    self?.pending.removeValue(forKey: id)?.resume(throwing: ProviderError("Home Assistant has not confirmed this action. Check the device before retrying."))
                }
            }
            Task {
                do { try await self.sendJSON(msg, on: socket) } catch {
                    self.pending.removeValue(forKey: id)?.resume(throwing: error)
                }
            }
        }
    }

    /// Calls a service and reports whether Home Assistant accepted it. A success is
    /// acknowledgement, not proof of physical playback or a camera changing state.
    func call(_ domain: String, _ service: String, _ entityID: String, _ data: JSON = [:],
              completion: ((Result<Void, Error>) -> Void)? = nil) {
        call(DeviceCommand(domain: domain, service: service, entityID: entityID, data: data), completion: completion)
    }

    func call(_ action: DeviceCommand, completion: ((Result<Void, Error>) -> Void)? = nil) {
        inFlight += 1
        Task {
            defer { inFlight -= 1 }
            do {
                try await command(action.body)
                completion?(.success(()))
            } catch {
                NSLog("Hearth: \(action.domain).\(action.service) failed: \(error.localizedDescription)")
                if completion == nil { actionError = error.localizedDescription }
                completion?(.failure(error))
            }
        }
    }

    func hasService(_ domain: String, _ service: String) -> Bool {
        (services?[domain] as? JSON)?[service] != nil
    }

    /// Shows a change straight away, before Home Assistant confirms it.
    func optimistic(_ id: String, _ change: (inout Entity) -> Void) {
        guard var e = entities[id] else { return }
        change(&e)
        entities[id] = e
    }

    // MARK: Demos

    /// Set only on a store that plays a demo: it never connects to Home Assistant, and every
    /// command it would have sent (service calls included) is answered here instead.
    private(set) var simulator: ((JSON) throws -> Any?)?
    var isDemo: Bool { simulator != nil }

    /// Turns this store into a demo: sample devices, no connection, commands answered locally.
    func playDemo(devices: [DeviceInfo], entities: [Entity], deviceOf: [String: String], areas: [Area] = [], simulator: @escaping (JSON) throws -> Any?) {
        self.simulator = simulator
        self.devices = Dictionary(uniqueKeysWithValues: devices.map { ($0.id, $0) })
        self.entities = Dictionary(uniqueKeysWithValues: entities.map { ($0.id, $0) })
        self.areas = Dictionary(uniqueKeysWithValues: areas.map { ($0.id, $0) })
        registry = Dictionary(uniqueKeysWithValues: entities.map { ($0.id, RegistryEntry(deviceID: deviceOf[$0.id], hidden: false)) })
        status = .connected
    }

    /// The demo's next moment.
    func playDemo(update: [Entity]) {
        guard isDemo else { return }
        for e in update { entities[e.id] = e }
    }

    // MARK: Cameras

    func snapshot(_ entityID: String) async -> NSImage? {
        guard !isDemo, let base = baseURL, let token = try? await validAccessToken() else { return nil }
        var req = URLRequest(url: base.appendingPathComponent("api/camera_proxy/\(entityID)"))
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let image = NSImage(data: data) else { return nil }
        snapshots[entityID] = image
        return image
    }

    /// An HLS address for live video, if the camera supports streaming.
    func streamURL(_ entityID: String) async -> URL? {
        guard let base = baseURL,
              let result = try? await command(["type": "camera/stream", "entity_id": entityID]) as? JSON,
              let path = result["url"] as? String else { return nil }
        return URL(string: path, relativeTo: base)?.absoluteURL
    }

    /// The camera on the same device as an entity, such as the doorbell's own camera.
    func camera(sharingDeviceWith entityID: String) -> Entity? {
        guard let device = registry[entityID]?.deviceID else { return nil }
        return entities.values.first { $0.domain == "camera" && registry[$0.id]?.deviceID == device }
    }

    /// The device an entity belongs to.
    func device(of entityID: String) -> DeviceInfo? {
        registry[entityID]?.deviceID.flatMap { devices[$0] }
    }

    /// Other entities on the same device, such as an AC's energy and filter sensors.
    func siblings(of entityID: String, domain: String) -> [Entity] {
        guard let device = registry[entityID]?.deviceID else { return [] }
        return entities.values
            .filter { $0.domain == domain && $0.id != entityID && registry[$0.id]?.deviceID == device }
            .sorted { $0.id < $1.id }
    }

    // MARK: Plumbing

    private func sendJSON(_ obj: JSON, on task: URLSessionWebSocketTask) async throws {
        let data = try JSONSerialization.data(withJSONObject: obj)
        try await task.send(.string(String(decoding: data, as: UTF8.self)))
    }

    private func receiveJSON(_ task: URLSessionWebSocketTask) async throws -> JSON {
        let message = try await task.receive()
        let data: Data
        switch message {
        case .string(let s): data = Data(s.utf8)
        case .data(let d): data = d
        @unknown default: data = Data()
        }
        return (try JSONSerialization.jsonObject(with: data)) as? JSON ?? [:]
    }

    private func failPending(_ error: Error) {
        let all = pending
        pending.removeAll()
        all.values.forEach { $0.resume(throwing: error) }
    }
}

struct ProviderError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

extension String {
    /// "fan_only" → "Fan only", "auto_low" → "Auto low".
    var pretty: String {
        let s = replacingOccurrences(of: "_", with: " ")
        return s.prefix(1).uppercased() + s.dropFirst()
    }
}
