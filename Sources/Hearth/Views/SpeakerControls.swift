import SwiftUI

/// One transport policy across the grid, list and device detail. Idle Alexa
/// devices start music on that device; other integrations ask what to play.
struct SpeakerPlayButton: View {
    @EnvironmentObject private var store: HomeStore
    let entity: Entity
    var size: CGFloat = 28
    var prominent = false
    @State private var choosing = false
    @State private var pending = false
    @State private var failure: String?
    @State private var acknowledged = false
    @State private var waitingForPlayback = false
    @State private var requestID = UUID()

    private var service: String? { SpeakerAction.primaryService(entity) }
    private var symbol: String { service == "media_pause" ? "pause.fill" : service == "media_stop" ? "stop.fill" : "play.fill" }
    private var title: String { service == "media_pause" ? "Pause" : service == "media_stop" ? "Stop" : entity.state == "paused" ? "Resume" : "Play music" }
    private var alexa: DeviceCommand? {
        store.registry[entity.id]?.deviceID.flatMap { store.devices[$0] }.flatMap {
            DeviceCommand.alexaMusic($0, available: store.hasService("alexa_devices", "send_text_command"), query: "")
        }
    }

    var body: some View {
        Button {
            if let service {
                send(DeviceCommand(domain: "media_player", service: service, entityID: entity.id))
            } else if entity.state != "playing", let alexa {
                send(alexa)
            } else {
                choosing = true
            }
        } label: {
            ZStack {
                if pending || waitingForPlayback { ProgressView().controlSize(.mini) }
                else { Image(systemName: symbol).font(.system(size: size > 32 ? 15 : 11.5)) }
            }
            .foregroundStyle(prominent ? Theme.onCTA : Theme.ink)
            .frame(width: size, height: size)
            .background(Circle().fill(prominent ? Theme.cta : Theme.fg.opacity(0.07)))
        }
        .buttonStyle(PressStyle()).disabled(pending || waitingForPlayback || entity.isUnavailable)
        .accessibilityLabel(waitingForPlayback ? "Waiting for playback on \(entity.name)" : "\(title) on \(entity.name)")
        .help(acknowledged ? "Home Assistant accepted the request. Playback appears when the speaker reports it." : title)
        .onChange(of: entity.state) { _, state in
            if state == "playing" { waitingForPlayback = false }
        }
        .contextMenu { Button("Choose music…") { choosing = true } }
        .popover(isPresented: $choosing, arrowEdge: .bottom) {
            SpeakerMusicComposer(entity: entity).environmentObject(store)
        }
        .alert("Speaker action needs attention", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK") { failure = nil }
        } message: { Text(failure ?? "") }
    }

    private func send(_ action: DeviceCommand) {
        pending = true
        acknowledged = false
        let token = UUID()
        requestID = token
        let startsPlayback = action.service == "media_play" || action.service == "play_media" || action.domain == "alexa_devices"
        store.call(action) { result in
            guard requestID == token else { return }
            pending = false
            switch result {
            case .success:
                acknowledged = true
                guard startsPlayback, store.entities[entity.id]?.state != "playing" else { return }
                waitingForPlayback = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(30))
                    guard requestID == token, waitingForPlayback else { return }
                    waitingForPlayback = false
                    failure = "Home Assistant accepted the request, but the speaker has not reported playback. Check its music provider, account and connection before retrying."
                }
            case .failure(let error): failure = error.localizedDescription
            }
        }
    }

}

struct SpeakerMusicComposer: View {
    @EnvironmentObject private var store: HomeStore
    let entity: Entity
    @State private var content = ""
    @State private var contentType = "music"
    @State private var pending = false
    @State private var status: String?
    @State private var failed = false

    private var device: DeviceInfo? { store.registry[entity.id]?.deviceID.flatMap { store.devices[$0] } }
    private var alexa: DeviceCommand? {
        device.flatMap { DeviceCommand.alexaMusic($0, available: store.hasService("alexa_devices", "send_text_command"), query: content) }
    }
    private var action: DeviceCommand? { alexa ?? DeviceCommand.media(entity, content: content, type: contentType) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Play on \(entity.name)", systemImage: "music.note")
                .font(.system(size: 14, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            HearthField(label: alexa != nil ? "Song, artist or station" : "Media address or identifier",
                        placeholder: alexa != nil ? "Leave empty to play music" : "A stream URL or media identifier",
                        text: $content, onSubmit: play)
            if alexa == nil {
                HearthField(label: "Media type or provider", placeholder: "music", text: $contentType, onSubmit: play)
                Text("Use a media identifier and type supported by this speaker’s Home Assistant integration.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Alexa uses the music provider linked to this device. Availability depends on your account and region.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            if !entity.list("source_list").isEmpty, SpeakerAction.supports(entity, feature: 2048) {
                Button {
                    PopupMenu.show(entity.list("source_list"), selected: entity.str("source")) { source in
                        send(DeviceCommand(domain: "media_player", service: "select_source", entityID: entity.id, data: ["source": source]))
                    }
                } label: { Label("Choose source", systemImage: "list.bullet") }
                .buttonStyle(PressStyle()).disabled(pending)
            }
            if let status {
                Text(status).font(.system(size: 11.5)).foregroundStyle(failed ? Theme.live : Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button(pending ? "Requesting…" : "Play music", action: play)
                    .buttonStyle(PressStyle()).font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.onCTA).padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(Theme.cta)).disabled(pending || action == nil)
            }
            if !SpeakerAction.supports(entity, feature: 512), alexa == nil {
                Text("This integration does not expose a way to start new music. Existing playback controls remain available.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18).frame(width: 300).foregroundStyle(Theme.ink).background(Theme.base)
    }

    private func play() { if let action, !pending { send(action) } }
    private func send(_ action: DeviceCommand) {
        pending = true; status = nil; failed = false
        store.call(action) { result in
            pending = false
            switch result {
            case .success: status = "Request accepted. The speaker’s reported state confirms playback."
            case .failure(let error): failed = true; status = error.localizedDescription
            }
        }
    }
}

/// An explicit picker remains available beside transport for choosing a different
/// track, including when Alexa's primary play key starts its account's music.
struct SpeakerChooseMusicButton: View {
    let entity: Entity
    @State private var choosing = false
    var body: some View {
        Button { choosing = true } label: {
            Image(systemName: "music.note.list").font(.system(size: 12))
                .foregroundStyle(Theme.ink).frame(width: 28, height: 28)
        }
        .buttonStyle(PressStyle()).disabled(entity.isUnavailable)
        .help("Choose music").accessibilityLabel("Choose music for \(entity.name)")
        .popover(isPresented: $choosing, arrowEdge: .bottom) { SpeakerMusicComposer(entity: entity) }
    }
}
