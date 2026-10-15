import AppKit
import SwiftUI
import XCTest
@testable import Hearth

final class AppearancePreferenceTests: XCTestCase {
    @MainActor
    func testDocumentationControlsAreNotEnabledInNormalViews() {
        XCTAssertFalse(EnvironmentValues().hearthDocumentationPreview)
    }
    func testSavedChoiceUsesIsolatedPreferencesAndFallsBackToSystem() throws {
        let name = "Hearth.AppearanceFixture.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(AppearanceChoice.saved(in: defaults), .system)
        defaults.set("light", forKey: AppearanceChoice.preferenceKey)
        XCTAssertEqual(AppearanceChoice.saved(in: defaults), .light)
        defaults.set("dark", forKey: AppearanceChoice.preferenceKey)
        XCTAssertEqual(AppearanceChoice.saved(in: defaults), .dark)
        defaults.set("invalid-old-value", forKey: AppearanceChoice.preferenceKey)
        XCTAssertEqual(AppearanceChoice.saved(in: defaults), .system)
    }

    func testLightAndDarkAgreeAcrossNativeAndSwiftUITraits() {
        XCTAssertEqual(AppearanceChoice.light.appearanceName, .aqua)
        XCTAssertEqual(AppearanceChoice.light.preferredColorScheme, .light)
        XCTAssertEqual(AppearanceChoice.dark.appearanceName, .darkAqua)
        XCTAssertEqual(AppearanceChoice.dark.preferredColorScheme, .dark)
        XCTAssertNil(AppearanceChoice.system.appearanceName)
        XCTAssertNil(AppearanceChoice.system.preferredColorScheme)
    }

    @MainActor
    func testNativeOverrideCanReturnToSystemInheritance() {
        XCTAssertEqual(AppearanceChoice.light.nativeAppearance?.name, .aqua)
        XCTAssertEqual(AppearanceChoice.dark.nativeAppearance?.name, .darkAqua)
        XCTAssertNil(AppearanceChoice.system.nativeAppearance)
        // Resolving the choice does not alter NSApp or any user's preferences.
    }

    @MainActor
    func testPinnedCardStartsAsOriginalHeaderReachesTop() {
        XCTAssertEqual(PinnedTitleBar.progress(headerTop: nil), 0)
        XCTAssertEqual(PinnedTitleBar.progress(headerTop: 26), 0)
        XCTAssertEqual(PinnedTitleBar.progress(headerTop: 1), 0)
        XCTAssertEqual(PinnedTitleBar.progress(headerTop: 0), 0)
        XCTAssertEqual(PinnedTitleBar.progress(headerTop: -9), 0.5)
        XCTAssertEqual(PinnedTitleBar.progress(headerTop: -18), 1)
        XCTAssertEqual(PinnedTitleBar.progress(headerTop: -200), 1)
    }
}
