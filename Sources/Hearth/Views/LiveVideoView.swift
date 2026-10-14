import AVKit
import SwiftUI
import WebKit

/// Where a live view has got to.
enum LiveState: Equatable {
    case connecting
    /// Frames are arriving. `kind` is "webrtc" or "hls".
    case live(kind: String)
    case fallbackSnapshots
    case failed(String)
}

/// Real-time video from a camera entity. Prefers WebRTC (negotiated through Home Assistant),
/// falls back to Home Assistant's HLS stream, then to a snapshot every two seconds.
/// Everything it opens is closed when it leaves the screen. See docs/live-video.md.
struct LiveVideoView: View {
    @EnvironmentObject var store: HomeStore
    let entityID: String
    var muted = true
    /// True while something drawn by SwiftUI sits over the video, like the pinned title.
    /// Native video views draw above SwiftUI, so the video steps back and its last picture shows.
    var covered = false
    var onState: ((LiveState) -> Void)? = nil
    @StateObject private var model = LiveVideoModel()
    @AppStorage(PrivacyBlur.key) private var privacyBlur = false
    @AppStorage(PrivacyBlur.amountKey) private var blurAmount = 0.45

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            // The last picture stays underneath, so nothing flashes black while video connects.
            if let still = store.snapshots[entityID] {
                Image(nsImage: still).resizable().aspectRatio(contentMode: .fill).privacyBlurred()
                    .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            }
            Group {
                switch model.surface {
                case .webRTC:
                    WebRTCVideo(page: model.page)
                        .opacity(model.state == .live(kind: "webrtc") ? 1 : 0)
                        .animation(.glide, value: model.state)
                case .hls:
                    if let player = model.player { HLSVideo(player: player, blurred: privacyBlur, amount: blurAmount).transition(.opacity) }
                case .snapshots:
                    EmptyView()
                }
            }
            .opacity(covered ? 0 : 1)
            LiveBadge(state: model.state, retrying: model.retrying).padding(12)
        }
        .clipped()
        .task(id: entityID) {
            model.muted = muted
            await model.run(entityID: entityID, store: store)
        }
        .onDisappear { model.stop() }
        .onChange(of: muted) { _, now in model.muted = now }
        .onChange(of: privacyBlur, initial: true) { _, now in model.page.blurred = now }
        .onChange(of: blurAmount, initial: true) { _, now in model.page.blurAmount = now }
        .onChange(of: model.state) { _, now in onState?(now) }
    }
}

// MARK: Model

/// Runs the fallback chain and owns every session it opens.
@MainActor
final class LiveVideoModel: ObservableObject {
    enum Surface { case webRTC, hls, snapshots }

    @Published private(set) var state: LiveState = .connecting
    @Published private(set) var surface: Surface = .webRTC
    @Published private(set) var player: AVPlayer?
    /// Reconnecting after a live view ended, rather than connecting for the first time.
    @Published private(set) var retrying = false
    let page = WebRTCPage()
    var muted = true {
        didSet {
            page.setMuted(muted)
            player?.isMuted = muted
        }
    }

    private var signalling: WebRTCSignalling?
    private var entityID = ""

    /// How long WebRTC has to show a first frame before we move on. Cameras with nothing better
    /// to fall back on (Ring has no HLS) get longer, since a battery doorbell is slow to wake.
    private func firstFrameDeadline(hasHLS: Bool) -> Duration { .seconds(hasHLS ? 15 : 25) }
    /// Automatic reconnects after a live view ends (Ring ends them after a few minutes).
    /// Capped per appearance, so a window left open can't keep a battery camera awake for ever.
    private let maxReconnects = 4
    /// Cameras whose WebRTC never produced a frame, and when. While they have HLS to fall back
    /// on, they skip straight to it for a while instead of waiting out the deadline every time.
    private static var webRTCUnreachable: [String: Date] = [:]

