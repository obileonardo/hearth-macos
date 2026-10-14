import Foundation
import XCTest
@testable import Hearth

final class HomePersistenceTests: XCTestCase {
    /// Every test owns a fresh directory and passes its file explicitly. No app defaults,
    /// Keychain entries, Home Assistant connections or personal files are read or changed.
    private func withFixture(_ body: @MainActor (URL) throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HearthHomeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await MainActor.run { try body(directory.appendingPathComponent("homes.json")) }
    }

    func testPrimaryHomeCannotBeDemotedOrAssignedDevices() async throws {
        try await withFixture { file in
            let list = HomeList(file: file)
            let mainID = list.main.id
            let office = list.add(name: "Office", style: .office)
            list.link("speaker-office", to: office.id)
            var edited = list.main
            edited.name = "Family home"
            edited.isMain = false
            edited.devices = ["speaker-office"]
            list.update(edited)

            let restored = HomeList(file: file)
            XCTAssertEqual(restored.main.id, mainID)
            XCTAssertEqual(restored.main.name, "Family home")
            XCTAssertTrue(restored.main.named)
            XCTAssertTrue(restored.main.devices.isEmpty)
            XCTAssertEqual(restored.home(of: "speaker-office").id, office.id)
            XCTAssertEqual(restored.homes.filter(\.isMain).count, 1)
        }
    }

    func testSecondaryHomeCannotBePromotedByEditing() async throws {
        try await withFixture { file in
            let list = HomeList(file: file)
            let mainID = list.main.id
            var office = list.add(name: "Office", style: .office)
            office.isMain = true
            office.name = "Studio"
            office.devices = ["device-studio"]
            list.update(office)

            let restored = HomeList(file: file)
            XCTAssertEqual(restored.main.id, mainID)
            XCTAssertEqual(restored.others.first?.id, office.id)
            XCTAssertEqual(restored.others.first?.name, "Studio")
            XCTAssertEqual(restored.others.first?.devices, ["device-studio"])
            XCTAssertFalse(restored.others.first?.isMain ?? true)
        }
    }

    func testRemovingPrimaryHomePreservesAllHomesAndAssignments() async throws {
        try await withFixture { file in
            let list = HomeList(file: file)
            let office = list.add(name: "Office", style: .office)
            list.link("computer", to: office.id)
            let original = list.homes
            list.remove(list.main.id)
            XCTAssertEqual(list.homes, original)
            XCTAssertEqual(HomeList(file: file).homes, original)
        }
    }

    func testRelinkingMovesDeviceOnceAndMainUnlinksIt() async throws {
        try await withFixture { file in
            let list = HomeList(file: file)
            let office = list.add(name: "Office", style: .office)
            let flat = list.add(name: "Flat", style: .apartment)
            list.link("shared-speaker", to: office.id)
            list.link("shared-speaker", to: flat.id)
            list.link("shared-speaker", to: flat.id)
            XCTAssertEqual(list.home(of: "shared-speaker").id, flat.id)
            XCTAssertEqual(list.homes.flatMap(\.devices).filter { $0 == "shared-speaker" }.count, 1)
            XCTAssertFalse(list.homes.first { $0.id == office.id }!.devices.contains("shared-speaker"))

            list.link("shared-speaker", to: list.main.id)
            let restored = HomeList(file: file)
            XCTAssertEqual(restored.home(of: "shared-speaker").id, restored.main.id)
            XCTAssertFalse(restored.homes.flatMap(\.devices).contains("shared-speaker"))
            XCTAssertEqual(restored.others.map(\.id), [office.id, flat.id])
        }
    }

    func testRemovingSecondaryHomeReturnsOnlyItsDevicesToMain() async throws {
        try await withFixture { file in
            let list = HomeList(file: file)
            let office = list.add(name: "Office", style: .office)
            let flat = list.add(name: "Flat", style: .apartment)
            list.link("office-device", to: office.id)
            list.link("flat-device", to: flat.id)
            list.remove(office.id)

            let restored = HomeList(file: file)
            XCTAssertEqual(restored.home(of: "office-device").id, restored.main.id)
            XCTAssertEqual(restored.home(of: "flat-device").id, flat.id)
            XCTAssertEqual(restored.others.map(\.id), [flat.id])
        }
    }

    func testHandNamedMainHomeDoesNotFollowLaterLocationNames() async throws {
        try await withFixture { file in
            let list = HomeList(file: file)
            list.adoptLocationName("Home Assistant location")
            XCTAssertEqual(list.main.name, "Home Assistant location")
            var main = list.main
            main.name = "Our house"
            list.update(main)
            list.adoptLocationName("A different location")
            list.adoptLocationName("")
            XCTAssertEqual(HomeList(file: file).main.name, "Our house")
        }
    }

    func testMissingPrimaryAddsFallbackWithoutDiscardingSavedHome() async throws {
        try await withFixture { file in
            let office = Home(name: "Existing office", style: .office, devices: ["existing-device"])
            try JSONEncoder().encode([office]).write(to: file)
            let originalData = try Data(contentsOf: file)
            let list = HomeList(file: file)
            XCTAssertTrue(list.main.isMain)
            XCTAssertEqual(list.others, [office])
            XCTAssertEqual(list.home(of: "existing-device").id, office.id)
            // Merely opening a file never rewrites it.
            XCTAssertEqual(try Data(contentsOf: file), originalData)
        }
    }

    func testExplicitFileKeepsSeparateFixtureHomesIndependent() async throws {
        try await withFixture { file in
            let siblingFile = file.deletingLastPathComponent().appendingPathComponent("another-home-list.json")
            let original = [Home(name: "Separate home", isMain: true)]
            let data = try JSONEncoder().encode(original)
            try data.write(to: siblingFile)
            let list = HomeList(file: file)
            _ = list.add(name: "New office", style: .office)
            XCTAssertEqual(try Data(contentsOf: siblingFile), data)
            XCTAssertEqual(HomeList(file: siblingFile).homes, original)
            XCTAssertNotEqual(list.main.id, original[0].id)
        }
    }
}
