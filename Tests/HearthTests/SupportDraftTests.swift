import Foundation
import XCTest
@testable import Hearth

final class SupportDraftTests: XCTestCase {
    func testSupportDraftDefaultsToUsefulTemplateWithoutDiagnostics() {
        let draft = SupportDraft(kind: .support)
        XCTAssertEqual(draft.subject, "Hearth — Support request")
        XCTAssertTrue(draft.body.contains("I’d like help with:"))
        XCTAssertFalse(draft.body.contains("version:"))
    }

    func testBugDraftContainsReproductionAndExpectedActualPrompts() {
        let draft = SupportDraft(kind: .bug)
        for prompt in ["Steps to reproduce:", "Expected result:", "Actual result:", "How often it happens:"] {
            XCTAssertTrue(draft.body.contains(prompt))
        }
    }

    func testVersionInformationIsOnlyIncludedWhenExplicitlyProvided() {
        let info = "Hearth version: 1.2 (3)\nmacOS version: 14.6.1\n"
        let draft = SupportDraft(kind: .bug, versions: info)
        XCTAssertTrue(draft.body.hasSuffix(info))
        XCTAssertFalse(SupportDraft(kind: .bug).body.contains(info))
    }

    func testMailURLPreservesReservedCharactersAndLineBreaksWithoutExtraRecipients() throws {
        var draft = SupportDraft(kind: .support)
        draft.subject = "A & B + C # D — help"
        draft.body = "Line one\nbody=value&cc=other@example.invalid + # ?"
        let url = try XCTUnwrap(draft.mailtoURL)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "mailto")
        XCTAssertEqual(components.path, "contact@elvisobi.com")
        XCTAssertNil(components.fragment)
        XCTAssertEqual(components.queryItems?.map(\.name), ["subject", "body"])
        XCTAssertEqual(components.queryItems?.first?.value, draft.subject)
        XCTAssertEqual(components.queryItems?.last?.value, draft.body)
    }

    func testCopiedDraftContainsEditedSubjectAndBody() {
        var draft = SupportDraft(kind: .bug)
        draft.subject = "Edited subject"
        draft.body = "My edited message"
        XCTAssertEqual(draft.clipboardText, "To: contact@elvisobi.com\nSubject: Edited subject\n\nMy edited message")
    }

    func testOutgoingVersionsCanBeTurnedOffWithoutChangingEditedDraft() {
        var draft = SupportDraft(kind: .support)
        draft.body = "Edited message"
        let versions = "Hearth version: 1.2\nmacOS version: 14.6.1\n"
        XCTAssertEqual(draft.includingVersions(versions).body, "Edited message\n" + versions)
        XCTAssertEqual(draft.body, "Edited message")
        XCTAssertEqual(draft.includingVersions(nil), draft)
        XCTAssertEqual(draft.includingVersions(versions), draft.includingVersions(versions))
    }

    func testDraftDoesNotLoadPersonalConfiguration() {
        let draft = SupportDraft(kind: .support)
        for excluded in ["Bearer", "password", "refresh_token", "/Users/", "device_id", "server:"] {
            XCTAssertFalse(draft.clipboardText.contains(excluded))
        }
    }
}
