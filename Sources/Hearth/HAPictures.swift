import Foundation

/// Credentials belong to the configured Home Assistant origin, never to an artwork host.
enum HAOrigin {
    static func matches(_ lhs: URL, _ rhs: URL) -> Bool {
        guard let a = URLComponents(url: lhs, resolvingAgainstBaseURL: true),
              let b = URLComponents(url: rhs, resolvingAgainstBaseURL: true),
              let scheme = a.scheme?.lowercased(), ["http", "https"].contains(scheme),
              scheme == b.scheme?.lowercased(), let host = a.host?.lowercased(),
              host == b.host?.lowercased(), a.user == nil, a.password == nil,
              b.user == nil, b.password == nil else { return false }
        let defaultPort = scheme == "https" ? 443 : 80
        return (a.port ?? defaultPort) == (b.port ?? defaultPort)
    }

    static func sanitizedRedirect(_ request: URLRequest, origin: URL) -> URLRequest? {
        guard let url = request.url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil else { return nil }
        var safe = request
        if !matches(url, origin) {
            safe.setValue(nil, forHTTPHeaderField: "Authorization")
            safe.setValue(nil, forHTTPHeaderField: "Cookie")
        }
        return safe
    }

    static func javaScriptGuard(for url: URL) -> String? {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let scheme = c.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = c.host?.lowercased(), c.user == nil, c.password == nil else { return nil }
        let hostname = host.hasPrefix("[") ? host : host.contains(":") ? "[\(host)]" : host
        let port = c.port ?? (scheme == "https" ? 443 : 80)
        let origin = "\(scheme)://\(hostname)" + (port == (scheme == "https" ? 443 : 80) ? "" : ":\(port)")
        guard let data = try? JSONEncoder().encode(origin), let literal = String(data: data, encoding: .utf8) else { return nil }
        return "window.location.origin === \(literal)"
    }
}

private final class PictureRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let origin: URL
    init(origin: URL) { self.origin = origin }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(HAOrigin.sanitizedRedirect(request, origin: origin))
    }
}

extension HomeStore {
    /// Keeps external artwork working, without handing its server the home session.
    func pictureData(at path: String, timeout: TimeInterval = 8) async -> Data? {
        let epoch = authenticationGeneration
        guard !isDemo, let base = baseURL,
              let url = URL(string: path, relativeTo: base)?.absoluteURL,
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        if HAOrigin.matches(url, base) {
            guard let token = try? await validAccessToken(), epoch == authenticationGeneration else { return nil }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        guard epoch == authenticationGeneration, !Task.isCancelled else { return nil }
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        let session = URLSession(configuration: config, delegate: PictureRedirects(origin: base), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              epoch == authenticationGeneration, !Task.isCancelled else { return nil }
        return data
    }
}
