import Foundation
import XCTest
@testable import Hearth

final class DeviceCommandTests: XCTestCase {
    private func player(_ state: String = "idle", features: Double? = nil) -> Entity {
        var attrs: JSON = [:]
        if let features { attrs["supported_features"] = features }
        return Entity(id: "media_player.fixture_kitchen", state: state, attributes: attrs)
    }

    func testIdlePlaybackNeedsContentInsteadOfEmptyResume() {
        XCTAssertNil(SpeakerAction.primaryService(player()))
        XCTAssertNil(SpeakerAction.primaryService(player("off")))
        XCTAssertNil(SpeakerAction.primaryService(player("buffering")))
        XCTAssertEqual(SpeakerAction.primaryService(player("paused", features: 16384)), "media_play")
        XCTAssertEqual(SpeakerAction.primaryService(player("playing", features: 1)), "media_pause")
    }

    func testUnsupportedTransportHasNoInventedPause() {
        XCTAssertNil(SpeakerAction.primaryService(player("playing", features: 512)))
        XCTAssertEqual(SpeakerAction.primaryService(player("playing", features: 4096)), "media_stop")
        XCTAssertNil(SpeakerAction.primaryService(player("unavailable", features: 1)))
        XCTAssertNil(SpeakerAction.primaryService(player("paused", features: 0)))
    }

    func testMalformedCapabilitiesFailClosedAndMissingKeepsLegacyControls() {
        XCTAssertTrue(SpeakerAction.supports(player(), feature: 512))
        for malformed in [Double.nan, Double.infinity, -1, 512.5, Double(Int.max)] {
            XCTAssertFalse(SpeakerAction.supports(player(features: malformed), feature: 512))
        }
        XCTAssertFalse(SpeakerAction.supports(player(features: 0), feature: 512))
    }

    func testMediaTargetsOnlySelectedSpeaker() throws {
        let action = try XCTUnwrap(DeviceCommand.media(player(features: 512), content: "  fixture station  ", type: " music "))
        XCTAssertEqual(action.service, "play_media")
        XCTAssertEqual((action.body["target"] as? JSON)?["entity_id"] as? String, "media_player.fixture_kitchen")
        XCTAssertEqual(action.data["media_content_id"] as? String, "fixture station")
        XCTAssertEqual(action.data["media_content_type"] as? String, "music")
        XCTAssertNil(DeviceCommand.media(player(features: 0), content: "song", type: "music"))
        XCTAssertNil(DeviceCommand.media(player(), content: " \n ", type: "music"))
        XCTAssertNil(DeviceCommand.media(player(), content: "song", type: ""))
    }

    func testAlexaUsesVerifiedIntegrationAndSelectedDeviceID() throws {
        var device = DeviceInfo(id: "fixture-device", name: "Echo fixture", manufacturer: "Amazon", model: "Echo Dot", areaID: nil)
        XCTAssertNil(DeviceCommand.alexaMusic(device, available: true, query: ""))
        device.integrations = ["alexa_media"]
        XCTAssertNil(DeviceCommand.alexaMusic(device, available: true, query: ""))
        device.integrations = ["alexa_devices"]
        XCTAssertNil(DeviceCommand.alexaMusic(device, available: false, query: ""))
        let action = try XCTUnwrap(DeviceCommand.alexaMusic(device, available: true, query: ""))
        XCTAssertNil(action.body["target"])
        XCTAssertEqual(action.data["device_id"] as? String, "fixture-device")
        XCTAssertEqual(action.data["text_command"] as? String, "play music")
        XCTAssertEqual(DeviceCommand.alexaMusic(device, available: true, query: " jazz ")?.data["text_command"] as? String, "play jazz")
    }

    func testIntegrationIdentifiersAreNotDeviceNames() {
        XCTAssertEqual(DeviceCommand.integrationDomains([["alexa_devices", "fixture"], ["other", "fixture-2"]]), ["alexa_devices", "other"])
        XCTAssertTrue(DeviceCommand.integrationDomains("Echo Dot").isEmpty)
        XCTAssertTrue(DeviceCommand.integrationDomains(nil).isEmpty)
    }

