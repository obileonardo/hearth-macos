import AVKit
import SwiftUI

/// A camera's latest picture in a machined frame, refreshed every few seconds while
/// it's on screen. The first camera is shown large.
struct CameraTile: View {
    @EnvironmentObject var store: HomeStore
    @Environment(\.hearthOpenWindow) private var openWindow
    let entity: Entity
    var hero = false
    private var image: NSImage? { store.snapshots[entity.id] }

    var body: some View {
        let radius: CGFloat = hero ? 22 : 18
        Button {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "camera", value: entity.id)
        } label: {
            ZStack(alignment: .bottomLeading) {
                Theme.fg.opacity(0.04)
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .privacyBlurred()
                        .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                        .transition(.opacity)
                } else {
                    Image(systemName: entity.isUnavailable ? "video.slash" : "video")
                        .font(.system(size: 18, weight: .ultraLight))
                        .foregroundStyle(Theme.faint)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                HStack(spacing: 6) {
                    PulseDot(color: entity.isUnavailable ? Theme.faint : Theme.live, live: !entity.isUnavailable, period: 1.8)
                    Text(entity.name).font(.system(size: hero ? 12 : 10.5, weight: .semibold)).lineLimit(1)
                    Spacer()
                    if hero {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11.5, weight: .medium))
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(.ultraThinMaterial))
                    }
                }
                .padding(hero ? 12 : 9)
            }
            .aspectRatio(hero ? 16 / 9 : 16 / 10, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: radius - 4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius - 4, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Theme.fg.opacity(0.2), Theme.fg.opacity(0.03)], startPoint: .top, endPoint: .bottom), lineWidth: 0.75))
            .padding(4)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.fg.opacity(0.025))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.75)))
        }
        .buttonStyle(PressStyle())
        .task(id: entity.id) {
            while !Task.isCancelled {
                _ = await store.snapshot(entity.id)
                try? await Task.sleep(for: .seconds(8))
            }
        }
    }
}

/// The live view window: real-time video (WebRTC, then HLS, then snapshots), with sound
/// off until asked for.
struct CameraWindow: View {
    @EnvironmentObject var store: HomeStore
    let entityID: String
    @State private var muted = true
    @State private var state: LiveState = .connecting

    var body: some View {
        LiveVideoView(entityID: entityID, muted: muted) { state = $0 }
            .overlay(alignment: .topTrailing) { PrivacyBlurButton(onMedia: true).padding(12) }
            .overlay(alignment: .bottomTrailing) {
                if case .live = state {
                    Button {
                        muted.toggle()
                    } label: {
                        Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.ink)
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(.ultraThinMaterial))
                            .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 0.75))
                    }
                    .buttonStyle(PressStyle())
                    .help(muted ? "Turn sound on" : "Turn sound off")
                    .padding(12)
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .bottomLeading) {
                let device = store.registry[entityID]?.deviceID.flatMap { store.homeDevice($0) }
                if let toggle = device?.entity(key: "camera_enabled"), !(device.map { store.isOnUnreachableHub($0.id) } ?? false) {
                    CameraPauseButton(entity: toggle, cameraName: device?.name ?? "Camera", compact: false).padding(12)
                }
            }
            .animation(.glide, value: state)
            .frame(minWidth: 480, minHeight: 300)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
            .navigationTitle(store.entities[entityID]?.name ?? "Camera")
    }
}
