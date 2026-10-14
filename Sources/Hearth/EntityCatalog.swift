import Foundation

/// How a device's settings are grouped on its page, in display order.
enum ControlGroup: String, CaseIterable {
    case live = "Live"
    case printing = "Printing"
    case charging = "Charging"
    case detection = "Detection"
    case alerts = "Alerts"
    case camera = "Camera"
    case sound = "Sound"
    case video = "Video"
    case schedule = "Schedule"
    case energy = "Energy"
    case status = "Status"
    case settings = "Settings"
    case actions = "Actions"
}

/// Plain-language names, explanations and groups for the settings Home Assistant exposes,
/// so a camera's thirty switches read as a few sections a person can understand.
struct EntityCopy {
    var label: String
    var detail: String?
    var group: ControlGroup
    var symbol: String
    /// Settings that only clutter the page (debug flags, raw ids).
    var hidden = false
}

enum EntityCatalog {
    /// The part of an entity id after the device's name: `switch.office_status_led` on the
    /// device "Office" gives "status_led".
    static func key(_ entity: Entity, deviceName: String) -> String {
        let object = String(entity.id.drop { $0 != "." }.dropFirst())
        let slug = slugify(deviceName)
        if !slug.isEmpty, object.hasPrefix(slug + "_") { return String(object.dropFirst(slug.count + 1)) }
        return object
    }

