import AVFoundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The picture you chose for yourself: a still, a GIF or a short video (a Memoji recording works
/// well, transparency and all). It lives in Hearth's own folder, never anywhere else.
@MainActor
final class AvatarStore: ObservableObject {
    static let shared = AvatarStore()

    enum Kind { case video, gif, still }

    @Published private(set) var url: URL?

    private static let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Hearth/avatar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {
        url = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil))?
            .first { !$0.lastPathComponent.hasPrefix(".") }
    }

    var kind: Kind? {
        guard let url, let type = UTType(filenameExtension: url.pathExtension) else { return nil }
        if type.conforms(to: .gif) { return .gif }
        if type.conforms(to: .movie) { return .video }
        return .still
    }

    /// Copies the file in, replacing whatever was there.
    func use(_ source: URL) {
        let fm = FileManager.default
        try? fm.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil).forEach { try? fm.removeItem(at: $0) }
        let target = Self.folder.appendingPathComponent("avatar." + source.pathExtension.lowercased())
        do {
            try fm.copyItem(at: source, to: target)
            url = target
        } catch {
            NSLog("Hearth: couldn't use that avatar: \(error.localizedDescription)")
        }
    }

    func remove() {
        if let url { try? FileManager.default.removeItem(at: url) }
        url = nil
    }

    func choose() {
        let panel = NSOpenPanel()
        panel.title = "Choose your picture"
        panel.message = "A photo, a GIF or a short video. A Memoji recording loops nicely."
        panel.allowedContentTypes = [.movie, .gif, .image]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let picked = panel.url { use(picked) }
    }
}

/// A round avatar that plays the chosen video or GIF on a loop, falling back to the
/// Home Assistant picture, then initials.
struct LiveAvatar: View {
    let name: String
    let fallback: NSImage?
    var size: CGFloat = 64
    @ObservedObject private var store = AvatarStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        ZStack {
            // A soft backdrop for transparent Memoji, lit from the top like the rest of Hearth.
            Circle().fill(LinearGradient(colors: [Theme.sand.opacity(0.55), Theme.sand.opacity(0.18)],
                                         startPoint: .top, endPoint: .bottom))
            switch (store.kind, store.url) {
            case (.video, let url?):
                LoopingVideo(url: url, playing: !reduceMotion)
                    // A Memoji sits small in the middle of its frame; bring the face up to fill the circle.
                    .scaleEffect(1.62)
                    .offset(y: size * 0.07)
            case (.gif, let url?):
                AnimatedImage(url: url, animates: !reduceMotion)
            case (.still, let url?):
                if let image = NSImage(contentsOf: url) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                }
            default:
                Avatar(name: name, image: fallback, size: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 0.75))
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "pencil")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Theme.base).overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 0.75)))
                .opacity(hovering ? 1 : 0)
                .offset(x: 2, y: 2)
        }
        .contentShape(Circle())
        .onHover { hovering = $0 }
        .animation(.snap, value: hovering)
        .onTapGesture { store.choose() }
        .contextMenu {
            Button("Choose picture or video…") { store.choose() }
            if store.url != nil { Button("Use my Home Assistant picture", role: .destructive) { store.remove() } }
        }
        .help("Choose a picture, GIF or short video")
        .accessibilityElement()
        .accessibilityLabel("Your picture")
        .accessibilityHint("Choose a picture, GIF or short video")
        .accessibilityAddTraits(.isButton)
    }
}

/// A muted video on a loop, transparent where the video is, paused when off screen.
private struct LoopingVideo: NSViewRepresentable {
    let url: URL
    let playing: Bool

    func makeNSView(context: Context) -> PlayerHost { PlayerHost(url: url) }

    func updateNSView(_ view: PlayerHost, context: Context) {
        if view.url != url { view.load(url) }
        view.setPlaying(playing)
    }

    static func dismantleNSView(_ view: PlayerHost, coordinator: ()) { view.stop() }

    final class PlayerHost: NSView {
        private(set) var url: URL
        private let layerHost = AVPlayerLayer()
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?
        private var wantsPlay = true

        init(url: URL) {
            self.url = url
            super.init(frame: .zero)
            wantsLayer = true
            layer?.backgroundColor = .clear
            layerHost.videoGravity = .resizeAspectFill
            layerHost.backgroundColor = .clear
            layer?.addSublayer(layerHost)
            load(url)
        }

        required init?(coder: NSCoder) { nil }

        override func layout() {
            super.layout()
            layerHost.frame = bounds
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window == nil ? player?.pause() : (wantsPlay ? player?.play() : nil)
        }

        func load(_ url: URL) {
            self.url = url
            let item = AVPlayerItem(url: url)
            let queue = AVQueuePlayer()
            queue.isMuted = true
            queue.preventsDisplaySleepDuringVideoPlayback = false
            looper = AVPlayerLooper(player: queue, templateItem: item)
            player = queue
            layerHost.player = queue
            if wantsPlay, window != nil { queue.play() }
        }

        func setPlaying(_ on: Bool) {
            wantsPlay = on
            on && window != nil ? player?.play() : player?.pause()
        }

        func stop() {
            player?.pause()
            looper = nil
            player = nil
        }
    }
}

/// A GIF that plays (or holds its first frame when motion should be reduced).
private struct AnimatedImage: NSViewRepresentable {
    let url: URL
    let animates: Bool

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.image = NSImage(contentsOf: url)
        view.animates = animates
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        view.animates = animates
    }
}
