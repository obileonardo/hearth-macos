import Foundation

/// One atomic Keychain record binds a refresh credential and its client ID to
/// the server that issued it. Never infer that binding from a newly edited URL.
struct HASavedSession: Codable, Equatable {
    let origin: String
    let clientID: String
    let refreshToken: String
}

enum HASessionError: LocalizedError, Equatable {
    case signedOut, rejected, invalidAddress, originMismatch, confirmSavedServer, staleSession, invalidResponse, invalidStoredSession
    var errorDescription: String? {
        switch self {
        case .signedOut: "Sign in to Home Assistant."
        case .rejected: "Home Assistant rejected the saved sign-in."
        case .invalidAddress: "Enter an HTTP or HTTPS Home Assistant address without embedded credentials."
        case .originMismatch: "The saved sign-in belongs to a different server. Sign in to the selected server."
        case .confirmSavedServer: "Confirm your saved Home Assistant server before using the existing sign-in."
        case .staleSession: "The sign-in changed while this request was running."
        case .invalidResponse: "Home Assistant did not return a complete sign-in response."
        case .invalidStoredSession: "The saved secure sign-in could not be read. Its existing data has been preserved."
        }
    }
}

enum HASessionOrigin {
    static func canonical(_ url: URL) -> String? {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let scheme = c.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = c.host?.lowercased(), !host.isEmpty,
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil else { return nil }
        let hostname = host.hasPrefix("[") ? host : host.contains(":") ? "[\(host)]" : host
        let port = c.port ?? (scheme == "https" ? 443 : 80)
        guard (1...65535).contains(port) else { return nil }
        return "\(scheme)://\(hostname)" + (port == (scheme == "https" ? 443 : 80) ? "" : ":\(port)")
    }

    static func permits(_ session: HASavedSession, at url: URL) -> Bool {
        guard let origin = canonical(url), session.origin == origin,
              let client = URL(string: session.clientID), canonical(client) == origin,
              !session.refreshToken.isEmpty else { return false }
        return true
    }
}

/// Injected storage/transport keep authentication tests away from the real
/// Keychain, UserDefaults, Home Assistant and physical devices.
@MainActor
final class HATokenSession {
    struct Vault {
        var load: () throws -> HASavedSession?
        var legacy: () throws -> String?
        var save: (HASavedSession) throws -> Void
        var clear: () throws -> Void

        static var keychain: Vault {
            Vault(load: {
                guard let text = try Keychain.read("ha.session") else { return nil }
                guard let data = text.data(using: .utf8),
                      let value = try? JSONDecoder().decode(HASavedSession.self, from: data) else {
                    throw HASessionError.invalidStoredSession
                }
                return value
            }, legacy: { try Keychain.read("ha.refresh") }, save: { value in
                let text = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
                try Keychain.write(text, for: "ha.session")
            }, clear: {
                // Explicit sign-out only. An upgrade or failed sign-in never deletes credentials.
                var first: Error?
                for key in ["ha.session", "ha.refresh", "ha.token"] {
                    do { try Keychain.write(nil, for: key) } catch { if first == nil { first = error } }
                }
                if let first { throw first }
            })
        }
    }

    private struct Access {
        let token: String
        let origin: String
        let expiry: Date
    }
    private let vault: Vault
    private var cached: Access?
    private(set) var generation = 0
    private(set) var blocked: Bool

    init(vault: Vault, blocked: Bool = false) { self.vault = vault; self.blocked = blocked }

    var hasSavedSignIn: Bool {
        guard !blocked else { return false }
        return (try? savedSignInAvailable()) == true
    }

    func savedSignInAvailable() throws -> Bool {
        guard !blocked else { return false }
        if try vault.load() != nil { return true }
        return try vault.legacy() != nil
    }

    func credential(at base: URL) throws -> HASavedSession {
        guard !blocked else { throw HASessionError.signedOut }
        guard let value = try vault.load() else {
            if try vault.legacy() != nil { throw HASessionError.confirmSavedServer }
            throw HASessionError.signedOut
        }
        guard HASessionOrigin.permits(value, at: base) else { throw HASessionError.originMismatch }
        return value
    }

