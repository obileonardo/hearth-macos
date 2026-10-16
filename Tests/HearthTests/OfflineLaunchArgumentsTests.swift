import XCTest
@testable import Hearth

final class OfflineLaunchArgumentsTests: XCTestCase {
    private let flags = ["--render-preview", "--render-cars", "--render-art"]

    func testEachExporterRequiresItsOutputPathInsteadOfNormalStartup() {
        for flag in flags {
            XCTAssertThrowsError(try OfflineLaunchArguments.validate(["Hearth", flag])) { error in
                XCTAssertEqual(error as? OfflineLaunchArguments.Invalid, .missingDestination(flag))
            }
        }
    }

    func testEmptyWhitespaceAndFollowingOptionsAreNotDestinations() {
        for flag in flags {
            for destination in ["", " ", "\n", "--review-rooms", "--render-art", "-appearance"] {
                XCTAssertThrowsError(try OfflineLaunchArguments.validate(["Hearth", flag, destination])) { error in
                    XCTAssertEqual(error as? OfflineLaunchArguments.Invalid, .missingDestination(flag))
                }
            }
        }
    }

    func testNormalExportPathsPreserveExistingCommands() throws {
        for flag in flags {
            for destination in ["/tmp/hearth-preview", "./-preview", "./preview images", "preview"] {
                try OfflineLaunchArguments.validate(["Hearth", flag, destination])
                try OfflineLaunchArguments.validate(["Hearth", "-appearance", "dark", flag, destination])
            }
        }
    }

    func testLaterMalformedExporterCannotHideBehindAnEarlierValidOne() {
        XCTAssertThrowsError(try OfflineLaunchArguments.validate(["Hearth", "--render-preview", "/tmp/fixture", "--render-art"])) { error in
            XCTAssertEqual(error as? OfflineLaunchArguments.Invalid, .missingDestination("--render-art"))
        }
    }

    func testNormalStartupAndDestinationFreeReviewModesRemainValid() throws {
        for arguments in [["Hearth"], ["Hearth", "--window"], ["Hearth", "--review-rooms"], ["Hearth", "--review-climate"], ["Hearth", "--review-tooltips"]] {
            try OfflineLaunchArguments.validate(arguments)
        }
    }
}