    func run(entityID: String, store: HomeStore) async {
        self.entityID = entityID
        set(.connecting)
        guard await waitForConnection(store) else { return await snapshots(store) }
        let types = await WebRTCSignalling.streamTypes(store, entityID)
        let hasHLS = types?.contains("hls") ?? true
        let recentlyUnreachable = Self.webRTCUnreachable[entityID].map { -$0.timeIntervalSinceNow < 600 } ?? false

        if types?.contains("web_rtc") ?? true, !(hasHLS && recentlyUnreachable), !LiveDebug.skips("webrtc") {
            var reconnects = 0
            var everLive = false
            while !Task.isCancelled {
                surface = .webRTC
                let outcome = await webRTCSession(store, deadline: firstFrameDeadline(hasHLS: hasHLS))
                guard !Task.isCancelled else { return }
                LiveDebug.log("\(entityID) webrtc ended: \(outcome.reason), live for \(Int(outcome.liveFor))s")
                everLive = everLive || outcome.wentLive
                // Never got a frame on the first go: this camera can't do WebRTC from here.
                if !everLive {
                    Self.webRTCUnreachable[entityID] = Date()
                    break
                }
                Self.webRTCUnreachable[entityID] = nil
                reconnects += 1
                if reconnects > maxReconnects { break }
                retrying = true
                set(.connecting)
                try? await Task.sleep(for: .seconds([1.0, 2, 5, 10][min(reconnects - 1, 3)]))
            }
            retrying = false
        }
        guard !Task.isCancelled else { return }

        if hasHLS, !LiveDebug.skips("hls") {
            set(.connecting)
            await hls(store)
        }
        guard !Task.isCancelled else { return }
        await snapshots(store)
    }

    /// Closes everything at once, without waiting for the task to notice it was cancelled.
    func stop() {
        signalling?.close()
        signalling = nil
        page.stop()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }

    private func set(_ new: LiveState) {
        guard state != new else { return }
        state = new
        LiveDebug.log("\(entityID) state: \(new)")
        if case .live(let kind) = new { LiveDebug.captureSoon(kind: kind, model: self) }
    }

    private func waitForConnection(_ store: HomeStore) async -> Bool {
        for _ in 0..<60 where store.status != .connected {
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled { return false }
        }
        return store.status == .connected
    }

    // MARK: WebRTC

    private enum Signal {
        case offer(String), localCandidate(JSON), live, ended(String), timedOut
    }

    private struct Outcome {
        var wentLive: Bool
        var liveFor: TimeInterval
        var reason: String
    }

    /// One WebRTC session, from offer to whatever ends it.
    private func webRTCSession(_ store: HomeStore, deadline limit: Duration) async -> Outcome {
        let config: JSON
        do { config = try await WebRTCSignalling.clientConfiguration(store, entityID) } catch {
            return Outcome(wentLive: false, liveFor: 0, reason: "no client config: \(error.localizedDescription)")
        }
        guard await page.load(), !Task.isCancelled else {
            return Outcome(wentLive: false, liveFor: 0, reason: "page did not load")
        }

        let (signals, feed) = AsyncStream.makeStream(of: Signal.self)
        let session = WebRTCSignalling(store: store, entityID: entityID)
        let page = page
        session.onAnswer = { page.applyAnswer($0) }
        session.onCandidate = { page.addRemoteCandidate($0) }
        session.onError = { feed.yield(.ended($0)) }
        page.onEvent = { event in
            switch event {
            case .offer(let sdp): feed.yield(.offer(sdp))
            case .candidate(let c): feed.yield(.localCandidate(c))
            case .live: feed.yield(.live)
            case .ended(let reason): feed.yield(.ended(reason))
            }
        }
        signalling = session
        let deadline = Task {
            try? await Task.sleep(for: limit)
            feed.yield(.timedOut)
        }
        defer {
            deadline.cancel()
            session.close()
            feed.finish()
            // Leave the page alone if a newer session has already taken it over.
            if signalling === session {
                signalling = nil
                page.stop()
                page.onEvent = nil
            }
        }

        page.start(config: config, muted: muted)
        var liveSince: Date?
        func outcome(_ reason: String) -> Outcome {
            Outcome(wentLive: liveSince != nil, liveFor: liveSince.map { -$0.timeIntervalSinceNow } ?? 0, reason: reason)
        }
        // Iteration ends by itself when the view's task is cancelled.
        for await signal in signals {
            switch signal {
            case .offer(let sdp):
                do { try await session.start(offer: sdp) } catch {
                    return outcome("offer refused: \(error.localizedDescription)")
                }
            case .localCandidate(let candidate):
                session.addLocalCandidate(candidate)
            case .live:
                guard liveSince == nil else { break }
                liveSince = Date()
                deadline.cancel()
                retrying = false
                set(.live(kind: "webrtc"))
            case .timedOut:
                if liveSince == nil { return outcome("no video within \(limit)") }
            case .ended(let reason):
                return outcome(reason)
            }
        }
        return outcome("cancelled")
    }

