import Foundation
import XCTest
@testable import Hearth

final class NavigationGlassPreferenceTests: XCTestCase {
    func testDefaultIsBetweenClearAndOpaque() {
        XCTAssertEqual(NavigationGlassPreference.defaultValue, 0.55)
    }
    func testFiniteValuesStayInRange() {
        XCTAssertEqual(NavigationGlassPreference.normalized(-1), 0)
        XCTAssertEqual(NavigationGlassPreference.normalized(2), 1)
        XCTAssertEqual(NavigationGlassPreference.normalized(0.35), 0.35)
    }
    func testInvalidValuesUseTheDefault() {
        for value: Double in [.nan, .infinity, -.infinity] {
            XCTAssertEqual(NavigationGlassPreference.normalized(value), NavigationGlassPreference.defaultValue)
        }
    }
    func testReduceTransparencyOverridesTheSurface() {
        XCTAssertEqual(NavigationGlassPreference.effective(0.2, reduceTransparency: true, increasedContrast: false), 1)
    }
    func testIncreasedContrastOverridesTheSurface() {
        XCTAssertEqual(NavigationGlassPreference.effective(0.2, reduceTransparency: false, increasedContrast: true), 1)
    }
    func testOrdinaryAppearanceKeepsTheChosenValue() {
        XCTAssertEqual(NavigationGlassPreference.effective(0.8, reduceTransparency: false, increasedContrast: false), 0.8)
    }
    func testChosenOpacityPersistsInAnIsolatedPreferencesDomain() {
        let domain = "HearthTests.NavigationGlass." + UUID().uuidString
        let first = UserDefaults(suiteName: domain)!
        defer { first.removePersistentDomain(forName: domain) }
        first.set(0.8, forKey: NavigationGlassPreference.key)
        let reopened = UserDefaults(suiteName: domain)!
        XCTAssertEqual(reopened.double(forKey: NavigationGlassPreference.key), 0.8)
    }

}
