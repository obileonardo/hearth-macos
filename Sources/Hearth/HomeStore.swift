import AppKit
import Foundation

typealias JSON = [String: Any]

/// One Home Assistant entity, as the app sees it.
struct Entity: Identifiable {
    let id: String
    var state: String
    var attributes: JSON
    var lastChanged: Date?
    /// Attribute-only updates (temperature/fan) need last_updated, not just state changes.
    var lastUpdated: Date?

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

    init(id: String, state: String, attributes: JSON, lastChanged: Date? = nil, lastUpdated: Date? = nil) {
        self.id = id
        self.state = state
        self.attributes = attributes
        self.lastChanged = lastChanged
        self.lastUpdated = lastUpdated
    }

    init?(_ raw: JSON) {
        guard let id = raw["entity_id"] as? String else { return nil }
        self.id = id
        state = raw["state"] as? String ?? "unknown"
        attributes = raw["attributes"] as? JSON ?? [:]
        lastChanged = (raw["last_changed"] as? String).flatMap(Self.parseDate)
        lastUpdated = (raw["last_updated"] as? String).flatMap(Self.parseDate)
    }

    /// A delayed read must not replace a newer push. Older payloads fall back to
    /// last_changed; an undated incoming snapshot cannot establish freshness.
    func isAtLeastAsRecent(as current: Entity) -> Bool {
        guard let incoming = lastUpdated ?? lastChanged else { return false }
        guard let existing = current.lastUpdated ?? current.lastChanged else { return true }
        return incoming >= existing
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
    private var socketSession: URLSession?
    /// The socket once Home Assistant has accepted our sign-in. Commands wait for it: anything
    /// sent before then lands in the sign-in exchange and gets the connection refused.
    private var signedInSocket: URLSessionWebSocketTask?
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<Any?, Error>] = [:]
    /// Event handlers for subscriptions other than the main state feed, keyed by message id.
    private var listeners: [Int: (JSON) -> Void] = [:]
    private var generation = 0
    private var retryDelay: Double = 1
    private let defaults: UserDefaults
    private let environment: [String: String]
    private let savedServerAtStartup: URL?
    private let authentication: HATokenSession
    private let authenticationTransport: ((URLRequest) async throws -> (Data, URLResponse))?
    private let authenticationConnection: (() -> Void)?
    private var signInAttempt = UUID()
    @Published private(set) var authenticationGeneration = 0
    @Published private(set) var loginConfirmationURL: URL?
    @Published private(set) var signInRecoveryMessage: String?

    init(defaults: UserDefaults = .standard, environment: [String: String] = ProcessInfo.processInfo.environment,
         authentication: HATokenSession? = nil,
         authenticationTransport: ((URLRequest) async throws -> (Data, URLResponse))? = nil,
         authenticationConnection: (() -> Void)? = nil) {
        self.defaults = defaults
        self.environment = environment
        self.authenticationTransport = authenticationTransport
        self.authenticationConnection = authenticationConnection
        savedServerAtStartup = defaults.string(forKey: "ha.url").flatMap(URL.init(string:))
        self.authentication = authentication ?? HATokenSession(vault: .keychain,
            blocked: defaults.bool(forKey: "ha.signedOut") && environment["HA_TOKEN"]?.isEmpty != false)
    }

    // MARK: Signing in

