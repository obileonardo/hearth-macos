import Foundation
import XCTest
@testable import Hearth

final class RoomsExplorerTests: XCTestCase {
    private let floors = [
        Floor(id: "upper", name: "Upstairs", level: 1),
        Floor(id: "ground", name: "Ground", level: 0),
        Floor(id: "empty", name: "Roof", level: 2)
    ]
    private let rooms = [
        Area(id: "office", name: "Office", icon: nil, floorID: "ground"),
        Area(id: "bedroom", name: "Bedroom", icon: nil, floorID: "upper"),
        Area(id: "empty-room", name: "Guest room", icon: nil, floorID: "upper"),
        Area(id: "no-floor", name: "Garden", icon: nil, floorID: nil),
        Area(id: "orphan-floor", name: "Lab", icon: nil, floorID: "removed-floor")
    ]

    func testDefaultAndUnknownSavedLayoutsPreserveOriginalOverview() {
        XCTAssertEqual(RoomsLayoutPreference.saved("overview"), .overview)
        XCTAssertEqual(RoomsLayoutPreference.saved("interactive"), .interactive)
        XCTAssertEqual(RoomsLayoutPreference.saved("old-unknown-choice"), .overview)
    }

    func testLayoutChoicePersistsOnlyInAnIsolatedFixtureDomain() throws {
        let domain = "HearthTests.RoomsLayout." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(RoomsLayoutPreference.interactive.rawValue, forKey: RoomsLayoutPreference.key)
        let reopened = try XCTUnwrap(UserDefaults(suiteName: domain))
        XCTAssertEqual(RoomsLayoutPreference.saved(reopened.string(forKey: RoomsLayoutPreference.key) ?? ""), .interactive)
    }

    func testFloorsSortByLevelAndRetainEmptyFloors() {
        XCTAssertEqual(RoomsExplorerNavigation.floors(floors).map(\.id), ["ground", "upper", "empty"])
    }

    func testAllRoomsIncludeEmptyRoomsAndUnassignedDevices() {
        XCTAssertEqual(RoomsExplorerNavigation.items(areas: rooms, floors: floors, scope: .all, hasUnassignedDevices: true),
                       [.area("bedroom"), .area("no-floor"), .area("empty-room"), .area("orphan-floor"), .area("office"), .unassigned])
    }

    func testSelectedFloorKeepsOnlyItsActualRooms() {
        XCTAssertEqual(RoomsExplorerNavigation.items(areas: rooms, floors: floors, scope: .floor("upper"), hasUnassignedDevices: true),
                       [.area("bedroom"), .area("empty-room")])
        XCTAssertTrue(RoomsExplorerNavigation.items(areas: rooms, floors: floors, scope: .floor("empty"), hasUnassignedDevices: true).isEmpty)
    }

    func testNoFloorIncludesOrphanAssignmentsAndDevicesWithoutRoom() {
        XCTAssertTrue(RoomsExplorerNavigation.hasUnassignedRooms(rooms, floors: floors, hasUnassignedDevices: false))
        XCTAssertEqual(RoomsExplorerNavigation.items(areas: rooms, floors: floors, scope: .unassigned, hasUnassignedDevices: true),
                       [.area("no-floor"), .area("orphan-floor"), .unassigned])
    }

    func testUnassignedSectionIsNotInventedWhenEverythingIsAssigned() {
        let assigned = rooms.filter { $0.id == "office" }
        XCTAssertFalse(RoomsExplorerNavigation.hasUnassignedRooms(assigned, floors: floors, hasUnassignedDevices: false))
        XCTAssertEqual(RoomsExplorerNavigation.items(areas: assigned, floors: floors, scope: .all, hasUnassignedDevices: false), [.area("office")])
    }

    func testRemovedFloorsAndUnassignedScopeFallBackToAll() {
        XCTAssertEqual(RoomsExplorerNavigation.resolvedScope(.floor("deleted"), floors: floors, hasUnassignedRooms: false), .all)
        XCTAssertEqual(RoomsExplorerNavigation.resolvedScope(.floor("ground"), floors: floors, hasUnassignedRooms: false), .floor("ground"))
        XCTAssertEqual(RoomsExplorerNavigation.resolvedScope(.unassigned, floors: floors, hasUnassignedRooms: false), .all)
    }

    func testSelectionSurvivesRefreshAndFallsBackWhenRoomIsRemoved() {
        let visible: [RoomsExplorerItem] = [.area("office"), .area("bedroom")]
        XCTAssertEqual(RoomsExplorerNavigation.selection(.area("bedroom"), in: visible), .area("bedroom"))
        XCTAssertEqual(RoomsExplorerNavigation.selection(.area("deleted"), in: visible), .area("office"))
        XCTAssertNil(RoomsExplorerNavigation.selection(.area("office"), in: []))
    }

    func testRoomIDsCannotCollideWithTheUnassignedDestination() {
        XCTAssertNotEqual(RoomsExplorerItem.area("unassigned"), .unassigned)
        XCTAssertEqual(RoomsExplorerItem.area("unassigned").areaID, "unassigned")
        XCTAssertNil(RoomsExplorerItem.unassigned.areaID)
    }

    func testNavigationDoesNotMutateAreaOrFloorAssignments() {
        let originalRooms = rooms
        let originalFloors = floors
        _ = RoomsExplorerNavigation.items(areas: rooms, floors: floors, scope: .unassigned, hasUnassignedDevices: true)
        XCTAssertEqual(rooms, originalRooms)
        XCTAssertEqual(floors, originalFloors)
    }

    @MainActor
    func testExplorerStateHoldsNavigationWithoutSavingRegistryAssignments() {
        let state = RoomsExplorerState()
        XCTAssertEqual(state.floorScope, .all)
        XCTAssertNil(state.selectedRoom)
        state.floorScope = .floor("upper")
        state.selectedRoom = .area("bedroom")
        XCTAssertEqual(state.floorScope, .floor("upper"))
        XCTAssertEqual(state.selectedRoom, .area("bedroom"))
    }
}
