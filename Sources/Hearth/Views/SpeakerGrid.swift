import SwiftUI

/// Group membership comes from HA. Matching metadata is labelled as the same
/// track, never used as evidence that the devices' clocks are synchronized.
struct SpeakerPlayback {
    let badge: String?
    let phase: Double

    init(entity: Entity, players: [Entity]) {
        let groups = players.map { player -> Set<String> in
            let reported = player.list("group_members")
            return reported.isEmpty ? [] : Set(reported + [player.id])
        }.filter { $0.contains(entity.id) && $0.count > 1 }
        let members = groups.sorted { $0.sorted().joined() < $1.sorted().joined() }.first
        let groupCount = members.map { group in players.filter { group.contains($0.id) }.count } ?? 0
        let sameTrack = entity.state == "playing" ? players.filter {
            $0.state == "playing" && Self.trackKey($0) != nil && Self.trackKey($0) == Self.trackKey(entity)
        }.count : 0
        badge = groupCount > 1 ? "Grouped · \(groupCount)" : sameTrack > 1 ? "Same track · \(sameTrack)" : nil
        let phaseKey = groupCount > 1 ? (members?.sorted().joined(separator: "|") ?? entity.id) : entity.id
        let hash = phaseKey.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        phase = Double(hash % 1000) / 1000
    }

    private static func trackKey(_ entity: Entity) -> String? {
        if let id = entity.str("media_content_id"), !id.isEmpty { return "id:\(id)" }
        guard let title = entity.str("media_title"), !title.isEmpty,
              let artist = entity.str("media_artist"), !artist.isEmpty else { return nil }
        return "metadata:\(artist.lowercased())|\(title.lowercased())"
    }
}

struct SpeakerGridCard: View {
    @EnvironmentObject private var store: HomeStore
    let entity: Entity
    let playback: SpeakerPlayback
    let onDetails: () -> Void

    var body: some View {
        let device = store.registry[entity.id]?.deviceID.flatMap { store.homeDevice($0) }
        let room = store.areaID(of: entity.id).flatMap { store.areas[$0]?.name }
        let area = store.areaID(of: entity.id).flatMap { store.areas[$0] }
        let playing = entity.state == "playing"
        let online = !entity.isUnavailable
        let kind = device?.kind ?? (entity.name.lowercased().contains("homepod") ? .meshSpeaker : .smartSpeaker)
        let accent = device?.accent ?? Theme.sand
        Bezel(radius: 22, inset: 3, lit: playing, tint: accent) {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    Button(action: onDetails) {
                        VStack(spacing: 4) {
                            Spacer(minLength: 0)
                            ZStack(alignment: .bottom) {
                                if playing { SpeakerWaves(phase: playback.phase, color: accent).frame(height: 35) }
                                DeviceArtView(kind: kind, active: online, accent: accent, size: 54)
                                    .frame(width: 54, height: 54).padding(.bottom, 4)
                                    .opacity(online ? 1 : 0.42)
                            }
                            .frame(maxWidth: .infinity).frame(height: 58)
                            Text(device?.name ?? entity.name).font(.system(size: 12.5, weight: .semibold))
                                .lineLimit(2).multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true).frame(minHeight: 28)
                            if let room {
                                Label(room, systemImage: RoomStyle.symbol(area))
                                    .font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.muted).lineLimit(1)
                            }
                            if let badge = playback.badge {
                                Text(badge).font(.system(size: 10, weight: .medium)).foregroundStyle(accent).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle()).help("Show track, transport and volume")
                    .accessibilityLabel("\(device?.name ?? entity.name), show playback controls")
                    HStack(spacing: 5) {
                        Circle().fill(online ? accent : Theme.faint).frame(width: 4, height: 4)
                        Text(!online ? "Offline" : playing ? "Playing" : entity.state == "paused" ? "Paused" : "Online")
                            .font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.muted)
                        Spacer(minLength: 0)
                        if online {
                            SpeakerPlayButton(entity: entity, size: 25)

                        }
                    }
                    .frame(height: 26)
                }
                .padding(10).frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Elliptical ripples leave the speaker's base. Reported group members share
/// a phase; independent speakers have their own phase. Reduce Motion is static.
struct SpeakerWaves: View {
    let phase: Double
    let color: Color
    var previewTime: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || previewTime != nil)) { timeline in
            let time = reduceMotion ? 1.0 : previewTime ?? timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                for i in 0..<3 {
                    let age = (time * 0.45 + phase + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    let width = size.width * (0.16 + age * 0.8)
                    let height = 4 + age * (size.height - 7)
                    let oval = Path(ellipseIn: CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2,
                                                    width: width, height: height))
                    let opacity = sin(age * .pi) * (1 - age) * 0.5
                    var glow = context
                    glow.addFilter(.blur(radius: 2))
                    glow.stroke(oval, with: .color(color.opacity(opacity * 0.5)), lineWidth: 3)
                    context.stroke(oval, with: .color(color.opacity(opacity)), lineWidth: 0.9)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
