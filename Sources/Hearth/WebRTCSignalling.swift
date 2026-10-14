import Foundation

/// One WebRTC session with a camera, negotiated through Home Assistant's WebSocket API.
///
/// The flow, as Home Assistant 2026.10 implements it (homeassistant/components/camera/webrtc.py):
/// 1. `camera/webrtc/get_client_config` returns `{configuration: {iceServers}, dataChannel?}`.
/// 2. `camera/webrtc/offer` with the SDP offer is a subscription. Its events are
///    `{type: "session", session_id}` first, then `answer`, `candidate` and `error`.
/// 3. Our own ICE candidates go to `camera/webrtc/candidate`, which needs the session id,
///    so any found before the `session` event are held back until it arrives.
/// 4. Unsubscribing from the offer closes the session at the camera (for Ring, it ends the live view).
@MainActor
final class WebRTCSignalling {
    let entityID: String
    private let store: HomeStore
    private(set) var sessionID: String?
    private var subscription: Int?
    private var heldCandidates: [JSON] = []
    private var closed = false

    /// The camera's SDP answer.
    var onAnswer: ((String) -> Void)?
    /// A remote ICE candidate: `{candidate, sdpMid?, sdpMLineIndex?}`.
    var onCandidate: ((JSON) -> Void)?
    /// Home Assistant or the camera gave up. Ring also says this when it ends a live view.
    var onError: ((String) -> Void)?

    init(store: HomeStore, entityID: String) {
        self.store = store
        self.entityID = entityID
    }

    /// What the camera can stream, such as ["web_rtc", "hls"]. Nil when Home Assistant won't say.
    static func streamTypes(_ store: HomeStore, _ entityID: String) async -> [String]? {
        let result = try? await store.command(["type": "camera/capabilities", "entity_id": entityID]) as? JSON
        return result?["frontend_stream_types"] as? [String]
    }

    /// The ICE servers (and data channel, for cameras that need one) the peer connection should use.
    static func clientConfiguration(_ store: HomeStore, _ entityID: String) async throws -> JSON {
        let result = try await store.command(["type": "camera/webrtc/get_client_config", "entity_id": entityID])
        return result as? JSON ?? [:]
    }

    /// Sends the offer. Answers and candidates arrive on the callbacks until `close`.
    func start(offer: String) async throws {
        let id = try await store.subscribe(["type": "camera/webrtc/offer", "entity_id": entityID, "offer": offer]) { [weak self] event in
            self?.handle(event)
        }
        // The view may have gone while Home Assistant was answering; never leave a session open.
        if closed { store.unsubscribe(id) } else { subscription = id }
    }

    /// One of our ICE candidates, as `RTCIceCandidate.toJSON()` gives it.
    func addLocalCandidate(_ candidate: JSON) {
        guard !closed, let line = candidate["candidate"] as? String, !line.isEmpty else { return }
        // Home Assistant parses exactly these three keys; Ring insists on sdpMLineIndex.
        var clean: JSON = ["candidate": line]
        if let mid = candidate["sdpMid"] as? String { clean["sdpMid"] = mid }
        if let index = candidate["sdpMLineIndex"] as? Int { clean["sdpMLineIndex"] = index }
        if let sessionID { send(clean, session: sessionID) } else { heldCandidates.append(clean) }
    }

    /// Ends the session. Safe to call more than once, and before `start` has finished.
    func close() {
        if !closed { LiveDebug.log("\(entityID) closing session \(sessionID ?? "none"), subscription \(subscription.map(String.init) ?? "none")") }
        closed = true
        heldCandidates.removeAll()
        if let subscription { store.unsubscribe(subscription) }
        subscription = nil
        onAnswer = nil
        onCandidate = nil
        onError = nil
    }

    private func handle(_ event: JSON) {
        guard !closed else { return }
        LiveDebug.log("\(entityID) signalling event: \(event["type"] as? String ?? "?")")
        switch event["type"] as? String {
        case "session":
            guard let id = event["session_id"] as? String else { return }
            sessionID = id
            let held = heldCandidates
            heldCandidates.removeAll()
            held.forEach { send($0, session: id) }
        case "answer":
            if let sdp = event["answer"] as? String { onAnswer?(sdp) }
        case "candidate":
            if let candidate = event["candidate"] as? JSON { onCandidate?(candidate) }
        case "error":
            let message = event["message"] as? String ?? ""
            let code = event["code"] as? String ?? "error"
            onError?(message.isEmpty ? code : "\(message) (\(code))")
        default:
            break
        }
    }

    private func send(_ candidate: JSON, session: String) {
        let body: JSON = ["type": "camera/webrtc/candidate", "entity_id": entityID, "session_id": session, "candidate": candidate]
        Task {
            do { try await store.command(body) } catch {
                NSLog("Hearth: candidate for \(entityID) refused: \(error.localizedDescription)")
            }
        }
    }
}
