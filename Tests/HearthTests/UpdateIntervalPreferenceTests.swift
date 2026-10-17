import Foundation
import XCTest
@testable import Hearth

final class UpdateIntervalPreferenceTests: XCTestCase {
    func testDefaultsAndExistingLimitsAreRetained() {
        XCTAssertEqual(UpdateIntervalPreference.cameraRefresh.defaultSeconds, 60)
        XCTAssertEqual(UpdateIntervalPreference.statusRotation.defaultSeconds, 6)
        XCTAssertEqual(UpdateIntervalPreference.cameraRefresh.range, 30...480)
        XCTAssertEqual(UpdateIntervalPreference.statusRotation.range, 4...60)
        XCTAssertEqual(UpdateIntervalPreference.cameraRefresh.seconds(for: 120), 120)
        XCTAssertEqual(UpdateIntervalPreference.statusRotation.seconds(for: 20), 20)
    }

    func testMenusIncludeOldChoicesAndRequestedMaximums() {
        XCTAssertEqual(UpdateIntervalPreference.cameraRefresh.choices(including: 60),
                       ["30", "60", "90", "120", "180", "240", "360", "480"])
        XCTAssertEqual(UpdateIntervalPreference.statusRotation.choices(including: 6),
                       ["4", "6", "10", "20", "30", "45", "60"])
    }

    func testCustomInRangeChoiceRemainsVisibleAndSelected() {
        XCTAssertEqual(UpdateIntervalPreference.cameraRefresh.label(for: 45), "45")
        XCTAssertTrue(UpdateIntervalPreference.cameraRefresh.choices(including: 45).contains("45"))
        XCTAssertEqual(UpdateIntervalPreference.statusRotation.label(for: 15), "15")
        XCTAssertTrue(UpdateIntervalPreference.statusRotation.choices(including: 15).contains("15"))
    }

    func testFractionalChoiceRoundTripsWithoutIntegerTruncation() {
        for (policy, value) in [(UpdateIntervalPreference.cameraRefresh, 90.125), (.statusRotation, 12.5)] {
            let label = policy.label(for: value)
            XCTAssertEqual(policy.seconds(fromChoice: label), value)
            XCTAssertTrue(policy.choices(including: value).contains(label))
        }
    }

    func testNonfiniteAndNonpositiveValuesUseDefaultsBeforeFormatting() {
        for policy in UpdateIntervalPreference.allCases {
            for value: Double in [.nan, .infinity, -.infinity, 0, -0.0, -1, -.greatestFiniteMagnitude] {
                XCTAssertEqual(policy.seconds(for: value), policy.defaultSeconds)
                XCTAssertEqual(policy.label(for: value), policy.label(for: policy.defaultSeconds))
            }
        }
    }

    func testFiniteExtremesAreBoundedBeforeFormattingAndSleep() {
        for policy in UpdateIntervalPreference.allCases {
            XCTAssertEqual(policy.seconds(for: .greatestFiniteMagnitude), policy.range.upperBound)
            XCTAssertEqual(policy.seconds(for: .leastNonzeroMagnitude), policy.range.lowerBound)
            XCTAssertEqual(policy.label(for: .greatestFiniteMagnitude), policy.label(for: policy.range.upperBound))
            for value: Double in [0.001, 1, 4, 30, 60, 480, 1e300] {
                let effective = policy.seconds(for: value)
                XCTAssertTrue(effective.isFinite)
                XCTAssertTrue(policy.range.contains(effective))
            }
        }
    }

    func testInvalidMenuTokensCannotBePersistedThroughSelection() {
        for policy in UpdateIntervalPreference.allCases {
            for token in ["", "not a number", "nan", "inf", "-inf", "0", "-10", "1e300"] {
                XCTAssertNil(policy.seconds(fromChoice: token))
            }
            XCTAssertNil(policy.seconds(fromChoice: String(policy.range.lowerBound - 1)))
            XCTAssertNil(policy.seconds(fromChoice: String(policy.range.upperBound + 1)))
        }
    }

    func testChoicesAreUniqueSortedAndUseTheSameSafePolicyAsConsumers() {
        for policy in UpdateIntervalPreference.allCases {
            for value: Double in [.nan, .infinity, -1, 1, 45, 45.5, 1e300] {
                let choices = policy.choices(including: value)
                XCTAssertEqual(Set(choices).count, choices.count)
                let values = choices.compactMap { policy.seconds(fromChoice: $0) }
                XCTAssertEqual(values.count, choices.count)
                XCTAssertEqual(values, values.sorted())
                XCTAssertTrue(choices.contains(policy.label(for: value)))
            }
        }
    }

    func testReadingMissingInvalidOrOutOfRangePreferencesDoesNotRewriteThem() throws {
        let name = "Hearth.UpdateIntervalFixture.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        for policy in UpdateIntervalPreference.allCases {
            XCTAssertNil(defaults.object(forKey: policy.key))
            XCTAssertEqual(policy.saved(in: defaults), policy.defaultSeconds)
            XCTAssertNil(defaults.object(forKey: policy.key))
            for value: Double in [-1, 1, 45.5, 1e300] {
                defaults.set(value, forKey: policy.key)
                XCTAssertEqual(policy.saved(in: defaults), policy.seconds(for: value))
                XCTAssertEqual(defaults.object(forKey: policy.key) as? Double, value)
            }
            defaults.set("invalid", forKey: policy.key)
            XCTAssertEqual(policy.saved(in: defaults), policy.defaultSeconds)
            XCTAssertEqual(defaults.string(forKey: policy.key), "invalid")
        }
    }
}
