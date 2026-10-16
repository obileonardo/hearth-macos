import XCTest
import Security
@testable import Hearth

final class KeychainMutationTests: XCTestCase {
    func testExistingValueIsUpdatedWithoutDeletingIt() throws {
        var updates = 0
        try KeychainMutation.write("fixture", update: { _ in updates += 1; return errSecSuccess },
            add: { _ in XCTFail("No add"); return errSecSuccess }, delete: { XCTFail("No delete"); return errSecSuccess })
        XCTAssertEqual(updates, 1)
    }
    func testDeniedUpdateDoesNotDeleteOrTryToAdd() {
        XCTAssertThrowsError(try KeychainMutation.write("fixture", update: { _ in errSecAuthFailed },
            add: { _ in XCTFail("No add"); return errSecSuccess }, delete: { XCTFail("No delete"); return errSecSuccess }))
    }
    func testMissingValueAddsOnce() throws {
        var adds = 0
        try KeychainMutation.write("fixture", update: { _ in errSecItemNotFound },
            add: { _ in adds += 1; return errSecSuccess }, delete: { XCTFail("No delete"); return errSecSuccess })
        XCTAssertEqual(adds, 1)
    }
    func testFailedAddIsReportedWithoutDeletion() {
        XCTAssertThrowsError(try KeychainMutation.write("fixture", update: { _ in errSecItemNotFound },
            add: { _ in errSecInteractionNotAllowed }, delete: { XCTFail("No delete"); return errSecSuccess }))
    }
    func testConcurrentInsertRetriesUpdateOnce() throws {
        var updates = 0
        try KeychainMutation.write("fixture", update: { _ in updates += 1; return updates == 1 ? errSecItemNotFound : errSecSuccess },
            add: { _ in errSecDuplicateItem }, delete: { XCTFail("No delete"); return errSecSuccess })
        XCTAssertEqual(updates, 2)
    }
    func testExplicitRemovalAllowsAlreadyMissingValue() throws {
        for result in [errSecSuccess, errSecItemNotFound] {
            try KeychainMutation.write(nil, update: { _ in XCTFail("No update"); return errSecSuccess },
                add: { _ in XCTFail("No add"); return errSecSuccess }, delete: { result })
        }
    }
    func testExplicitRemovalFailurePropagates() {
        XCTAssertThrowsError(try KeychainMutation.write(nil, update: { _ in errSecSuccess },
            add: { _ in errSecSuccess }, delete: { errSecAuthFailed }))
    }
}
