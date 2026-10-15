import AppKit
import Foundation
import UserNotifications

/// Everything worth knowing that happened around the house: people seen, the doorbell,
/// motion, the alarm and the air conditioning. Kept on disk, with a picture where there's a camera.
@MainActor
final class ActivityLog: ObservableObject {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case person, doorbell, motion, pet, sound, security, climate
        var id: String { rawValue }

        var label: String {
            switch self {
            case .person: "People"
            case .doorbell: "Doorbell"
            case .motion: "Motion"
            case .pet: "Pets"
            case .sound: "Sound"
            case .security: "Alarm"
            case .climate: "Climate"
            }
        }

        var symbol: String {
            switch self {
            case .person: "person.fill"
            case .doorbell: "bell.fill"
            case .motion: "figure.walk.motion"
            case .pet: "pawprint.fill"
            case .sound: "waveform"
            case .security: "shield.lefthalf.filled"
            case .climate: "air.conditioner.horizontal.fill"
            }
        }

        /// People, the doorbell and the alarm notify by default; the rest stay in the timeline.
        var notifiesByDefault: Bool { [.person, .doorbell, .security].contains(self) }
    }

    struct Item: Codable, Identifiable, Equatable {
        var id = UUID()
        var kind: Kind
        var title: String
        var place: String
        var date: Date
        var entityID: String
        var cameraID: String?
        var imageFile: String?
        var read = false
        /// A face Hearth found in the picture (see FaceLibrary), and the title before any name was put on it.
        var faceSample: UUID?
        var plainTitle: String?
    }

    @Published private(set) var items: [Item] = []
    var unread: Int { items.filter { !$0.read }.count }

    /// Supplying preview items opts into a memory-only log before the static
    /// persistence path is evaluated. Documentation must never read live history.
    private let isPreview: Bool
    private var previewNotificationChoices: [Kind: Bool] = [:]
    private weak var store: HomeStore?
    private var lastSeen: [String: Date] = [:]
    private var backfilled = false

    private static let folder: URL = {
        if let path = UserDefaults.standard.string(forKey: "activityFolder") {
            let dir = URL(fileURLWithPath: path, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir.appendingPathComponent("activity"), withIntermediateDirectories: true)
            return dir
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Hearth", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("activity"), withIntermediateDirectories: true)
        return dir
    }()
    private static var file: URL { folder.appendingPathComponent("activity.json") }

    init(previewItems: [Item]? = nil) {
        isPreview = previewItems != nil
        if let previewItems {
            items = previewItems.map { seed in
                var item = seed
                item.cameraID = nil
                item.imageFile = nil
                item.faceSample = nil
                item.plainTitle = nil
                return item
            }
            return
        }
        if let data = try? Data(contentsOf: Self.file),
           let saved = try? JSONDecoder().decode([Item].self, from: data) {
            items = saved
        }
    }

    func attach(_ store: HomeStore) {
        guard !isPreview else { return }
        self.store = store
        FaceLibrary.shared.onEdit = { [weak self] in self?.refreshFaceTitles() }
        Task { await learnFaces() }
    }

    // MARK: Settings

    func notifies(_ kind: Kind) -> Bool {
        if isPreview { return previewNotificationChoices[kind] ?? kind.notifiesByDefault }
        return UserDefaults.standard.object(forKey: "notify.\(kind.rawValue)") as? Bool ?? kind.notifiesByDefault
    }

    func setNotifies(_ kind: Kind, _ on: Bool) {
        if isPreview {
            previewNotificationChoices[kind] = on
            objectWillChange.send()
            return
        }
        UserDefaults.standard.set(on, forKey: "notify.\(kind.rawValue)")
        objectWillChange.send()
    }

    func markAllRead() {
        guard items.contains(where: { !$0.read }) else { return }
        for i in items.indices { items[i].read = true }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    // MARK: Watching

    /// Called for every state change Home Assistant reports.
    func handle(_ new: Entity, _ old: Entity?) {
        guard !isPreview else { return }
        guard let old, !new.isUnavailable, !old.isUnavailable, new.state != old.state else { return }
        // A camera that recognises a face names the person a moment after it reports someone.
        if new.domain == "sensor", new.id.hasSuffix("_person_name"), let name = Self.recognised(new.state) {
            return named(name, deviceOf: new.id)
        }
        guard let (kind, title) = classify(new, old) else { return }
        if let last = lastSeen[new.id], Date().timeIntervalSince(last) < 45 { return }
        lastSeen[new.id] = Date()
        add(kind: kind, title: title, entityID: new.id, date: Date(), notify: true)
    }

    private func classify(_ e: Entity, _ old: Entity) -> (Kind, String)? {
        let device = store?.device(of: e.id)?.name ?? e.name
        switch e.domain {
        case "binary_sensor":
            guard e.state == "on" else { return nil }
            let id = e.id
            let dc = e.str("device_class") ?? ""
            if id.contains("person") {
                let name = store?.siblings(of: e.id, domain: "sensor").first { $0.id.hasSuffix("_person_name") }
                    .flatMap { Self.recognised($0.state) }
                return (.person, "\(name ?? "Person") at \(device)")
            }
            if id.contains("pet") { return (.pet, "Pet at \(device)") }
            if id.contains("crying") || dc == "sound" { return (.sound, "Sound at \(device)") }
            if ["motion", "occupancy", "presence", "moving"].contains(dc) { return (.motion, "Movement at \(device)") }
            return nil
        case "event":
            switch e.str("device_class") ?? e.str("event_type") ?? "" {
            case "doorbell", "ding", "ring": return (.doorbell, "Someone rang \(device)")
            case "motion": return (.motion, "Movement at \(device)")
            default: return nil
            }
        case "alarm_control_panel":
            let what = switch e.state {
            case "armed_away": "armed for Away"
            case "armed_home": "armed for Home"
            case "armed_night": "armed for Night"
            case "disarmed": "disarmed"
            case "triggered": "triggered"
            default: e.state.pretty.lowercased()
            }
            return (.security, "\(e.name) \(what)")
        case "climate":
            let wasOn = old.state != "off", isOn = e.state != "off"
            guard wasOn != isOn else { return nil }
            return (.climate, "\(Climate.shortName(e.name)) AC turned \(isOn ? "on" : "off")")
        default:
            return nil
        }
    }

    /// A real name from a camera's face recognition, not its placeholders.
    private static func recognised(_ state: String) -> String? {
        let s = state.trimmingCharacters(in: .whitespaces)
        return s.isEmpty || ["no person", "unknown person", "unknown", "stranger"].contains(s.lowercased()) ? nil : s
    }

    /// Puts a recognised name on the person just seen by that camera, or adds an entry for them.
    private func named(_ name: String, deviceOf entityID: String) {
        guard !isPreview else { return }
        guard let store, let device = store.registry[entityID]?.deviceID else { return }
        if let i = items.firstIndex(where: { $0.kind == .person && Date().timeIntervalSince($0.date) < 60
                                        && store.registry[$0.entityID]?.deviceID == device }) {
            let place = store.devices[device]?.name ?? ""
            items[i].title = "\(name) at \(place)"
            save()
        } else {
            let place = store.devices[device]?.name ?? ""
            add(kind: .person, title: "\(name) at \(place)", entityID: entityID, date: Date(), notify: true)
        }
    }

    private func add(kind: Kind, title: String, entityID: String, date: Date, notify: Bool, read: Bool = false) {
        guard !isPreview else { return }
        guard let store else { return }
        let place = store.areaID(of: entityID).flatMap { store.areas[$0]?.name } ?? ""
        let camera = store.camera(sharingDeviceWith: entityID)?.id
        var item = Item(kind: kind, title: title, place: place, date: date, entityID: entityID, cameraID: camera, read: read)
        items.insert(item, at: 0)
        if items.count > 300 { items.removeLast(items.count - 300) }
        save()

        Task { @MainActor in
            // Give the camera a moment to save its event picture.
            if camera != nil { try? await Task.sleep(for: .seconds(2.5)) }
            if let file = await picture(for: entityID, camera: camera, id: item.id) {
                item.imageFile = file.path
                if let i = items.firstIndex(where: { $0.id == item.id }) { items[i].imageFile = file.path }
                save()
            }
            if let path = item.imageFile, [.person, .doorbell].contains(kind),
               let match = await FaceLibrary.shared.process(URL(fileURLWithPath: path), date: item.date, itemID: item.id) {
                applyFace(match, to: item.id)
                if let i = items.firstIndex(where: { $0.id == item.id }) { item = items[i] }
            }
            if notify, notifies(kind) { await post(item) }
        }
    }

    // MARK: Faces

    /// Looks for faces in the pictures already saved, a few at a time, when Familiar faces is on.
    func learnFaces() async {
        guard !isPreview else { return }
        let faces = FaceLibrary.shared
        guard faces.enabled else { return }
        let pending = items.filter { [.person, .doorbell].contains($0.kind) && $0.imageFile != nil && $0.faceSample == nil }
        for item in pending {
            guard faces.enabled, let path = item.imageFile else { break }
            let url = URL(fileURLWithPath: path)
            guard !faces.hasScanned(url), FileManager.default.fileExists(atPath: path) else { continue }
            if let match = await faces.process(url, date: item.date, itemID: item.id) { applyFace(match, to: item.id) }
            try? await Task.sleep(for: .milliseconds(150))
        }
    }

    private func applyFace(_ match: FaceLibrary.Match, to id: UUID) {
        guard !isPreview else { return }
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].faceSample = match.sample
        if items[i].plainTitle == nil { items[i].plainTitle = items[i].title }
        if let name = match.name { items[i].title = Self.titled(items[i].plainTitle ?? items[i].title, with: name) }
        save()
    }

    /// Puts the current names back on every entry with a face, after faces are named, merged or forgotten.
    func refreshFaceTitles() {
        guard !isPreview else { return }
        var changed = false
        for i in items.indices {
            guard let sample = items[i].faceSample else { continue }
            let plain = items[i].plainTitle ?? items[i].title
            let title = FaceLibrary.shared.name(ofSample: sample).map { Self.titled(plain, with: $0) } ?? plain
            if title != items[i].title { items[i].title = title; changed = true }
        }
        if changed { save() } else { objectWillChange.send() }
    }

    /// Replaces generic event subjects with the locally matched person's display name.
    static func titled(_ plain: String, with name: String) -> String {
        if plain.hasPrefix("Someone ") { return name + plain.dropFirst("Someone".count) }
        if let r = plain.range(of: " at ") { return name + plain[r.lowerBound...] }
        return "\(name): \(plain)"
    }

    /// The event picture if the camera keeps one, otherwise a fresh snapshot.
    private func picture(for entityID: String, camera: String?, id: UUID) async -> URL? {
        guard !isPreview else { return nil }
        guard let store, camera != nil else { return nil }
        let eventImage = store.registry[entityID]?.deviceID.flatMap { dev in
            store.entities.keys.first { $0.hasPrefix("image.") && $0.hasSuffix("event_image") && store.registry[$0]?.deviceID == dev }
        }
        var image: NSImage?
        if let eventImage { image = await store.image(eventImage) }
        if image == nil, let camera { image = await store.snapshot(camera) }
        guard let image, let tiff = image.tiffRepresentation,
              let jpeg = NSBitmapImageRep(data: tiff)?.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return nil }
        let url = Self.folder.appendingPathComponent("activity/\(id.uuidString).jpg")
        return (try? jpeg.write(to: url)) != nil ? url : nil
    }

    private func post(_ item: Item) async {
        guard !isPreview else { return }
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.place.isEmpty ? item.kind.label : item.place
        content.sound = item.kind == .doorbell ? .defaultCritical : .default
        content.threadIdentifier = item.kind.rawValue
        if let path = item.imageFile {
            // Notifications move their attachment, so hand them a copy.
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
            if (try? FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: copy)) != nil,
               let attachment = try? UNNotificationAttachment(identifier: "picture", url: copy) {
                content.attachments = [attachment]
            }
        }
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: item.id.uuidString, content: content, trigger: nil))
    }

    // MARK: History

    /// Fills the timeline with the last day from Home Assistant's logbook, once per launch.
    func backfill() async {
        guard !isPreview else { return }
        guard let store, !backfilled else { return }
        backfilled = true
        let watched = store.entities.values.filter { e in
            switch e.domain {
            case "binary_sensor": ["motion", "occupancy", "presence", "sound"].contains(e.str("device_class") ?? "")
            case "event": ["doorbell", "motion"].contains(e.str("device_class") ?? "")
            case "alarm_control_panel": true
            default: false
            }
        }
        guard !watched.isEmpty else { return }
        let since = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-24 * 3600))
        guard let rows = try? await store.command([
            "type": "logbook/get_events", "start_time": since, "entity_ids": watched.map(\.id),
        ]) as? [JSON] else { return }

        let known = Set(items.map { "\($0.entityID)@\(Int($0.date.timeIntervalSince1970))" })
        var previous: [String: String] = [:]
        for row in rows {
            guard let id = row["entity_id"] as? String, let state = row["state"] as? String, let e = store.entities[id] else { continue }
            let when: Date? = if let t = row["when"] as? Double { Date(timeIntervalSince1970: t) }
                else if let s = row["when"] as? String { ISO8601DateFormatter().date(from: s) } else { nil }
            guard let when else { continue }
            var probe = e
            probe.state = state
            var before = e
            before.state = previous[id] ?? (e.domain == "binary_sensor" ? "off" : "")
            previous[id] = state
            guard state != "unavailable", let (kind, title) = classify(probe, before) else { continue }
            guard !known.contains("\(id)@\(Int(when.timeIntervalSince1970))") else { continue }
            items.append(Item(kind: kind, title: title, place: store.areaID(of: id).flatMap { store.areas[$0]?.name } ?? "",
                              date: when, entityID: id, cameraID: store.camera(sharingDeviceWith: id)?.id, read: true))
        }
        items.sort { $0.date > $1.date }
        if items.count > 300 { items.removeLast(items.count - 300) }
        save()
    }

    private func save() {
        guard !isPreview else { return }
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: Self.file, options: .atomic) }
    }
}