    func testPowerKeepsEntityDomainAndTarget() throws {
        for domain in ["switch", "input_boolean", "light", "fan", "siren", "camera"] {
            let e = Entity(id: "\(domain).fixture", state: "on", attributes: [:])
            let action = try XCTUnwrap(DeviceCommand.power(e, on: false))
            XCTAssertEqual(action.domain, domain)
            XCTAssertEqual(action.service, "turn_off")
            XCTAssertEqual(action.entityID, e.id)
        }
        XCTAssertNil(DeviceCommand.power(Entity(id: "sensor.fixture", state: "on", attributes: [:]), on: false))
        XCTAssertNil(DeviceCommand.power(Entity(id: "switch.fixture", state: "unavailable", attributes: [:]), on: true))
    }

    func testFirstAnnouncementUnknownStateIsValidAndWhitespaceIsRejected() throws {
        let e = Entity(id: "notify.fixture_announce", state: "unknown", attributes: [:])
        let action = try XCTUnwrap(DeviceCommand.announcement(e, message: " Dinner is ready "))
        XCTAssertEqual(action.service, "send_message")
        XCTAssertEqual(action.entityID, e.id)
        XCTAssertEqual(action.data["message"] as? String, "Dinner is ready")
        XCTAssertNil(DeviceCommand.announcement(e, message: "  \n"))
        XCTAssertNil(DeviceCommand.announcement(Entity(id: e.id, state: "unavailable", attributes: [:]), message: "hello"))
        XCTAssertNil(DeviceCommand.announcement(player(), message: "hello"))
    }

    @MainActor func testDemoServiceAcknowledgementDoesNotFakePlaying() async throws {
        let store = HomeStore()
        let e = player()
        var received: JSON?
        store.playDemo(devices: [], entities: [e], deviceOf: [:]) { body in received = body; return nil }
        let acknowledged = expectation(description: "Accepted fixture action")
        store.call("media_player", "play_media", e.id, ["media_content_id": "fixture", "media_content_type": "music"]) { result in
            if case .failure(let error) = result { XCTFail(error.localizedDescription) }
            acknowledged.fulfill()
        }
        await fulfillment(of: [acknowledged], timeout: 2)
        XCTAssertEqual((received?["target"] as? JSON)?["entity_id"] as? String, e.id)
        XCTAssertEqual(store.entities[e.id]?.state, "idle")
        XCTAssertEqual(store.inFlight, 0)
    }
    @MainActor func testRejectedLegacyActionIsVisibleAndDoesNotChangeState() async {
        let store = HomeStore()
        let e = Entity(id: "switch.fixture_camera_enabled", state: "off", attributes: [:])
        store.playDemo(devices: [], entities: [e], deviceOf: [:]) { _ in throw ProviderError("Fixture action rejected") }
        store.call("switch", "turn_on", e.id)
        for _ in 0..<20 where store.inFlight != 0 { try? await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(store.actionError, "Fixture action rejected")
        XCTAssertEqual(store.entities[e.id]?.state, "off")
        XCTAssertEqual(store.inFlight, 0)
    }

    @MainActor func testRejectedCallbackKeepsErrorLocalWithoutDuplicateGlobalAlert() async {
        let store = HomeStore()
        store.playDemo(devices: [], entities: [], deviceOf: [:]) { _ in throw ProviderError("Fixture callback rejected") }
        let rejected = expectation(description: "Rejected fixture action")
        store.call("notify", "send_message", "notify.fixture", ["message": "fixture message"]) { result in
            switch result {
            case .success: XCTFail("Rejected fixture cannot succeed")
            case .failure(let error): XCTAssertEqual(error.localizedDescription, "Fixture callback rejected")
            }
            rejected.fulfill()
        }
        await fulfillment(of: [rejected], timeout: 2)
        XCTAssertNil(store.actionError)
        XCTAssertEqual(store.inFlight, 0)
    }

}
