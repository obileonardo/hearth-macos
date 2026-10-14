import AppKit
import CoreImage
import Foundation
import Vision

/// Familiar faces, learned on this Mac from the pictures Hearth's cameras save, and from photos
/// you add. Apple Vision finds each face, levels it by the eyes, and describes it as a feature
/// print; prints that sit close together are probably the same person.
///
/// Vision's feature prints are general image descriptors, not a dedicated face-identity model,
/// so matching is cautious: a name is only given when several of that person's pictures are
/// close and nobody else comes near. When unsure, the face stays unnamed.
///
/// Everything lives in ~/Library/Application Support/Hearth/faces and never leaves the Mac.
/// It is off until you turn it on.
@MainActor
final class FaceLibrary: ObservableObject {
    static let shared = FaceLibrary()

    struct Sample: Codable, Identifiable, Equatable {
        var id = UUID()
        var date: Date
        var quality: Float
        /// The activity entry the face came from; nil for photos you added.
        var itemID: UUID?
    }

    struct Person: Codable, Identifiable, Equatable {
        var id = UUID()
        var name: String
        var samples: [Sample]
        var lastSeen: Date?
        /// The clearest picture, for the avatar.
        var best: Sample? { samples.max { $0.quality < $1.quality } }
    }

    /// Faces that look alike but nobody has named yet.
    struct Group: Codable, Identifiable, Equatable {
        var id = UUID()
        var samples: [Sample]
        var best: Sample? { samples.max { $0.quality < $1.quality } }
    }

    private struct Index: Codable {
        var people: [Person] = []
        var unknown: [Group] = []
        var scanned: [String] = []
        var lookedAt = 0
        var usable = 0
    }

    /// Who a face turned out to be, for the activity entry it came from.
    struct Match {
        let sample: UUID
        let name: String?
    }

