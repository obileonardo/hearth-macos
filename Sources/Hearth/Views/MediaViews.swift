import SwiftUI

/// Every speaker in the house, playing ones first, with artwork and controls.
struct MediaPage: View {
    @EnvironmentObject var store: HomeStore
    let players: [Entity]
    let shown: Bool
    var previewLayout: String?
    @AppStorage("speakers.layout") private var savedLayout = "list"
    @State private var expandedID: String?

    private var grid: Bool { (previewLayout ?? savedLayout) == "grid" }

    private var sorted: [Entity] {
        players.sorted { a, b in
            let ra = rank(a), rb = rank(b)
            return ra != rb ? ra < rb : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private func rank(_ e: Entity) -> Int {
        switch e.state {
        case "playing": 0
        case "paused", "buffering": 1
        case "unavailable", "unknown": 3
        default: 2
        }
    }

    var body: some View {
        let playing = players.filter { $0.state == "playing" }.count
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(eyebrow: playing > 0 ? "\(playing) playing" : "\(players.count) speakers", title: "Now playing",
                       pinnedIllustrations: sorted.prefix(3).map { player in
                           store.registry[player.id]?.deviceID.flatMap { store.homeDevice($0)?.kind } ?? .smartSpeaker
                       }, pinnedCount: players.count) {
                HStack(spacing: 2) {
                    layoutButton("square.grid.2x2", title: "Grid view", value: "grid")
                    layoutButton("list.bullet", title: "List view", value: "list")
                }
                .slidingSelection(grid ? 0 : 1, radius: 14)
                .padding(3).background(Capsule().fill(Theme.fg.opacity(0.05)).overlay(Capsule().strokeBorder(Theme.hairline)))
            }
                .reveal(shown, 0)
            if grid {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(sorted) { player in
                        SpeakerGridCard(entity: player, playback: SpeakerPlayback(entity: player, players: players)) {
                            withAnimation(.glide) { expandedID = expandedID == player.id ? nil : player.id }
                        }
                    }
                }
                .reveal(shown, 1)
                if let player = players.first(where: { $0.id == expandedID }) {
                    PlayerCard(entity: player).transition(.opacity)
                }
            } else {
            ForEach(Array(sorted.enumerated()), id: \.element.id) { i, player in
                if rank(player) < 2 {
                    PlayerCard(entity: player).reveal(shown, 1 + i)
                } else {
                    IdleSpeakerRow(entity: player).reveal(shown, 1 + min(i, 8))
                }
            }
            }
        }
    }

    private func layoutButton(_ symbol: String, title: String, value: String) -> some View {
        Button { withAnimation(.glide) { savedLayout = value } } label: {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(grid == (value == "grid") ? Theme.onKey : Theme.muted)
                .frame(width: 28, height: 26)
                .selectionFrame(value == "grid" ? 0 : 1)
        }
        .buttonStyle(PressStyle()).help(title).accessibilityLabel(title)
        .accessibilityAddTraits(grid == (value == "grid") ? .isSelected : [])
    }
}

/// A speaker that's playing or paused: artwork, track, transport and volume.
struct PlayerCard: View {
    @EnvironmentObject var store: HomeStore
    let entity: Entity
    @State private var artwork: NSImage?
    @State private var volume: Double?
    @State private var commandError: String?

    var body: some View {
        let playing = entity.state == "playing"
        let device = store.registry[entity.id]?.deviceID.flatMap { store.homeDevice($0) }
        let room = store.areaID(of: entity.id).flatMap { store.areas[$0]?.name }
        Bezel(radius: 24, inset: 4, lit: playing, tint: Theme.sand) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.fg.opacity(0.06))
                        if let artwork {
                            Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                        } else if let device {
                            DeviceArtView(kind: device.kind, active: playing, accent: device.accent, size: 46)
                        } else {
                            Image(systemName: "music.note").font(.system(size: 20, weight: .light)).foregroundStyle(Theme.muted)
                        }
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entity.str("media_title") ?? (playing ? "Playing" : entity.state == "paused" ? "Paused" : "Choose music"))
                            .font(.system(size: 14.5, weight: .semibold)).lineLimit(1)
                        Text(entity.str("media_artist") ?? entity.str("app_name") ?? "")
                            .font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(1)
                        HStack(spacing: 5) {
                            if playing { Equalizer() }
                            Text([device?.name ?? entity.name, room].compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.faint).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 18) {
                    transport("backward.fill", "media_previous_track", size: 12)
                    SpeakerPlayButton(entity: entity, size: 40, prominent: true)
                    transport("forward.fill", "media_next_track", size: 12)
                    SpeakerChooseMusicButton(entity: entity)
                    if let v = entity.num("volume_level") {
                        HStack(spacing: 6) {
                            Image(systemName: "speaker.fill").font(.system(size: 10.5)).foregroundStyle(Theme.faint)
                            ThinSlider(value: volume ?? v, range: 0...1, step: 0.02) { volume = $0 } onEnd: { v in
                                send("volume_set", ["volume_level": v])
                                volume = nil
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
        .task(id: entity.str("entity_picture")) { await loadArtwork() }
        .alert("Speaker action failed", isPresented: Binding(get: { commandError != nil }, set: { if !$0 { commandError = nil } })) {
            Button("OK") { commandError = nil }
        } message: { Text(commandError ?? "") }
    }

    private func transport(_ symbol: String, _ service: String, size: CGFloat) -> some View {
        Button { send(service) } label: {
            Image(systemName: symbol).font(.system(size: size)).foregroundStyle(Theme.ink)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(PressStyle())
        .disabled(entity.isUnavailable || !SpeakerAction.supports(entity, feature: service == "media_next_track" ? 32 : 16))
        .accessibilityLabel(service == "media_next_track" ? "Next track" : service == "media_previous_track" ? "Previous track" : service.replacingOccurrences(of: "media_", with: "").pretty)
    }

    private func send(_ service: String, _ data: JSON = [:]) {
        store.call("media_player", service, entity.id, data) { result in
            if case .failure(let error) = result { commandError = error.localizedDescription }
        }
    }

    /// Album art comes through Home Assistant's media proxy.
    private func loadArtwork() async {
        artwork = nil
        guard let path = entity.str("entity_picture") else { return }
        if let data = await store.pictureData(at: path), !Task.isCancelled, let image = NSImage(data: data) {
            withAnimation(.glide) { artwork = image }
        }
    }
}

/// A quiet speaker: a single line with a play key.
struct IdleSpeakerRow: View {
    @EnvironmentObject var store: HomeStore
    let entity: Entity

    var body: some View {
        let device = store.registry[entity.id]?.deviceID.flatMap { store.homeDevice($0) }
        let room = store.areaID(of: entity.id).flatMap { store.areas[$0]?.name }
        HStack(spacing: 10) {
            if let device {
                DeviceArtView(kind: device.kind, active: !entity.isUnavailable, accent: device.accent, size: 34)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(device?.name ?? entity.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text([room, entity.isUnavailable ? "Offline" : "Idle"].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            Spacer()
            if !entity.isUnavailable {
                SpeakerPlayButton(entity: entity)

            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.fg.opacity(0.03))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.75)))
    }
}

/// Three little bars that bounce while music plays.
struct Equalizer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { t in
            let x = reduceMotion ? 1 : t.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule().fill(Theme.sand)
                        .frame(width: 2, height: 3 + 6 * abs(sin(x * (3.1 + Double(i) * 1.7) + Double(i))))
                }
            }
            .frame(height: 9, alignment: .bottom)
        }
    }
}
