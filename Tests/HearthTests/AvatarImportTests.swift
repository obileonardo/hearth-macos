import AppKit
import Foundation
import XCTest
@testable import Hearth

@MainActor
final class AvatarImportTests: XCTestCase {
    private struct Fixture {
        let root: URL
        let folder: URL
        let old: URL
        let source: URL
    }
    private func fixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HearthAvatarTests-" + UUID().uuidString, isDirectory: true)
        let folder = root.appendingPathComponent("avatar", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let old = folder.appendingPathComponent("avatar.png")
        let source = root.appendingPathComponent("new.png")
        try Data("previous synthetic avatar".utf8).write(to: old)
        try Data("incoming synthetic fixture".utf8).write(to: source)
        return Fixture(root: root, folder: folder, old: old, source: source)
    }
    private func assertOldPreserved(_ fixture: Fixture, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try Data(contentsOf: fixture.old), Data("previous synthetic avatar".utf8), file: file, line: line)
        XCTAssertEqual(AvatarImport.selected(in: fixture.folder), fixture.old, file: file, line: line)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.folder.path), ["avatar.png"], file: file, line: line)
    }

    func testCopyFailurePreservesPriorAvatarAndSelection() async throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        do {
            _ = try await AvatarImport.stage(f.source, in: f.folder,
                copy: { _, _ in throw CocoaError(.fileReadNoPermission) },
                validate: { _ in XCTFail("No validation after failed copy") },
                commit: { _, _ in XCTFail("No selection change") })
            XCTFail("Copy failure must propagate")
        } catch { XCTAssertTrue(error is CocoaError) }
        try assertOldPreserved(f)
    }

    func testValidationFailureCleansStagingWithoutRemovingOldAvatar() async throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        do {
            _ = try await AvatarImport.stage(f.source, in: f.folder,
                validate: { _ in throw AvatarImport.Invalid.unreadableMedia },
                commit: { _, _ in XCTFail("No selection change") })
            XCTFail("Validation failure must propagate")
        } catch { XCTAssertTrue(error is AvatarImport.Invalid) }
        try assertOldPreserved(f)
        XCTAssertEqual(try Data(contentsOf: f.source), Data("incoming synthetic fixture".utf8))
    }

    func testSelectionWriteFailureRollsBackOnlyTheNewFile() async throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        do {
            _ = try await AvatarImport.stage(f.source, in: f.folder, validate: { _ in },
                commit: { _, _ in throw CocoaError(.fileWriteNoPermission) })
            XCTFail("Commit failure must propagate")
        } catch { XCTAssertTrue(error is CocoaError) }
        try assertOldPreserved(f)
    }

    func testSupersededChoiceCannotCommitAfterValidation() async throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        var current = true
        do {
            _ = try await AvatarImport.stage(f.source, in: f.folder, stillCurrent: { current },
                validate: { _ in current = false }, commit: { _, _ in XCTFail("Obsolete choice cannot commit") })
            XCTFail("Superseded choice must stop")
        } catch { XCTAssertTrue(error is CancellationError) }
        try assertOldPreserved(f)
    }

    func testSuccessfulStagingValidatesCopiedBytesBeforeCommittingSelection() async throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        var validated = false
        let target = try await AvatarImport.stage(f.source, in: f.folder, validate: { staged in
            XCTAssertNotEqual(staged, f.source)
            XCTAssertTrue(staged.lastPathComponent.hasPrefix(".import-"))
            XCTAssertEqual(try Data(contentsOf: staged), Data("incoming synthetic fixture".utf8))
            XCTAssertEqual(AvatarImport.selected(in: f.folder), f.old)
            validated = true
        }, commit: { name, folder in
            XCTAssertTrue(validated)
            XCTAssertTrue(FileManager.default.fileExists(atPath: f.old.path))
            try AvatarImport.writeSelection(name, in: folder)
        })
        XCTAssertEqual(AvatarImport.selected(in: f.folder), target)
        XCTAssertEqual(try Data(contentsOf: target), Data("incoming synthetic fixture".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.old.path))
    }

    func testStoreImportFailureIsVisibleAndKeepsExistingDisplayedAvatar() async throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let store = AvatarStore(folder: f.folder)
        await store.use(f.source) // Invalid image bytes: real local media validation only.
        XCTAssertEqual(store.url, f.old)
        XCTAssertNotNil(store.importError)
        try assertOldPreserved(f)
        store.dismissImportError()
        XCTAssertNil(store.importError)
    }

    func testStoreSuccessPersistsNewSelectionAndThenRemovesPriorAvatar() async throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.bitmapData?.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        for x in 0..<2 { for y in 0..<2 { bitmap.setColor(.blue, atX: x, y: y) } }
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: f.source)
        let store = AvatarStore(folder: f.folder)
        await store.use(f.source)
        let selected = try XCTUnwrap(store.url)
        XCTAssertNotEqual(selected, f.old)
        XCTAssertEqual(try Data(contentsOf: selected), png)
        XCTAssertNil(store.importError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.old.path))
        XCTAssertEqual(AvatarStore(folder: f.folder).url, selected)
    }

    func testExplicitRemovalDoesNotReselectAnOlderRetainedFile() async throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let retained = f.folder.appendingPathComponent("retained.png")
        try Data("older retained synthetic fixture".utf8).write(to: retained)
        let store = AvatarStore(folder: f.folder)
        XCTAssertEqual(store.url, f.old)
        store.remove()
        XCTAssertNil(store.url)
        XCTAssertNil(AvatarStore(folder: f.folder).url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: retained.path))
    }

    func testSelectionRecordCannotResolveOutsideItsAvatarFolder() async throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        try AvatarImport.writeSelection("../new.png", in: f.folder)
        XCTAssertNil(AvatarImport.selected(in: f.folder))
    }
}
