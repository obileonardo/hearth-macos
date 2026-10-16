import SwiftUI
import WebKit
import Combine

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

            WebView(view: web.view).id(ObjectIdentifier(web.view))
        }
        .frame(minWidth: 760, minHeight: 520)
        .navigationTitle("Home Assistant")
        .task(id: store.authenticationGeneration) {
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
    @Published private(set) var view: WKWebView
    private var base: URL?
    private var authenticationChanges: AnyCancellable?
    private weak var boundStore: HomeStore?
    private var loadGeneration = 0

    private static func makeView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        return WKWebView(frame: .zero, configuration: config)
    }

    override init() {
        view = Self.makeView()
        super.init()
        view.navigationDelegate = self
        view.allowsBackForwardNavigationGestures = true
    }

    /// Replacing the entire ephemeral view drops its token store, document and
    /// scripts. A stale async load cannot reinstall the old authority afterward.
    func invalidate() {
        loadGeneration &+= 1
        base = nil
        canGoBack = false; canGoForward = false; loading = false; path = ""
        let previous = view
        previous.stopLoading()
        previous.navigationDelegate = nil
        previous.configuration.userContentController.removeAllUserScripts()
        previous.loadHTMLString("", baseURL: nil)
        previous.configuration.websiteDataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {}
        view = Self.makeView()
        view.navigationDelegate = self
        view.allowsBackForwardNavigationGestures = true
    }

    func load(_ store: HomeStore, path: String = "") async {
        if boundStore !== store {
            if boundStore != nil { invalidate() }
            boundStore = store
            authenticationChanges = store.$authenticationGeneration.dropFirst().sink { [weak self] _ in self?.invalidate() }
        }
        let epoch = loadGeneration
        let authEpoch = store.authenticationGeneration
        guard let auth = try? await store.webAuthentication(),
              !Task.isCancelled, epoch == loadGeneration,
              authEpoch == store.authenticationGeneration else { return }
        let base = auth.base
        var tokens: JSON = ["hassUrl": base.absoluteString, "clientId": auth.clientID,
                            "token_type": "Bearer", "access_token": auth.accessToken,
                            "expires_in": 1800, "expires": Int(Date().addingTimeInterval(1700).timeIntervalSince1970 * 1000)]
        if let refresh = auth.refreshToken { tokens["refresh_token"] = refresh }
        guard let data = try? JSONSerialization.data(withJSONObject: tokens),
              let json = String(data: data, encoding: .utf8),
              let originGuard = HAOrigin.javaScriptGuard(for: base) else { return }
        let literal = (try? JSONSerialization.data(withJSONObject: [json], options: [.fragmentsAllowed]))
            .flatMap { String(data: $0, encoding: .utf8) }.map { String($0.dropFirst().dropLast()) } ?? "\"\""
        let script = "if (\(originGuard)) { try { localStorage.setItem('hassTokens', \(literal)); } catch (e) {} }"
        view.configuration.userContentController.removeAllUserScripts()
        view.configuration.userContentController.addUserScript(
            WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        self.base = base
        open(path)
    }

    func open(_ path: String) {
        guard let base else { return }
        let url = path.isEmpty ? base : URL(string: path, relativeTo: base.appendingPathComponent("/")) ?? base
        view.load(URLRequest(url: url))
    }

    nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Task { @MainActor in if self.view === webView { self.update(loading: true) } }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in if self.view === webView { self.update(loading: false) } }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in if self.view === webView { self.update(loading: false) } }
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