    // MARK: HLS

    private func hls(_ store: HomeStore) async {
        guard let url = await store.streamURL(entityID), !Task.isCancelled else { return }
        let item = AVPlayerItem(url: url)
        LiveDebug.attach(to: item)
        let player = AVPlayer(playerItem: item)
        player.isMuted = muted
        player.automaticallyWaitsToMinimizeStalling = false
        player.play()
        self.player = player
        surface = .hls
        defer {
            player.pause()
            if self.player === player { self.player = nil }
        }
        var waited = 0.0
        while !Task.isCancelled {
            if item.status == .failed {
                LiveDebug.log("\(entityID) hls failed: \(item.error?.localizedDescription ?? "unknown")")
                return
            }
            if item.status == .readyToPlay, player.timeControlStatus == .playing {
                set(.live(kind: "hls"))
            } else if state != .live(kind: "hls") {
                waited += 0.5
                if waited > 20 { return }
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    // MARK: Snapshots

    private func snapshots(_ store: HomeStore) async {
        surface = .snapshots
        var misses = 0
        while !Task.isCancelled {
            if await store.snapshot(entityID) != nil {
                misses = 0
                set(.fallbackSnapshots)
            } else {
                misses += 1
                if misses >= 3, store.snapshots[entityID] == nil { set(.failed("No picture from this camera")) }
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }
}

// MARK: WebRTC in WebKit

/// A WKWebView holding one `<video>` and an RTCPeerConnection. WebKit does the media;
/// Swift does the signalling with Home Assistant.
@MainActor
final class WebRTCPage: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    enum Event {
        case offer(String), candidate(JSON), live, ended(String)
    }

    let webView: WKWebView
    var onEvent: ((Event) -> Void)?
    private var ready = false
    private var loading = false
    private var waiting: [CheckedContinuation<Bool, Never>] = []
    private var frameWaiters: [CheckedContinuation<NSImage?, Never>] = []

    override init() {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.suppressesIncrementalRendering = true
        // WebKit hides our host ICE candidates from the camera by default, which is right for web
        // pages and wrong for a camera on the same network. Private, so only if it's there.
        let filtering = NSSelectorFromString("_setICECandidateFilteringEnabled:")
        if let method = class_getInstanceMethod(type(of: config.preferences), filtering) {
            typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
            unsafeBitCast(method_getImplementation(method), to: Setter.self)(config.preferences, filtering, false)
        }
        webView = PassiveWebView(frame: .zero, configuration: config)
        super.init()
        webView.configuration.userContentController.add(WeakHandler(self), name: "colima")
        webView.navigationDelegate = self
        webView.underPageBackgroundColor = .black
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = false
    }

    /// Loads the player page once; true when it's ready for `start`.
    func load() async -> Bool {
        if ready { return true }
        if !loading {
            loading = true
            // An https base makes this a secure context; the page itself loads nothing.
            webView.loadHTMLString(Self.html, baseURL: URL(string: "https://colima.localhost/"))
        }
        return await withCheckedContinuation { waiting.append($0) }
    }

    func start(config: JSON, muted: Bool) { call("start", config, muted) }
    func applyAnswer(_ sdp: String) { call("applyAnswer", sdp) }
    func addRemoteCandidate(_ candidate: JSON) { call("addRemoteCandidate", candidate) }
    func setMuted(_ muted: Bool) { call("setMuted", muted) }

    /// Privacy blur on the live video, drawn by the page so it covers the native web view.
    var blurred = false {
        didSet { if blurred != oldValue { applyBlur() } }
    }
    /// Blur strength, 0 to 1; follows the slider while it's dragged.
    var blurAmount = PrivacyBlur.amount {
        didSet { if blurAmount != oldValue, blurred { applyBlur() } }
    }

    private func applyBlur() {
        guard ready else { return }
        let css = blurred ? "blur(\(Int(PrivacyBlur.radius(blurAmount)))px)" : "none"
        let scale = blurred ? "scale(\(1.03 + blurAmount * 0.06))" : "none"
        webView.evaluateJavaScript("document.querySelectorAll('video').forEach(function (v) { v.style.transition = 'filter .35s ease'; v.style.filter = '\(css)'; v.style.transform = '\(scale)'; })")
    }
    func stop() { call("stop") }

    /// The current video frame, drawn to a canvas in the page. For debugging.
    func grabFrame() async -> NSImage? {
        guard ready else { return nil }
        call("grab")
        return await withCheckedContinuation { frameWaiters.append($0) }
    }

    private func call(_ function: String, _ args: Any...) {
        guard ready else { return }
        let encoded = args.map { arg -> String in
            let data = try? JSONSerialization.data(withJSONObject: arg, options: [.fragmentsAllowed])
            return data.map { String(decoding: $0, as: UTF8.self) } ?? "null"
        }
        webView.evaluateJavaScript("void \(function)(\(encoded.joined(separator: ",")))") { _, error in
            if let error { NSLog("Hearth: \(function) failed in the player: \(error.localizedDescription)") }
        }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            ready = true
            applyBlur()
            let all = waiting
            waiting.removeAll()
            all.forEach { $0.resume(returning: true) }
        case "offer":
            if let sdp = body["sdp"] as? String { onEvent?(.offer(sdp)) }
        case "candidate":
            if let candidate = body["candidate"] as? JSON { onEvent?(.candidate(candidate)) }
        case "live":
            applyBlur()
            onEvent?(.live)
        case "ended":
            onEvent?(.ended(body["reason"] as? String ?? "ended"))
        case "frame":
            let image = (body["data"] as? String)
                .flatMap { $0.components(separatedBy: ",").last }
                .flatMap { Data(base64Encoded: $0) }
                .flatMap(NSImage.init(data:))
            let all = frameWaiters
            frameWaiters.removeAll()
            all.forEach { $0.resume(returning: image) }
        case "log":
            LiveDebug.log("player: \(body["message"] as? String ?? "")")
        default:
            break
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failLoad(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failLoad(error) }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        ready = false
        loading = false
        onEvent?(.ended("player process ended"))
    }

    private func failLoad(_ error: Error) {
        NSLog("Hearth: player page failed: \(error.localizedDescription)")
        loading = false
        let all = waiting
        waiting.removeAll()
        all.forEach { $0.resume(returning: false) }
    }

    /// The content controller holds its handlers strongly; this breaks the cycle.
    private final class WeakHandler: NSObject, WKScriptMessageHandler {
        weak var target: WebRTCPage?
        init(_ target: WebRTCPage) { self.target = target }
        func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
            MainActor.assumeIsolated { target?.userContentController(c, didReceive: message) }
        }
    }

    /// The player page. Trickle ICE: the offer goes out at once and candidates follow.
    static let html = #"""
    <!doctype html>
    <html><head><meta charset="utf-8">
    <style>
      html, body { margin: 0; height: 100%; background: #000; overflow: hidden; }
      video { position: fixed; inset: 0; width: 100%; height: 100%; object-fit: cover; background: #000; }
    </style></head>
    <body><video id="v" autoplay playsinline muted></video>
    <script>
    const video = document.getElementById("v");
    const post = (m) => window.webkit.messageHandlers.colima.postMessage(m);
    const log = (message) => post({ type: "log", message: String(message) });
    let pc = null, run = 0, live = false, remoteSet = false, pendingRemote = [];
    let lastBytes = -1, lastAdvance = 0, watchdog = null, dropTimer = null;

    function end(reason) {
      if (!pc) return;
      log("ending: " + reason);
      post({ type: "ended", reason: String(reason) });
      stop();
    }

    function stop() {
      run++;
      live = false; remoteSet = false; pendingRemote = [];
      clearInterval(watchdog); watchdog = null;
      clearTimeout(dropTimer); dropTimer = null;
      if (pc) {
        pc.ontrack = pc.onicecandidate = pc.onconnectionstatechange = pc.oniceconnectionstatechange = null;
        pc.getReceivers().forEach((r) => r.track && r.track.stop());
        pc.close();
        pc = null;
      }
      video.srcObject = null;
    }

    async function checkLive() {
      if (!pc) return;
      const mine = run;
      if (!live && video.videoWidth > 0 && video.currentTime > 0) {
        live = true;
        lastAdvance = Date.now();
        log("first frame " + video.videoWidth + "x" + video.videoHeight);
        post({ type: "live", width: video.videoWidth, height: video.videoHeight });
      }
      if (!live) return;
      // Connected but no video bytes for a while: the camera has stopped sending.
      let bytes = 0;
      try {
        (await pc.getStats()).forEach((r) => { if (r.type === "inbound-rtp" && r.kind === "video") bytes += r.bytesReceived || 0; });
      } catch (err) { return; }
      if (mine !== run) return;
      const now = Date.now();
      if (bytes !== lastBytes) { lastBytes = bytes; lastAdvance = now; }
      if (now - lastAdvance > 10000) end("video stalled");
    }

    async function start(config, muted) {
      stop();
      const mine = run;
      video.muted = muted;
      try {
        pc = new RTCPeerConnection((config && config.configuration) || {});
        if (config && config.dataChannel) pc.createDataChannel(config.dataChannel);
        // Ring wants an audio m-line in the offer as well as video.
        pc.addTransceiver("audio", { direction: "recvonly" });
        pc.addTransceiver("video", { direction: "recvonly" });
        const stream = new MediaStream();
        pc.ontrack = (e) => {
          stream.addTrack(e.track);
          if (video.srcObject !== stream) video.srcObject = stream;
          log("track " + e.track.kind);
          video.play().catch((err) => log("play: " + err));
        };
        pc.onicecandidate = (e) => {
          if (e.candidate && e.candidate.candidate) {
            log("local candidate " + e.candidate.candidate);
            post({ type: "candidate", candidate: e.candidate.toJSON() });
          }
        };
        pc.oniceconnectionstatechange = () => pc && log("ice " + pc.iceConnectionState);
        pc.onconnectionstatechange = () => {
          if (!pc) return;
          const s = pc.connectionState;
          log("connection " + s);
          clearTimeout(dropTimer); dropTimer = null;
          if (s === "failed" || s === "closed") end("connection " + s);
          // A short drop can recover by itself; a long one is the end of the session.
          if (s === "disconnected") dropTimer = setTimeout(() => pc && pc.connectionState !== "connected" && end("connection lost"), 5000);
        };
        const offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        if (mine !== run) return;
        post({ type: "offer", sdp: pc.localDescription.sdp });
        lastBytes = -1; lastAdvance = Date.now();
        watchdog = setInterval(checkLive, 1000);
      } catch (err) {
        if (mine === run) end("offer: " + err);
      }
    }

    async function applyAnswer(sdp) {
      if (!pc || pc.signalingState !== "have-local-offer") return;
      try {
        await pc.setRemoteDescription({ type: "answer", sdp: sdp });
        remoteSet = true;
        const queued = pendingRemote; pendingRemote = [];
        for (const c of queued) await addRemoteCandidate(c);
      } catch (err) { end("answer: " + err); }
    }

    async function addRemoteCandidate(c) {
      if (!pc) return;
      if (!remoteSet) { pendingRemote.push(c); return; }
      // Some providers send neither sdpMid nor an index; the first m-line is the safe guess.
      log("remote candidate " + c.candidate);
      const init = (c.sdpMid || c.sdpMLineIndex != null) ? c : { candidate: c.candidate, sdpMid: "0" };
      try { await pc.addIceCandidate(init); } catch (err) { log("remote candidate: " + err); }
    }

    function setMuted(muted) {
      video.muted = muted;
      if (!muted) video.play().catch((err) => log("unmute: " + err));
    }

    function grab() {
      const canvas = document.createElement("canvas");
      canvas.width = video.videoWidth || 1; canvas.height = video.videoHeight || 1;
      canvas.getContext("2d").drawImage(video, 0, 0, canvas.width, canvas.height);
      post({ type: "frame", data: canvas.toDataURL("image/png") });
    }

    post({ type: "ready", webrtc: typeof RTCPeerConnection !== "undefined" });
    </script></body></html>
    """#
}

/// A web view that never takes the mouse, so clicks reach the SwiftUI around it.
private final class PassiveWebView: WKWebView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct WebRTCVideo: NSViewRepresentable {
    let page: WebRTCPage
    func makeNSView(context: Context) -> WKWebView { page.webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}

private struct HLSVideo: NSViewRepresentable {
    let player: AVPlayer
    var blurred = false
    var amount = PrivacyBlur.amount
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspectFill
        view.player = player
        view.setPrivacyBlur(blurred, amount: amount)
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
        view.setPrivacyBlur(blurred, amount: amount)
    }
}

// MARK: Badge

/// "LIVE" with a pulsing dot, or what's happening instead.
private struct LiveBadge: View {
    let state: LiveState
    let retrying: Bool

    var body: some View {
        HStack(spacing: 6) {
            switch state {
            case .live:
                PulseDot(color: Theme.live, size: 6)
                Text("LIVE").tracking(1.2)
            case .connecting:
                PulseDot(color: Theme.faint, size: 6, period: 1.1)
                Text(retrying ? "Reconnecting…" : "Connecting…")
            case .fallbackSnapshots:
                Circle().fill(Theme.muted).frame(width: 6, height: 6)
                Text("Snapshots")
            case .failed:
                Circle().fill(Theme.faint).frame(width: 6, height: 6)
                Text("Offline")
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.black.opacity(0.45), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.75))
        .animation(.glide, value: state)
    }
}

// MARK: Debugging

/// `Hearth --live <entity_id> [--capture <dir>] [--skip webrtc,hls]` opens a window with only a
/// LiveVideoView, logs every state change, and writes a frame from whichever path went live
/// into the capture folder. `--skip` forces the fallbacks, for testing them.
enum LiveDebug {
    static let enabled = CommandLine.arguments.contains("--live")

    static func value(after flag: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static func skips(_ path: String) -> Bool {
        enabled && (value(after: "--skip")?.split(separator: ",").contains { $0 == path } ?? false)
    }

    static func log(_ message: String) {
        if enabled { NSLog("Hearth live: \(message)") }
    }

    private static var outputs: [ObjectIdentifier: AVPlayerItemVideoOutput] = [:]
    private static weak var lastItem: AVPlayerItem?

    @MainActor static func attach(to item: AVPlayerItem) {
        guard enabled, value(after: "--capture") != nil else { return }
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: nil)
        item.add(output)
        outputs = [ObjectIdentifier(item): output]
        lastItem = item
    }

    @MainActor static func captureSoon(kind: String, model: LiveVideoModel) {
        guard enabled, let dir = value(after: "--capture") else { return }
        Task { @MainActor [weak model] in
            try? await Task.sleep(for: .seconds(4))
            guard let model else { return }
            let folder = URL(fileURLWithPath: dir)
            switch kind {
            case "webrtc":
                let view = model.page.webView
                if let shot = try? await view.takeSnapshot(configuration: nil) { write(shot, folder.appendingPathComponent("webrtc-view.png")) }
                if let frame = await model.page.grabFrame() { write(frame, folder.appendingPathComponent("webrtc-frame.png")) }
            case "hls":
                guard let item = lastItem, let output = outputs[ObjectIdentifier(item)] else { return }
                let time = output.itemTime(forHostTime: CACurrentMediaTime())
                guard let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else {
                    log("hls capture: no frame at \(time.seconds)")
                    return
                }
                let image = CIImage(cvPixelBuffer: buffer)
                let rep = NSCIImageRep(ciImage: image)
                let ns = NSImage(size: rep.size)
                ns.addRepresentation(rep)
                write(ns, folder.appendingPathComponent("hls-frame.png"))
            default:
                break
            }
        }
    }

    private static func write(_ image: NSImage, _ url: URL) {
        guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
        log("wrote \(url.path) (\(Int(image.size.width))x\(Int(image.size.height)))")
    }
}
