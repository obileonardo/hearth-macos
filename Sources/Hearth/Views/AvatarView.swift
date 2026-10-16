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
    @Published private(set) var importError: String?
    private let folder: URL
    private var importAttempt = UUID()

    private static let defaultFolder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Hearth/avatar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private convenience init() { self.init(folder: Self.defaultFolder) }

    /// Fixture callers provide a separate directory; never access the live store.
    init(folder: URL) {
        self.folder = folder
        url = AvatarImport.selected(in: folder)
    }

    var kind: Kind? {
        guard let url, let type = UTType(filenameExtension: url.pathExtension) else { return nil }
        if type.conforms(to: .gif) { return .gif }
        if type.conforms(to: .movie) { return .video }
        return .still
    }

    /// Preserve the current picture until the new copy, media validation and
    /// atomic selection update all succeed. A later choice owns the result.
    func use(_ source: URL) async {
        let attempt = UUID()
        importAttempt = attempt
        do {
            _ = try await AvatarImport.stage(source, in: folder,
                stillCurrent: { self.importAttempt == attempt }, commit: { name, folder in
                    guard self.importAttempt == attempt else { throw CancellationError() }
                    try AvatarImport.writeSelection(name, in: folder)
                    // Selection and displayed URL change in the same MainActor
                    // turn, so an overlapping choice cannot publish stale state.
                    let previous = self.url
                    let next = folder.appendingPathComponent(name)
                    self.url = next
                    self.importError = nil
                    if let previous, previous != next, previous.deletingLastPathComponent() == folder {
                        try? FileManager.default.removeItem(at: previous)
                    }
                })
        } catch {
            guard importAttempt == attempt else { return }
            importError = "Your existing picture is unchanged. " + error.localizedDescription
        }
    }

    func dismissImportError() { importError = nil }

    func remove() {
        importAttempt = UUID()
        do {
            // An explicit empty choice prevents an older retained file from
            // reappearing after a restart if its cleanup previously failed.
            try AvatarImport.writeSelection("", in: folder)
            let previous = url
            url = nil
            importError = nil
            if let previous { try? FileManager.default.removeItem(at: previous) }
        } catch {
            importError = "Your existing picture is unchanged. " + error.localizedDescription
        }
    }

    func choose() {
        let panel = NSOpenPanel()
        panel.title = "Choose your picture"
        panel.message = "A photo, a GIF or a short video. A Memoji recording loops nicely."
        panel.allowedContentTypes = [.movie, .gif, .image]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let picked = panel.url { Task { await use(picked) } }
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
        .alert("Couldn’t change your picture", isPresented: Binding(
            get: { store.importError != nil },
            set: { if !$0 { store.dismissImportError() } })) {
                Button("OK", role: .cancel) { store.dismissImportError() }
            } message: { Text(store.importError ?? "") }
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