    /// The user confirms this address locally. Existing raw credentials are kept
    /// intact for recovery; no request is sent until the new bound record saves.
    func confirmLegacy(at base: URL, savedAtStartup: URL?) throws {
        guard !blocked, let savedAtStartup,
              let origin = HASessionOrigin.canonical(base),
              HASessionOrigin.canonical(savedAtStartup) == origin else { throw HASessionError.originMismatch }
        if try vault.load() != nil { _ = try credential(at: base); return }
        guard let legacy = try vault.legacy(), !legacy.isEmpty else { throw HASessionError.signedOut }
        try vault.save(HASavedSession(origin: origin, clientID: base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/", refreshToken: legacy))
        invalidate()
    }

    func token(at base: URL, developmentToken: String?, stillCurrent: () -> Bool = { true },
               refresh: (HASavedSession) async throws -> JSON) async throws -> String {
        try Task.checkCancellation()
        guard !blocked else { throw HASessionError.signedOut }
        guard let origin = HASessionOrigin.canonical(base) else { throw HASessionError.invalidAddress }
        guard stillCurrent() else { throw HASessionError.staleSession }
        // A developer explicitly supplies this credential for this invocation's
        // endpoint. It never authorizes reuse of a saved token at another origin.
        if let developmentToken, !developmentToken.isEmpty { return developmentToken }
        let saved = try credential(at: base)
        if let cached, cached.origin == origin, cached.expiry > Date().addingTimeInterval(60) { return cached.token }
        let epoch = generation
        let tokens = try await refresh(saved)
        try Task.checkCancellation()
        guard generation == epoch, !blocked, stillCurrent() else { throw HASessionError.staleSession }
        let access = try Self.access(tokens, origin: origin)
        cached = access
        return access.token
    }

    func commit(_ tokens: JSON, at base: URL) throws {
        guard let origin = HASessionOrigin.canonical(base),
              let refresh = tokens["refresh_token"] as? String, !refresh.isEmpty else { throw HASessionError.invalidResponse }
        let access = try Self.access(tokens, origin: origin)
        let value = HASavedSession(origin: origin, clientID: base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/", refreshToken: refresh)
        try vault.save(value) // Save first: a failed write preserves the current session/cache.
        invalidate()
        blocked = false
        cached = access
    }

    func signOut() throws {
        blocked = true
        invalidate() // Invalidate before storage cleanup, including on a Keychain failure.
        try vault.clear()
    }

    private func invalidate() { generation &+= 1; cached = nil }
    private static func access(_ tokens: JSON, origin: String) throws -> Access {
        guard let token = tokens["access_token"] as? String, !token.isEmpty else { throw HASessionError.invalidResponse }
        let duration = (tokens["expires_in"] as? NSNumber)?.doubleValue ?? 1800
        guard duration.isFinite, duration > 0 else { throw HASessionError.invalidResponse }
        return Access(token: token, origin: origin, expiry: Date().addingTimeInterval(min(duration, 86400)))
    }
}

struct HAWebAuthentication {
    let base: URL
    let accessToken: String
    let refreshToken: String?
    let clientID: String
}

/// Auth POST bodies can contain passwords or refresh tokens. Never follow them
/// to another origin, even if the server responds with a body-preserving redirect.
final class HAAuthenticationRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let origin: URL
    init(origin: URL) { self.origin = origin }
    static func allowed(_ target: URL, from origin: URL) -> Bool { HAOrigin.matches(target, origin) }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map { Self.allowed($0, from: origin) } == true ? request : nil)
    }
}

/// WebSocket handshakes may redirect before the HA auth message is sent.
/// Normalize transport schemes to the corresponding HTTP origin for comparison.
enum HAWebSocketAuthentication {
    static func matches(_ url: URL, expected: URL) -> Bool {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return false }
        switch parts.scheme?.lowercased() {
        case "ws": parts.scheme = "http"
        case "wss": parts.scheme = "https"
        case "http", "https": break
        default: return false
        }
        return parts.url.map { HAOrigin.matches($0, expected) } == true
    }
    static func maySend(first: JSON, currentRequest: URL?, response: URL?, expected: URL) -> Bool {
        guard first["type"] as? String == "auth_required", let currentRequest,
              matches(currentRequest, expected: expected) else { return false }
        return response.map { matches($0, expected: expected) } ?? true
    }
}

final class HAWebSocketRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let origin: URL
    init(origin: URL) { self.origin = origin }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map { HAWebSocketAuthentication.matches($0, expected: origin) } == true ? request : nil)
    }
}