    static func slugify(_ s: String) -> String {
        let lowered = s.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "_" }
        return String(lowered).split(separator: "_").joined(separator: "_")
    }

    private static let known: [String: (String, String?, ControlGroup, String)] = [
        // Cameras
        "camera_enabled": ("Camera", "Turns the camera fully off when off", .live, "video"),
        "motion_detection": ("Motion detection", "Watches for movement in view", .detection, "figure.walk.motion"),
        "motion_detection_type_human": ("People", "Flags movement from people", .detection, "person"),
        "motion_detection_type_pet": ("Pets", "Flags movement from pets", .detection, "pawprint"),
        "motion_detection_type_all_other_motions": ("Everything else", "Cars, branches and any other motion", .detection, "wind"),
        "motion_detection_sensitivity": ("Sensitivity", "How small a movement counts", .detection, "dial.medium"),
        "motion_tracking": ("Follow movement", "Turns the camera to follow what it sees", .detection, "scope"),
        "notification_person_detected": ("People", "Alert when a person is seen", .alerts, "bell.badge"),
        "notification_pet_detected": ("Pets", "Alert when a pet is seen", .alerts, "bell"),
        "notification_all_other_motion": ("Other motion", "Alert on any other movement", .alerts, "bell"),
        "notification_crying_detected": ("Crying", "Alert when crying is heard", .alerts, "bell"),
        "notification_sound_detected": ("Sound", "Alert on loud sounds", .alerts, "bell"),
        "auto_nightvision": ("Night vision", "Switches to infrared in the dark", .camera, "moon.stars"),
        "status_led": ("Status light", "The small light on the front", .camera, "circle.dotted"),
        "rotation_speed": ("Turn speed", "How fast it pans and tilts", .camera, "arrow.triangle.2.circlepath"),
        "microphone": ("Microphone", "Lets the camera hear", .sound, "mic"),
        "speaker": ("Speaker", "Lets you talk through it", .sound, "speaker.wave.2"),
        "speaker_volume": ("Speaker volume", nil, .sound, "speaker.wave.3"),
        "audio_recording": ("Record sound", "Saves audio with clips", .sound, "waveform"),
        "rtsp_stream": ("Local stream", "Streams on your network for live view", .video, "dot.radiowaves.left.and.right"),
        "video_recording_quality": ("Recording quality", nil, .video, "film"),
        "video_streaming_quality": ("Live quality", nil, .video, "play.rectangle"),
        "motion_detected": ("Motion", nil, .status, "figure.walk"),
        "person_detected": ("Person", nil, .status, "person"),
        "pet_detected": ("Pet", nil, .status, "pawprint"),
        "sound_detected": ("Sound", nil, .status, "ear"),
        "crying_detected": ("Crying", nil, .status, "ear"),
        // Doorbells
        "ding": ("Last ring", nil, .status, "bell"),
        "motion": ("Movement", "Someone moving nearby", .status, "figure.walk"),
        "volume": ("Chime volume", nil, .sound, "speaker.wave.2"),
        "battery": ("Battery", nil, .status, "battery.75percent"),
        "last_activity": ("Last activity", nil, .status, "clock"),
        // Smart speakers
        "announce": ("Announce", "Say something out loud", .live, "megaphone"),
        "do_not_disturb": ("Do not disturb", "Silences notifications and calls", .sound, "moon"),
        "temperature": ("Temperature", nil, .status, "thermometer.medium"),
        "illuminance": ("Light level", nil, .status, "sun.max"),
        "next_alarm": ("Next alarm", nil, .schedule, "alarm"),
        "next_timer": ("Next timer", nil, .schedule, "timer"),
        "next_reminder": ("Next reminder", nil, .schedule, "checklist"),
        "restart": ("Restart", nil, .actions, "arrow.clockwise"),
        // Security hubs
        "guard_mode": ("Guard mode", "What the system does when it sees motion", .live, "shield.lefthalf.filled"),
        "current_mode": ("Current mode", nil, .status, "shield"),
        "alarm_volume": ("Siren volume", nil, .sound, "light.beacon.max"),
        "prompt_volume": ("Voice prompts", nil, .sound, "text.bubble"),
        // Air conditioners
        "sleep_timer": ("Sleep timer", "Turns off after a while", .schedule, "moon.zzz"),
        "schedule_turn_off": ("Turn off in", nil, .schedule, "power"),
        "schedule_turn_on": ("Turn on in", nil, .schedule, "power"),
        "lighting": ("Display light", "The lights on the unit", .settings, "lightbulb"),
        "filter_remaining": ("Filter life", nil, .status, "aqi.low"),
        "energy_today": ("Energy today", nil, .energy, "bolt"),
        "energy_yesterday": ("Yesterday", nil, .energy, "bolt"),
        "energy_this_month": ("This month", nil, .energy, "bolt"),
        "energy_last_month": ("Last month", nil, .energy, "bolt"),
        // 3D printers (Bambu Lab)
        "print_progress": ("Progress", nil, .printing, "percent"),
        "print_status": ("Print status", nil, .printing, "printer"),
        "current_stage": ("Stage", "What the printer is doing right now", .printing, "list.bullet.indent"),
        "remaining_time": ("Time left", nil, .printing, "hourglass"),
        "end_time": ("Done at", nil, .printing, "clock"),
        "start_time": ("Started", nil, .printing, "clock"),
        "task_name": ("Printing", nil, .printing, "cube"),
        "current_layer": ("Layer", nil, .printing, "square.3.layers.3d"),
        "total_layer_count": ("Layers in all", nil, .printing, "square.3.layers.3d"),
        "nozzle_temperature": ("Nozzle", "How hot the tip that lays the plastic is", .status, "flame"),
        "nozzle_target_temperature": ("Nozzle target", nil, .status, "flame"),
        "bed_temperature": ("Bed", "How hot the plate the print sits on is", .status, "square.3.layers.3d.down.right"),
        "bed_target_temperature": ("Bed target", nil, .status, "square.3.layers.3d.down.right"),
        "chamber_temperature": ("Inside", nil, .status, "thermometer.medium"),
        "chamber_light": ("Chamber light", "The light inside the printer", .settings, "lightbulb"),
        // Electric cars and chargers
        "battery_level": ("Battery", nil, .charging, "battery.75percent"),
        "state_of_charge": ("Battery", nil, .charging, "battery.75percent"),
        "battery_range": ("Range", "How far it can go on this charge", .charging, "road.lanes"),
        "range": ("Range", "How far it can go on this charge", .charging, "road.lanes"),
        "est_battery_range": ("Estimated range", nil, .charging, "road.lanes"),
        "charging": ("Charging", nil, .charging, "bolt.fill"),
        "charging_state": ("Charging", nil, .charging, "bolt.fill"),
        "charge_state": ("Charging", nil, .charging, "bolt.fill"),
        "charge": ("Charge", "Starts or stops charging while plugged in", .charging, "bolt.fill"),
        "charger_power": ("Charging power", nil, .charging, "bolt"),
        "charging_power": ("Charging power", nil, .charging, "bolt"),
        "charge_rate": ("Charge rate", nil, .charging, "speedometer"),
        "time_to_full_charge": ("Full at", nil, .charging, "clock"),
        "time_to_full": ("Time to full", nil, .charging, "hourglass"),
        "charge_limit": ("Charge limit", "Stops charging at this level, to look after the battery", .charging, "battery.100percent"),
        "charge_limit_soc": ("Charge limit", "Stops charging at this level, to look after the battery", .charging, "battery.100percent"),
        "plugged_in": ("Plugged in", nil, .charging, "powerplug"),
        "charge_cable": ("Charge cable", nil, .charging, "powerplug"),
        "charge_energy_added": ("Added this charge", nil, .charging, "bolt.batteryblock"),
        "added_energy": ("Added this charge", nil, .charging, "bolt.batteryblock"),
        "charge_port_door": ("Charge port", nil, .settings, "ev.plug.dc.ccs1"),
        "charge_cable_lock": ("Cable lock", "Keeps the cable locked in while charging", .settings, "lock"),
        "location": ("Location", nil, .status, "location"),
        "odometer": ("Odometer", nil, .status, "gauge.with.dots.needle.33percent"),
        "climate": ("Climate", "Heats or cools the cabin before you go", .live, "fan"),
        "sentry_mode": ("Sentry mode", "Watches the car with its cameras while parked", .settings, "eye"),
        // Robot vacuums and mowers
        "cleaning_time": ("Cleaning time", nil, .status, "clock"),
        "cleaning_area": ("Area cleaned", nil, .status, "square.dashed"),
        "filter_left": ("Filter life", nil, .status, "aqi.low"),
        "main_brush_left": ("Main brush life", nil, .status, "paintbrush"),
        "side_brush_left": ("Side brush life", nil, .status, "paintbrush"),
        "fan_speed": ("Suction", nil, .settings, "fan"),
        "mop_mode": ("Mop", nil, .settings, "drop"),
        "blade_usage_time": ("Blade use", nil, .status, "scissors"),
    ]

    private static let hiddenFragments = ["debug", "snooze", "person_name", "connectivity", "voice_event", "event_image", "notification"]

    static func copy(for entity: Entity, deviceName: String) -> EntityCopy {
        let k = key(entity, deviceName: deviceName)
        // Climate "power" duplicates the AC page's power key; "speak" duplicates "announce".
        let hide = hiddenFragments.contains { k == $0 || (k.contains($0) && !k.hasPrefix("notification_")) }
            || (entity.domain == "switch" && k == "power") || (entity.domain == "notify" && k == "speak")
            || entity.domain == "event" && k.hasSuffix("notification")
        if let (label, detail, group, symbol) = known[k] {
            return EntityCopy(label: label, detail: detail, group: group, symbol: symbol, hidden: hide)
        }
        // Unknown: the friendly name without the device's name in front.
        var label = entity.name
        if label.lowercased().hasPrefix(deviceName.lowercased() + " ") { label = String(label.dropFirst(deviceName.count + 1)) }
        if label == entity.name, entity.attributes["friendly_name"] == nil { label = k.pretty }
        let group: ControlGroup = switch entity.domain {
        case "sensor", "binary_sensor", "event": .status
        case "button": .actions
        case "media_player", "camera", "climate", "alarm_control_panel", "notify": .live
        default: .settings
        }
        let symbol = switch entity.domain {
        case "light": "lightbulb"
        case "fan": "fan"
        case "lock": "lock"
        case "cover": "blinds.horizontal.closed"
        case "media_player": "hifispeaker"
        case "switch", "input_boolean": "switch.2"
        case "number": "slider.horizontal.3"
        case "select": "list.bullet"
        case "button": "hand.tap"
        default: "circle.grid.2x1"
        }
        return EntityCopy(label: label.isEmpty ? k.pretty : label, detail: nil, group: group, symbol: symbol, hidden: hide)
    }
}