    /// Development overrides are explicit; saved credentials still remain bound
    /// to their issuing origin, independently of the selected endpoint.
    var baseURL: URL? {
        let raw = environment["HA_URL"] ?? defaults.string(forKey: "ha.url") ?? "http://localhost:8123"
        guard let url = URL(string: raw.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))),
              HASessionOrigin.canonical(url) != nil else { return nil }
        return url
    }

    private var developmentAccessToken: String? { environment["HA_TOKEN"].flatMap { $0.isEmpty ? nil : $0 } }

    var isSignedIn: Bool {
        if isDemo { return true }
        return !authentication.blocked && (developmentAccessToken != nil || authentication.hasSavedSignIn)
    }

    /// Sign-in uses a draft address. The live address and old session are only
    /// replaced after the complete new response is securely persisted.
    func signIn(url: String, username: String, password: String) async throws {
        try Task.checkCancellation()
        guard let base = URL(string: url.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))),
              HASessionOrigin.canonical(base) != nil else { throw HASessionError.invalidAddress }
        if environment["HA_URL"] != nil {
            guard let selected = baseURL else { throw HASessionError.invalidAddress }
            guard HAOrigin.matches(base, selected) else {
                throw ProviderError("A development server override is active. Restart without HA_URL to choose another server.")
            }
        }
        let attempt = UUID()
        signInAttempt = attempt
        let clientID = base.absoluteString + "/"
        let flow = try await postJSON(base.appendingPathComponent("auth/login_flow"), [
            "client_id": clientID, "handler": ["homeassistant", NSNull()], "redirect_uri": clientID,
        ])
        try Task.checkCancellation()
        guard signInAttempt == attempt else { throw HASessionError.staleSession }
        guard let flowID = flow["flow_id"] as? String else { throw ProviderError("Home Assistant didn't offer a login") }
        let step = try await postJSON(base.appendingPathComponent("auth/login_flow/\(flowID)"), [
            "client_id": clientID, "username": username.trimmingCharacters(in: .whitespaces), "password": password,
        ])
        try Task.checkCancellation()
        guard signInAttempt == attempt else { throw HASessionError.staleSession }
        if (step["errors"] as? JSON)?["base"] != nil { throw ProviderError("Wrong username or password") }
        if step["step_id"] as? String == "mfa" { throw ProviderError("This Home Assistant account requires an MFA sign-in flow that Hearth does not yet support. Keep MFA enabled.") }
        guard step["type"] as? String == "create_entry", let code = step["result"] as? String else { throw ProviderError("Home Assistant didn't finish the login") }
        let tokens = try await postForm(base.appendingPathComponent("auth/token"), [
            "grant_type": "authorization_code", "code": code, "client_id": clientID,
        ])
        try Task.checkCancellation()
        guard signInAttempt == attempt else { throw HASessionError.staleSession }
        let previousBase = baseURL
        try authentication.commit(tokens, at: base)
        closeConnection(HASessionError.staleSession)
        if previousBase.map({ !HAOrigin.matches($0, base) }) == true {
            // Only discard stale reported memory after a successful, explicit
            // server change; saved homes/maps/devices and credentials are untouched.
            entities = [:]; registry = [:]; devices = [:]; areas = [:]; floors = []
            snapshots = [:]; services = nil
        }
        defaults.set(base.absoluteString, forKey: "ha.url")
        defaults.set(false, forKey: "ha.signedOut")
        loginConfirmationURL = nil
        authenticationGeneration &+= 1
        restartAuthenticationConnection()
    }

    func confirmSavedServer() throws {
        guard let base = baseURL, let confirmation = loginConfirmationURL,
              HAOrigin.matches(base, confirmation) else { throw HASessionError.originMismatch }
        try authentication.confirmLegacy(at: base, savedAtStartup: savedServerAtStartup)
        loginConfirmationURL = nil
        authenticationGeneration &+= 1
        restartAuthenticationConnection()
    }

    func signOut() {
        signInAttempt = UUID()
        defaults.set(true, forKey: "ha.signedOut")
        closeConnection(HASessionError.signedOut)
        authenticationGeneration &+= 1 // Drop the web authority before any Keychain operation.
        do { try authentication.signOut() } catch { actionError = error.localizedDescription }
        loginConfirmationURL = nil
        restartAuthenticationConnection()
    }

    func validAccessToken() async throws -> String {
        guard let base = baseURL else { throw HASessionError.invalidAddress }
        return try await authentication.token(at: base, developmentToken: developmentAccessToken, stillCurrent: {
            self.baseURL.map { HAOrigin.matches($0, base) } == true
        }) { saved in
            do {
                return try await self.postForm(base.appendingPathComponent("auth/token"), [
                    "grant_type": "refresh_token", "refresh_token": saved.refreshToken, "client_id": saved.clientID,
                ])
            } catch let error as HTTPStatusError where error.status == 400 || error.status == 401 {
                throw HASessionError.rejected
            }
        }
    }

    /// A coherent, origin-bound snapshot. Never hand an unrelated legacy refresh
    /// token to WebKit, including when a development access token is supplied.
    func webAuthentication() async throws -> HAWebAuthentication {
        let epoch = authenticationGeneration
        guard let base = baseURL else { throw HASessionError.invalidAddress }
        let access = try await validAccessToken()
        guard epoch == authenticationGeneration, baseURL.map({ HAOrigin.matches($0, base) }) == true,
              !authentication.blocked else { throw HASessionError.staleSession }
        let saved = developmentAccessToken == nil ? try authentication.credential(at: base) : nil
        return HAWebAuthentication(base: base, accessToken: access, refreshToken: saved?.refreshToken,
                                   clientID: saved?.clientID ?? (base.absoluteString + "/"))
    }

    private func restartAuthenticationConnection() {
        if let authenticationConnection { authenticationConnection() } else { connect() }
    }

    // MARK: Connection

    private func closeConnection(_ reason: Error) {
        generation &+= 1
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        socketSession?.invalidateAndCancel()
        socketSession = nil
        failPending(reason)
    }

    func connect() {
        closeConnection(ProviderError("Reconnecting"))
        let gen = generation
        services = nil

        guard let base = baseURL else {
            signInRecoveryMessage = "The configured Home Assistant address is invalid. Your saved sign-in is preserved."
            status = .needsSetup
            return
        }
        do {
            guard !authentication.blocked, try (developmentAccessToken != nil || authentication.savedSignInAvailable()) else {
                status = .needsSetup
                return
            }
        } catch {
            signInRecoveryMessage = error.localizedDescription
            status = .needsSetup
            return
        }
        signInRecoveryMessage = nil
        status = .connecting
        Task {
            let token: String
            do {
                token = try await validAccessToken()
            } catch HASessionError.confirmSavedServer {
                if gen == generation {
                    if let base = baseURL, let savedServerAtStartup, HAOrigin.matches(base, savedServerAtStartup) {
                        loginConfirmationURL = base
                        status = .needsSetup
                    } else { status = .rejected }
                }
                return
            } catch HASessionError.originMismatch {
                if gen == generation { status = .rejected }
                return
            } catch HASessionError.signedOut {
                if gen == generation { status = .needsSetup }
                return
            } catch HASessionError.rejected {
                if gen == generation { status = .rejected }
                return
            } catch {
                await retry(gen)
                return
            }
            guard gen == generation, baseURL.map({ HAOrigin.matches($0, base) }) == true else { return }
            var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
            comps.scheme = comps.scheme?.lowercased() == "https" ? "wss" : "ws"
            comps.path = "/api/websocket"
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = nil
            config.urlCredentialStorage = nil
            config.httpShouldSetCookies = false
            let session = URLSession(configuration: config, delegate: HAWebSocketRedirects(origin: base), delegateQueue: nil)
            socketSession = session
            let task = session.webSocketTask(with: comps.url!)
            task.maximumMessageSize = 64 * 1024 * 1024
            socket = task
            task.resume()
            await run(task, token: token, gen: gen)
        }
    }

    private func run(_ task: URLSessionWebSocketTask, token: String, gen: Int) async {
        do {
            // auth_required, then our token, then auth_ok.
            let first = try await receiveJSON(task)
            guard gen == generation else { return }
            guard let expected = baseURL,
                  HAWebSocketAuthentication.maySend(first: first, currentRequest: task.currentRequest?.url,
                                                    response: task.response?.url, expected: expected) else {
                task.cancel(with: .policyViolation, reason: nil)
                status = .rejected
                return
            }
            try await sendJSON(["type": "auth", "access_token": token], on: task)
            let reply = try await receiveJSON(task)
            guard gen == generation else { return }
            guard reply["type"] as? String == "auth_ok" else {
                task.cancel(with: .policyViolation, reason: nil)
                status = .rejected
                return
            }
            signedInSocket = task
            Task { await self.loadEverything(gen: gen) }
            while gen == generation {
                let message = try await receiveJSON(task)
                guard gen == generation else { return }
                handle(message)
            }
        } catch {
            guard gen == generation else { return }
            failPending(error)
            await retry(gen)
        }
    }

    private func retry(_ gen: Int) async {
        guard gen == generation else { return }
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
        let data: Data
        let response: URLResponse
        if let authenticationTransport {
            (data, response) = try await authenticationTransport(req)
        } else {
            guard let origin = req.url, HASessionOrigin.canonical(origin) != nil else { throw HASessionError.invalidAddress }
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = nil
            config.urlCredentialStorage = nil
            config.httpShouldSetCookies = false
            let session = URLSession(configuration: config, delegate: HAAuthenticationRedirects(origin: origin), delegateQueue: nil)
            defer { session.finishTasksAndInvalidate() }
            (data, response) = try await session.data(for: req)
        }
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
        let epoch = authenticationGeneration
        guard !isDemo, let base = baseURL,
              let data = await pictureData(at: base.appendingPathComponent("api/image_proxy/\(entityID)").absoluteString, timeout: 15),
              epoch == authenticationGeneration,
              let image = NSImage(data: data) else { return nil }
        snapshots[entityID] = image
        return image
    }

    // MARK: Commands

    private let climateCommands = ClimateCommandQueue()

    @discardableResult
    func command(_ body: JSON, id fixedID: Int? = nil, authenticationEpoch: Int? = nil) async throws -> Any? {
        let session = CommandSession(generation: authenticationEpoch ?? authenticationGeneration)
        try Task.checkCancellation()
        try session.check(current: authenticationGeneration)
        if let simulator { return try simulator(body) }
        if let key = ClimateCommandScope.key(for: body, registry: registry, entities: entities) {
            return try await climateCommands.run(key: key) { [self] in
                try await sendCommand(body, id: fixedID, session: session)
            }
        }
        return try await sendCommand(body, id: fixedID, session: session)
    }

    /// Reconnects within one sign-in remain valid. A queued action never gains
    /// authority from a later sign-in or server, even with matching entity IDs.
    private func sendCommand(_ body: JSON, id fixedID: Int? = nil, session: CommandSession) async throws -> Any? {
        try await session.waitForConnection(current: { self.authenticationGeneration },
                                            connected: { self.signedInSocket != nil && self.signedInSocket === self.socket },
                                            pause: { try await Task.sleep(for: .milliseconds(100)) })
        try session.check(current: authenticationGeneration)
        guard let socket = signedInSocket, socket === self.socket else { throw ProviderError("Not connected") }
        let id = fixedID ?? nextID
        nextID = max(nextID, id) + 1
        var msg = body
        msg["id"] = id
        let result: Any? = try await withCheckedThrowingContinuation { cont in
            pending[id] = cont
            if body["type"] as? String == "call_service" {
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(30))
                    self?.pending.removeValue(forKey: id)?.resume(throwing: ProviderError("Home Assistant has not confirmed this action. Check the device before retrying."))
                }
            }
            Task {
                do {
                    try session.check(current: self.authenticationGeneration)
                    guard socket === self.socket, socket === self.signedInSocket else { throw ProviderError("Not connected") }
                    try await self.sendJSON(msg, on: socket)
                } catch {
                    self.pending.removeValue(forKey: id)?.resume(throwing: error)
                }
            }
        }
        try session.check(current: authenticationGeneration)
        return result
    }

    /// Read one entity out of HA's snapshot, retaining a newer state_changed push.
    /// Demo refreshes remain in memory and a failed read never invents a rollback.
    @discardableResult
    func refreshEntity(_ entityID: String, authenticationEpoch: Int? = nil) async -> Entity? {
        let session = CommandSession(generation: authenticationEpoch ?? authenticationGeneration)
        guard (try? session.check(current: authenticationGeneration)) != nil else { return nil }
        if isDemo { return entities[entityID] }
        guard signedInSocket != nil, signedInSocket === socket,
              let rows = try? await command(["type": "get_states"], authenticationEpoch: session.generation) as? [JSON],
              (try? session.check(current: authenticationGeneration)) != nil,
              let raw = rows.first(where: { $0["entity_id"] as? String == entityID }),
              let fresh = Entity(raw) else { return nil }
        let current = entities[entityID]
        if let current, !fresh.isAtLeastAsRecent(as: current) { return current }
        entities[entityID] = fresh
        // A read is reconciliation, not a new event. Comparing it with a legacy
        // optimistic value could fabricate an Activity/Live pill transition.
        return fresh
    }

    /// Calls a service and reports whether Home Assistant accepted it. A success is
    /// acknowledgement, not proof of physical playback or a camera changing state.
    func call(_ domain: String, _ service: String, _ entityID: String, _ data: JSON = [:],
              completion: ((Result<Void, Error>) -> Void)? = nil) {
        call(DeviceCommand(domain: domain, service: service, entityID: entityID, data: data), completion: completion)
    }

    func call(_ action: DeviceCommand, completion: ((Result<Void, Error>) -> Void)? = nil) {
        let session = CommandSession(generation: authenticationGeneration)
        inFlight += 1
        Task {
            defer { inFlight -= 1 }
            do {
                try await CommandReconciliation.perform(action, send: {
                    _ = try await self.command($0.body, authenticationEpoch: session.generation)
                }, refresh: {
                    await self.refreshEntity($0, authenticationEpoch: session.generation)
                })
                try session.check(current: self.authenticationGeneration)
                completion?(.success(()))
            } catch {
                NSLog("Hearth: \(action.domain).\(action.service) failed: \(error.localizedDescription)")
                if completion == nil, session.generation == self.authenticationGeneration { actionError = error.localizedDescription }
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
    func playDemo(devices: [DeviceInfo], entities: [Entity], deviceOf: [String: String], areas: [Area] = [], floors: [Floor] = [], simulator: @escaping (JSON) throws -> Any?) {
        self.simulator = simulator
        self.devices = Dictionary(uniqueKeysWithValues: devices.map { ($0.id, $0) })
        self.entities = Dictionary(uniqueKeysWithValues: entities.map { ($0.id, $0) })
        self.areas = Dictionary(uniqueKeysWithValues: areas.map { ($0.id, $0) })
        self.floors = floors
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
        let epoch = authenticationGeneration
        guard !isDemo, let base = baseURL,
              let data = await pictureData(at: base.appendingPathComponent("api/camera_proxy/\(entityID)").absoluteString, timeout: 15),
              epoch == authenticationGeneration,
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