    @Published private(set) var people: [Person] = []
    @Published private(set) var unknown: [Group] = []
    /// Pictures examined so far, and the clear faces found in them.
    @Published private(set) var lookedAt = 0
    @Published private(set) var usable = 0
    @Published private(set) var working = false
    /// Off until turned on. `-facesEnabled YES` turns it on for one run without saving the setting.
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: "faces.enabled") || UserDefaults.standard.bool(forKey: "facesEnabled")

    /// Called after anything that can change who a picture shows, so activity titles can follow.
    var onEdit: (() -> Void)?

    private var scanned: Set<String> = []
    private var prints: [UUID: VNFeaturePrintObservation] = [:]

    // Distances between Vision feature prints of aligned face crops. Conservative on purpose:
    // a wrong name is worse than no name.
    /// A sample this close counts towards a match.
    private static let close: Float = 0.42
    /// With only one picture of someone, it has to be this close.
    private static let veryClose: Float = 0.34
    /// The best person must beat the next by at least this much.
    private static let margin: Float = 0.06
    /// Unnamed faces join a group when they're on average this close to it.
    private static let together: Float = 0.45
    /// Pictures kept per person; the clearest stay.
    private static let keep = 40

    static let folder: URL = {
        // `-facesFolder <path>` points at a test library, for checking layouts with stand-in pictures.
        if let test = UserDefaults.standard.string(forKey: "facesFolder") { return URL(fileURLWithPath: test, isDirectory: true) }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Hearth/faces", isDirectory: true)
    }()
    private static var indexFile: URL { folder.appendingPathComponent("index.json") }
    static func cropURL(_ id: UUID) -> URL { folder.appendingPathComponent("crops/\(id.uuidString).jpg") }
    private static func printURL(_ id: UUID) -> URL { folder.appendingPathComponent("prints/\(id.uuidString).print") }

    private init() {
        load()
    }

    // MARK: Turning it on and off

    func setEnabled(_ on: Bool) {
        enabled = on
        UserDefaults.standard.set(on, forKey: "faces.enabled")
    }

    /// Deletes every face, name and picture Hearth has learned. The setting stays as it is.
    func forgetAll() {
        try? FileManager.default.removeItem(at: Self.folder)
        people = []
        unknown = []
        scanned = []
        prints = [:]
        lookedAt = 0
        usable = 0
        onEdit?()
    }

    /// Whether to hold off: the Mac is saving power or running hot.
    private var shouldWait: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled || ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
    }

    func hasScanned(_ url: URL) -> Bool { scanned.contains(url.lastPathComponent) }

    // MARK: Learning

    /// Looks for faces in a saved camera picture. Returns the face to attach to the activity
    /// entry (a named one first), or nil when there's no clear face or it's off.
    func process(_ url: URL, date: Date, itemID: UUID?) async -> Match? {
        guard enabled, !shouldWait, !hasScanned(url) else { return nil }
        working = true
        defer { working = false }
        let found = await Task.detached(priority: .utility) { FaceEngine.detect(url) }.value
        scanned.insert(url.lastPathComponent)
        lookedAt += 1
        var result: Match?
        for face in found {
            guard let observation = Self.unarchive(face.print) else { continue }
            usable += 1
            let sample = Sample(date: date, quality: face.quality, itemID: itemID)
            store(sample, crop: face.crop, print: face.print, observation: observation)
            if let i = bestPerson(for: observation) {
                add(sample, toPerson: i, seen: date)
                if result?.name == nil { result = Match(sample: sample.id, name: people[i].name) }
            } else {
                cluster(sample, observation)
                if result == nil { result = Match(sample: sample.id, name: nil) }
            }
        }
        save()
        return result
    }

    /// Adds the clearest face in each photo to a person, or to the unnamed faces when no
    /// person is given. Returns how many faces were taken.
    @discardableResult
    func addPhotos(_ urls: [URL], to personID: UUID?) async -> Int {
        working = true
        defer { working = false }
        var taken = 0
        for url in urls {
            let found = await Task.detached(priority: .userInitiated) { FaceEngine.detect(url, strict: false) }.value
            guard let face = found.max(by: { $0.quality < $1.quality }), let observation = Self.unarchive(face.print) else { continue }
            let sample = Sample(date: Date(), quality: face.quality, itemID: nil)
            store(sample, crop: face.crop, print: face.print, observation: observation)
            if let personID, let i = people.firstIndex(where: { $0.id == personID }) {
                people[i].samples.append(sample)
            } else if let i = bestPerson(for: observation) {
                people[i].samples.append(sample)
            } else {
                cluster(sample, observation)
            }
            taken += 1
        }
        save()
        onEdit?()
        return taken
    }

    private func store(_ sample: Sample, crop: Data, print: Data, observation: VNFeaturePrintObservation) {
        try? FileManager.default.createDirectory(at: Self.folder.appendingPathComponent("crops"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: Self.folder.appendingPathComponent("prints"), withIntermediateDirectories: true)
        try? crop.write(to: Self.cropURL(sample.id))
        try? print.write(to: Self.printURL(sample.id))
        prints[sample.id] = observation
    }

    private func add(_ sample: Sample, toPerson i: Int, seen: Date) {
        people[i].samples.append(sample)
        people[i].lastSeen = max(people[i].lastSeen ?? seen, seen)
        if people[i].samples.count > Self.keep {
            // Keep the clearest pictures; drop the faintest.
            let sorted = people[i].samples.sorted { $0.quality > $1.quality }
            for s in sorted.dropFirst(Self.keep) { discard(s.id) }
            people[i].samples = Array(sorted.prefix(Self.keep))
        }
    }

    // MARK: Matching

    private func distance(_ a: VNFeaturePrintObservation, _ b: UUID) -> Float? {
        guard let other = prints[b] else { return nil }
        var d: Float = 0
        return (try? a.computeDistance(&d, to: other)) != nil ? d : nil
    }

    /// The person this face belongs to, only when the evidence is clear.
    private func bestPerson(for observation: VNFeaturePrintObservation) -> Int? {
        var scores: [(index: Int, score: Float)] = []
        for (i, person) in people.enumerated() {
            let ds = person.samples.compactMap { distance(observation, $0.id) }.sorted()
            guard let best = ds.first else { continue }
            let closeOnes = ds.filter { $0 < Self.close }.count
            let needed = min(2, ds.count)
            guard closeOnes >= needed, ds.count > 1 || best < Self.veryClose else { continue }
            let top = ds.prefix(3)
            scores.append((i, top.reduce(0, +) / Float(top.count)))
        }
        scores.sort { $0.score < $1.score }
        guard let first = scores.first else { return nil }
        if scores.count > 1, scores[1].score - first.score < Self.margin { return nil }
        return first.index
    }

    private func cluster(_ sample: Sample, _ observation: VNFeaturePrintObservation) {
        var best: (index: Int, score: Float)?
        for (i, group) in unknown.enumerated() {
            let ds = group.samples.compactMap { distance(observation, $0.id) }
            guard !ds.isEmpty else { continue }
            let mean = ds.reduce(0, +) / Float(ds.count)
            if mean < Self.together, mean < (best?.score ?? .infinity) { best = (i, mean) }
        }
        if let best {
            unknown[best.index].samples.append(sample)
        } else {
            unknown.insert(Group(samples: [sample]), at: 0)
        }
    }

    // MARK: Looking things up

    /// The name of whoever a sample belongs to, if it's been named.
    func name(ofSample id: UUID) -> String? {
        people.first { $0.samples.contains { $0.id == id } }?.name
    }

    func person(ofSample id: UUID) -> Person? { people.first { $0.samples.contains { $0.id == id } } }
    func group(ofSample id: UUID) -> Group? { unknown.first { $0.samples.contains { $0.id == id } } }

    func crop(_ id: UUID) -> NSImage? { NSImage(contentsOf: Self.cropURL(id)) }

    // MARK: Editing

    /// Gives an unnamed group a name, joining a person who already has that name.
    func name(_ groupID: UUID, as name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let g = unknown.firstIndex(where: { $0.id == groupID }) else { return }
        let group = unknown.remove(at: g)
        let seen = group.samples.map(\.date).max()
        if let p = people.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            people[p].samples += group.samples
            people[p].lastSeen = [people[p].lastSeen, seen].compactMap { $0 }.max()
        } else {
            people.append(Person(id: group.id, name: name, samples: group.samples, lastSeen: seen))
            people.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        save()
        onEdit?()
    }

    func merge(_ groupID: UUID, into personID: UUID) {
        guard let g = unknown.firstIndex(where: { $0.id == groupID }),
              let p = people.firstIndex(where: { $0.id == personID }) else { return }
        let group = unknown.remove(at: g)
        people[p].samples += group.samples
        people[p].lastSeen = [people[p].lastSeen, group.samples.map(\.date).max()].compactMap { $0 }.max()
        save()
        onEdit?()
    }

    func rename(_ personID: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let p = people.firstIndex(where: { $0.id == personID }) else { return }
        people[p].name = name
        save()
        onEdit?()
    }

    /// Takes a wrong picture out of a person or a group, and forgets it.
    func remove(sample id: UUID) {
        for i in people.indices { people[i].samples.removeAll { $0.id == id } }
        for i in unknown.indices { unknown[i].samples.removeAll { $0.id == id } }
        people.removeAll { $0.samples.isEmpty }
        unknown.removeAll { $0.samples.isEmpty }
        discard(id)
        save()
        onEdit?()
    }

    func delete(person id: UUID) {
        guard let p = people.firstIndex(where: { $0.id == id }) else { return }
        for s in people[p].samples { discard(s.id) }
        people.remove(at: p)
        save()
        onEdit?()
    }

    /// Not someone worth remembering: forget the whole group.
    func dismiss(group id: UUID) {
        guard let g = unknown.firstIndex(where: { $0.id == id }) else { return }
        for s in unknown[g].samples { discard(s.id) }
        unknown.remove(at: g)
        save()
        onEdit?()
    }

    private func discard(_ id: UUID) {
        prints[id] = nil
        try? FileManager.default.removeItem(at: Self.cropURL(id))
        try? FileManager.default.removeItem(at: Self.printURL(id))
    }

    // MARK: Disk

    private func load() {
        guard let data = try? Data(contentsOf: Self.indexFile),
              let index = try? JSONDecoder().decode(Index.self, from: data) else { return }
        people = index.people
        unknown = index.unknown
        scanned = Set(index.scanned)
        lookedAt = index.lookedAt
        usable = index.usable
        for s in index.people.flatMap(\.samples) + index.unknown.flatMap(\.samples) {
            if let data = try? Data(contentsOf: Self.printURL(s.id)), let p = Self.unarchive(data) { prints[s.id] = p }
        }
    }

    private func save() {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let index = Index(people: people, unknown: unknown, scanned: Array(scanned), lookedAt: lookedAt, usable: usable)
        if let data = try? JSONEncoder().encode(index) { try? data.write(to: Self.indexFile, options: .atomic) }
    }

    nonisolated static func unarchive(_ data: Data) -> VNFeaturePrintObservation? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data)
    }
}

