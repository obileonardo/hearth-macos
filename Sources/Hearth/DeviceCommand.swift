import Foundation

/// A single explicit HA action. No broad target is ever inferred or substituted.
struct DeviceCommand {
    let domain: String
    let service: String
    var entityID: String?
    var data: JSON = [:]

    var body: JSON {
        var result: JSON = ["type": "call_service", "domain": domain, "service": service, "service_data": data]
        if let entityID { result["target"] = ["entity_id": entityID] }
        return result
    }

    static func integrationDomains(_ identifiers: Any?) -> Set<String> {
        Set((identifiers as? [[String]] ?? []).compactMap { $0.first })
    }

    static func power(_ entity: Entity, on: Bool) -> DeviceCommand? {
        guard ["switch", "input_boolean", "light", "fan", "siren", "camera"].contains(entity.domain),
              !entity.isUnavailable else { return nil }
        return DeviceCommand(domain: entity.domain, service: on ? "turn_on" : "turn_off", entityID: entity.id)
    }

    static func announcement(_ entity: Entity, message: String) -> DeviceCommand? {
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard entity.domain == "notify", entity.state != "unavailable", !message.isEmpty else { return nil }
        return DeviceCommand(domain: "notify", service: "send_message", entityID: entity.id, data: ["message": message])
    }

    /// Only an actual Alexa Devices registry identifier enables the Alexa service.
    static func alexaMusic(_ device: DeviceInfo, available: Bool, query: String) -> DeviceCommand? {
        guard available, device.integrations.contains("alexa_devices") else { return nil }
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return DeviceCommand(domain: "alexa_devices", service: "send_text_command",
                             data: ["device_id": device.id, "text_command": query.isEmpty ? "play music" : "play \(query)"])
    }

    static func media(_ entity: Entity, content: String, type: String) -> DeviceCommand? {
        let content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let type = type.trimmingCharacters(in: .whitespacesAndNewlines)
        guard entity.domain == "media_player", !entity.isUnavailable, !content.isEmpty, !type.isEmpty,
              SpeakerAction.supports(entity, feature: 512) else { return nil }
        return DeviceCommand(domain: "media_player", service: "play_media", entityID: entity.id,
                             data: ["media_content_id": content, "media_content_type": type])
    }
}

enum SpeakerAction {
    /// Missing metadata keeps older integrations usable; explicit zero means unsupported.
    static func supports(_ entity: Entity, feature: Int) -> Bool {
        guard let value = entity.num("supported_features"), value >= 0, let features = Int(exactly: value) else {
            return entity.attributes["supported_features"] == nil
        }
        return features & feature != 0
    }

    static func primaryService(_ entity: Entity) -> String? {
        guard !entity.isUnavailable else { return nil }
        if entity.state == "playing" {
            if supports(entity, feature: 1) { return "media_pause" }
            if supports(entity, feature: 4096) { return "media_stop" }
        } else if entity.state == "paused", supports(entity, feature: 16384) {
            return "media_play"
        }
        // media_play only resumes a queue; an idle player needs an explicit media request.
        return nil
    }
}
