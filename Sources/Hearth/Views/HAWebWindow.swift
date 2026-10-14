import SwiftUI
import WebKit

/// Home Assistant's own web interface in a window, for everything Hearth doesn't draw natively:
/// automations, dashboards, logs. It's signed in with Hearth's session, so there's no login page.
struct HAWebWindow: View {
    @EnvironmentObject var store: HomeStore
    @StateObject private var web = HAWebModel()

    private static let shortcuts: [(title: String, symbol: String, path: String)] = [
        ("Overview", "house", "lovelace/0"),
        ("Integrations", "puzzlepiece.extension", "config/integrations/dashboard"),
        ("Devices", "cpu", "config/devices/dashboard"),
        ("Automations", "wand.and.stars", "config/automation/dashboard"),
        ("Logs", "doc.text.magnifyingglass", "config/logs"),
        ("Settings", "gearshape", "config/dashboard"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                toolbarButton("chevron.left", "Back", enabled: web.canGoBack) { web.view.goBack() }
                toolbarButton("chevron.right", "Forward", enabled: web.canGoForward) { web.view.goForward() }
                toolbarButton("arrow.clockwise", "Reload", enabled: true) { web.view.reload() }
                Divider().frame(height: 18).padding(.horizontal, 4)
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(Self.shortcuts, id: \.path) { s in
                            Button { web.open(s.path) } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: s.symbol).font(.system(size: 12))
                                    Text(s.title).font(.system(size: 13, weight: .medium))
                                }
                                .padding(.horizontal, 10).frame(height: 28)
                                .background(Capsule().fill(Theme.ink.opacity(web.path.hasPrefix(s.path) ? 0.12 : 0.05)))
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                }
                .scrollIndicators(.never)
                if web.loading { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 12)
            .frame(height: 46)
            .foregroundStyle(Theme.ink)
            .background(Theme.base)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }

            WebView(view: web.view)
        }
        .frame(minWidth: 760, minHeight: 520)
        .navigationTitle("Home Assistant")
        .task {
            // Another screen can ask for a particular page, such as a setup flow to finish here.
            let next = UserDefaults.standard.string(forKey: "haWeb.next") ?? ""
            UserDefaults.standard.removeObject(forKey: "haWeb.next")
            await web.load(store, path: next)
        }
    }

    private func toolbarButton(_ symbol: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium)).frame(width: 30, height: 28)
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Owns the web view and signs it in.
@MainActor
final class HAWebModel: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var loading = false
    @Published var path = ""
    let view: WKWebView
    private var base: URL?

    override init() {
        let config = WKWebViewConfiguration()
        // Nothing is kept on disk: the session is handed over fresh each time the window opens.
        config.websiteDataStore = .nonPersistent()
        view = WKWebView(frame: .zero, configuration: config)
        super.init()
        view.navigationDelegate = self
        view.allowsBackForwardNavigationGestures = true
    }

    /// Signs the page in the way Home Assistant's frontend remembers a login: it reads `hassTokens`
    /// from local storage. The client id must be the one the tokens were issued to, which is the
    /// server's own address, the same as Hearth's sign-in uses.
    func load(_ store: HomeStore, path: String = "") async {
        guard let base = store.baseURL else { return }
        self.base = base
        let origin = base.absoluteString
        var tokens: JSON = ["hassUrl": origin, "clientId": origin + "/", "token_type": "Bearer"]
        if let access = try? await store.validAccessToken() {
            tokens["access_token"] = access
            tokens["expires_in"] = 1800
            tokens["expires"] = Int(Date().addingTimeInterval(1700).timeIntervalSince1970 * 1000)
        }
        if let refresh = Keychain.get("ha.refresh") { tokens["refresh_token"] = refresh }
        if tokens["access_token"] != nil,
           let data = try? JSONSerialization.data(withJSONObject: tokens),
           let json = String(data: data, encoding: .utf8) {
            let literal = (try? JSONSerialization.data(withJSONObject: [json], options: [.fragmentsAllowed]))
                .flatMap { String(data: $0, encoding: .utf8) }.map { String($0.dropFirst().dropLast()) } ?? "\"\""
            guard let originGuard = HAOrigin.javaScriptGuard(for: base) else { return }
            let script = "if (\(originGuard)) { try { localStorage.setItem('hassTokens', \(literal)); } catch (e) {} }"
            view.configuration.userContentController.removeAllUserScripts()
            view.configuration.userContentController.addUserScript(
                WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        open(path)
    }

    func open(_ path: String) {
        guard let base else { return }
        let url = path.isEmpty ? base : URL(string: path, relativeTo: base.appendingPathComponent("/")) ?? base
        view.load(URLRequest(url: url))
    }

    nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Task { @MainActor in self.update(loading: true) }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.update(loading: false) }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.update(loading: false) }
    }

    private func update(loading: Bool) {
        self.loading = loading
        canGoBack = view.canGoBack
        canGoForward = view.canGoForward
        path = view.url?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
    }
}

/// Hosts a WKWebView in SwiftUI.
private struct WebView: NSViewRepresentable {
    let view: WKWebView
    func makeNSView(context: Context) -> WKWebView { view }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
