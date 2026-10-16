import AppKit
import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// A staged new avatar never replaces or deletes the previous selection until
/// its copied bytes validate and a tiny selection record commits atomically.
@MainActor
enum AvatarImport {
    private static let selectionName = ".selected-avatar.json"
    enum Invalid: LocalizedError {
        case unsupported, unreadableMedia
        var errorDescription: String? {
            switch self {
            case .unsupported: "Choose a supported photo, GIF or video file."
            case .unreadableMedia: "The selected file could not be read as a picture or video."
            }
        }
    }

    static func selected(in folder: URL) -> URL? {
        let manifest = folder.appendingPathComponent(selectionName)
        if let data = try? Data(contentsOf: manifest), let name = try? JSONDecoder().decode(String.self, from: data) {
            if name.isEmpty { return nil }
            if name == URL(fileURLWithPath: name).lastPathComponent, !name.hasPrefix(".") {
                let candidate = folder.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            }
            return nil // Never resolve a corrupt record outside this private folder.
        }
        // Existing installations predate the selection record.
        return (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasPrefix("avatar.") && !$0.hasDirectoryPath }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }.first
            // Enumeration may resolve /var into /private/var. Preserve the
            // caller's folder identity, matching the manifest path and cleanup.
            .map { folder.appendingPathComponent($0.lastPathComponent) }
    }

    static func writeSelection(_ name: String, in folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(name).write(to: folder.appendingPathComponent(selectionName), options: .atomic)
    }

    static func stage(_ source: URL, in folder: URL,
                      stillCurrent: @MainActor () -> Bool = { true },
                      copy: @MainActor (URL, URL) throws -> Void = { try FileManager.default.copyItem(at: $0, to: $1) },
                      validate: @MainActor (URL) async throws -> Void = validateMedia,
                      commit: @MainActor (String, URL) throws -> Void = writeSelection) async throws -> URL {
        let source = source.resolvingSymlinksInPath()
        guard source.isFileURL, let type = UTType(filenameExtension: source.pathExtension),
              type.conforms(to: .image) || type.conforms(to: .movie),
              (try? source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { throw Invalid.unsupported }
        try Task.checkCancellation()
        guard stillCurrent() else { throw CancellationError() }
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let suffix = source.pathExtension.lowercased()
        let id = UUID().uuidString
        let staged = folder.appendingPathComponent(".import-" + id + "." + suffix)
        let final = folder.appendingPathComponent("avatar-" + id + "." + suffix)
        var committed = false
        defer {
            try? fm.removeItem(at: staged)
            if !committed { try? fm.removeItem(at: final) }
        }
        try copy(source, staged)
        try await validate(staged)
        try Task.checkCancellation()
        guard stillCurrent() else { throw CancellationError() }
        try fm.moveItem(at: staged, to: final)
        try commit(final.lastPathComponent, folder)
        committed = true
        return final
    }

    static func validateMedia(_ url: URL) async throws {
        guard let type = UTType(filenameExtension: url.pathExtension) else { throw Invalid.unsupported }
        if type.conforms(to: .movie) {
            let asset = AVURLAsset(url: url)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let duration = try await asset.load(.duration)
            guard !tracks.isEmpty, duration.seconds.isFinite, duration.seconds > 0 else { throw Invalid.unreadableMedia }
        } else {
            guard let image = NSImage(contentsOf: url), image.isValid,
                  image.size.width > 0, image.size.height > 0 else { throw Invalid.unreadableMedia }
        }
    }
}