/// The Vision work, off the main thread: find faces, keep only clear, frontal, large-enough
/// ones, level each by its eyes, crop it with a margin, and describe it.
enum FaceEngine {
    struct Found: Sendable {
        let crop: Data
        let print: Data
        let quality: Float
    }

    /// Faces narrower than this (in pixels) don't hold enough detail to tell people apart.
    static let smallest: CGFloat = 48

    /// `strict` is for camera pictures; photos you choose yourself are trusted a little more.
    static func detect(_ url: URL, strict: Bool = true) -> [Found] {
        guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { return [] }
        let extent = image.extent
        let handler = VNImageRequestHandler(ciImage: image)
        let rectangles = VNDetectFaceRectanglesRequest()
        guard (try? handler.perform([rectangles])) != nil, let faces = rectangles.results, !faces.isEmpty else { return [] }
        let landmarks = VNDetectFaceLandmarksRequest()
        landmarks.inputFaceObservations = faces
        let quality = VNDetectFaceCaptureQualityRequest()
        quality.inputFaceObservations = faces
        try? handler.perform([landmarks, quality])

        let context = CIContext()
        var out: [Found] = []
        for face in quality.results ?? faces {
            let box = CGRect(x: extent.minX + face.boundingBox.minX * extent.width,
                             y: extent.minY + face.boundingBox.minY * extent.height,
                             width: face.boundingBox.width * extent.width,
                             height: face.boundingBox.height * extent.height)
            let clarity = face.faceCaptureQuality ?? 0.5
            let turned = abs(face.yaw?.doubleValue ?? 0)
            guard box.width >= (strict ? smallest : 32), clarity >= (strict ? 0.3 : 0.15), turned <= (strict ? 0.5 : 0.8) else { continue }

            // Level the face by its eyes when the landmarks are there, by Vision's roll otherwise.
            var angle = face.roll?.doubleValue ?? 0
            let marks = (landmarks.results ?? []).first { abs($0.boundingBox.midX - face.boundingBox.midX) < 0.01 && abs($0.boundingBox.midY - face.boundingBox.midY) < 0.01 }
            if let left = marks?.landmarks?.leftEye, let right = marks?.landmarks?.rightEye {
                let size = extent.size
                let a = centre(left.pointsInImage(imageSize: size)), b = centre(right.pointsInImage(imageSize: size))
                var dx = Double(b.x - a.x), dy = Double(b.y - a.y)
                if dx < 0 { dx = -dx; dy = -dy }
                if dx > 0 { angle = atan2(dy, dx) }
            }
            let c = CGPoint(x: box.midX, y: box.midY)
            let level = CGAffineTransform(translationX: -c.x, y: -c.y)
                .concatenating(CGAffineTransform(rotationAngle: -angle))
                .concatenating(CGAffineTransform(translationX: c.x, y: c.y))
            let side = max(box.width, box.height) * 1.45
            let square = CGRect(x: c.x - side / 2, y: c.y - side / 2, width: side, height: side)
            let scale = 160 / side
            let crop = image.clampedToExtent().transformed(by: level).cropped(to: square)
                .transformed(by: CGAffineTransform(translationX: -square.minX, y: -square.minY).scaledBy(x: scale, y: scale))
            guard let cg = context.createCGImage(crop, from: CGRect(x: 0, y: 0, width: 160, height: 160)) else { continue }

            let describe = VNGenerateImageFeaturePrintRequest()
            describe.imageCropAndScaleOption = .scaleFill
            guard (try? VNImageRequestHandler(cgImage: cg).perform([describe])) != nil,
                  let print = describe.results?.first,
                  let printData = try? NSKeyedArchiver.archivedData(withRootObject: print, requiringSecureCoding: true),
                  let jpeg = NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { continue }
            out.append(Found(crop: jpeg, print: printData, quality: clarity))
        }
        return out
    }

    private static func centre(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }
}
