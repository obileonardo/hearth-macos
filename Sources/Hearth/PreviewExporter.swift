import AppKit
import SwiftUI
import ImageIO
import SceneKit

/// Review the actual app components with sample data, without opening a home connection.
@MainActor
enum PreviewExporter {
    static func export(to folder: String) throws {
        let out = URL(fileURLWithPath: folder, isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let fixtures = out.appendingPathComponent("fixtures", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
        // Only read empty preview stores. The app's saved homes, gadgets and faces stay private.
        var arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        arguments["homesFile"] = fixtures.appendingPathComponent("homes.json").path
        arguments["gadgetsFile"] = fixtures.appendingPathComponent("gadgets.json").path
        arguments["facesFolder"] = fixtures.appendingPathComponent("faces", isDirectory: true).path
        arguments["activityFolder"] = fixtures.path
        arguments["mapsFolder"] = fixtures.appendingPathComponent("maps").path
        arguments["map.current"] = ""
        arguments["mapFile"] = ""
        arguments["map.walls"] = "seeThrough"
        arguments["map.floor"] = "all"
        arguments["map.plan"] = false
        arguments["demo"] = ""
        arguments["openHome"] = ""
        arguments["openAccount"] = false
        arguments["openHelp"] = false
        arguments["openFaces"] = false
        arguments["ha.url"] = "http://homeassistant.local:8123"
        arguments["ha.username"] = "demo"
        arguments["appearance"] = "system"
        arguments["desktopWidgets.climateEntity"] = "climate.preview_living_room"
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        let engine = DemoEngine(.vehicles)
        let energy = DemoEngine(.energy)
        let climate = Entity(["entity_id": "climate.preview_living_room", "state": "cool",
                              "attributes": ["friendly_name": "Living room", "temperature": 24,
                                             "current_temperature": 25.5, "hvac_modes": ["off", "cool", "heat"]]])!
        energy.store.playDemo(update: [climate])
        let log = ActivityLog()
        let hub = DevicesHub()
        hub.showGrid()
        guard let car = engine.store.homeDevice("demo-car") else { throw ProviderError("Missing sample car") }
        let speakers = HomeStore()
        let ids = ["media_player.living_homepod", "media_player.kitchen_homepod", "media_player.office_echo", "media_player.bedroom_homepod"]
        let names = ["Living Room HomePod", "Kitchen HomePod", "Echo Dot Upstairs Bedroom", "Guest Bedroom Speaker"]
        let rooms = [Area(id: "living", name: "Living Room"), Area(id: "kitchen", name: "Kitchen"),
                     Area(id: "master", name: "Upstairs Bedroom"), Area(id: "bedroom", name: "Guest Bedroom")]
        let states = ["playing", "playing", "paused", "unavailable"]
        let players = ids.enumerated().map { i, id in
            Entity(id: id, state: states[i], attributes: ["friendly_name": names[i], "media_title": "A quiet morning",
                "media_artist": "Hearth Sessions", "volume_level": 0.45,
                "group_members": i < 2 ? Array(ids.prefix(2)) : []])
        }
        speakers.playDemo(devices: ids.enumerated().map { i, id in
            DeviceInfo(id: id, name: names[i], manufacturer: i == 2 ? "Amazon" : "Apple",
                       model: i == 2 ? "Echo Dot" : "HomePod mini", areaID: rooms[i].id)
        }, entities: players, deviceOf: Dictionary(uniqueKeysWithValues: ids.map { ($0, $0) }), areas: rooms, simulator: { _ in nil })
        for scheme in [ColorScheme.dark, .light] {
            let suffix = scheme == .dark ? "dark" : "light"
            try save(PreviewProductShowcase(), name: "product-showcase-\(suffix)", width: 1020,
                     scheme: scheme, store: energy.store, log: log, out: out)
            try save(PreviewScreenshotPanel(selected: .devices) { DevicesPage(hub: hub, shown: true, visible: false) },
                     name: "guide-devices-\(suffix)", width: 448, scheme: scheme, store: engine.store, log: log, out: out)
            try save(PreviewScreenshotPanel(selected: .devices) { MediaPage(players: players, shown: true, previewLayout: "grid") },
                     name: "guide-speakers-\(suffix)", width: 448, scheme: scheme, store: speakers, log: log, out: out)
            try save(PreviewScreenshotPanel(selected: .climate(climate.id)) { ClimatePage(entityID: climate.id, shown: true) },
                     name: "guide-climate-\(suffix)", width: 448, scheme: scheme, store: energy.store, log: log, out: out)
            try save(PreviewScreenshotPanel(selected: nil, settings: true) { SettingsView(previewSignedIn: false) {} },
                     name: "guide-connect-\(suffix)", width: 448, scheme: scheme, store: energy.store, log: log, out: out)
            try save(PreviewScreenshotPanel(selected: nil, settings: true) { HelpAndSupport {} },
                     name: "guide-help-\(suffix)", width: 448, scheme: scheme, store: energy.store, log: log, out: out)
            try save(PreviewScreenshotPanel(selected: nil, settings: true) { HelpAndSupport(initialRequest: .bug) {} },
                     name: "guide-bug-report-\(suffix)", width: 448, scheme: scheme, store: energy.store, log: log, out: out)
            try save(CarCard(device: car) { _ in }, name: "vehicle-\(suffix)", width: 368,
                     scheme: scheme, store: engine.store, log: log, out: out)
            try save(DevicesPage(hub: hub, shown: true, visible: false), name: "devices-\(suffix)", width: 368,
                     scheme: scheme, store: engine.store, log: log, out: out)
            for layout in ["grid", "list"] {
                try save(MediaPage(players: players, shown: true, previewLayout: layout), name: "speakers-\(layout)-\(suffix)", width: 368,
                         scheme: scheme, store: speakers, log: log, out: out)
            }
            try save(ACUnitView(power: 1, mode: "cool", intensity: 0.8, swing: true, width: 240, display: "24°", previewTime: 1.4),
                     name: "airflow-\(suffix)", width: 340, scheme: scheme, store: engine.store, log: log, out: out)
            try save(PillAndWidgetSettings(), name: "settings-\(suffix)", width: 368,
                     scheme: scheme, store: engine.store, log: log, out: out, native: true)
            try save(LivePill.preview(), name: "pill-\(suffix)", width: LivePill.size.width,
                     scheme: scheme, store: engine.store, log: log, out: out, native: true)
            for kind in DesktopWidgetKind.allCases {
                try save(DesktopWidgetCard(kind: kind, previewOpaque: true).frame(width: kind.size.width, height: kind.size.height), name: "widget-\(kind.rawValue)-\(suffix)", width: kind.size.width,
                         scheme: scheme, store: energy.store, log: log, out: out)
            }
            try save(DesktopWidgetCard(kind: .overview, previewOpaque: true).frame(width: 360, height: 320), name: "widget-overview-narrow-\(suffix)", width: 360,
                     scheme: scheme, store: energy.store, log: log, out: out)
        }
        CarSheet.export(to: folder)
        try airflowAnimation(to: out)
        try mapScene(to: out, store: speakers)
        try deviceModels(to: out)
    }

    private static func deviceModels(to out: URL) throws {
        let controller = MapSceneController(full: true)
        let floor = SCNBox(width: 9.4, height: 0.08, length: 5.6, chamferRadius: 0.04)
        floor.materials = [MapSceneController.clay(0.24)]
        let ground = SCNNode(geometry: floor); ground.position = SCNVector3(5, -0.05, 3.5)
        controller.scene.rootNode.addChildNode(ground)
        let kinds: [DeviceKind] = [.fridge, .tv, .airConditioner, .smartSpeaker, .meshSpeaker, .indoorCamera,
                                   .outdoorCamera, .doorbell, .securityHubPro, .computer, .battery, .router]
        for (index, kind) in kinds.enumerated() {
            guard let model = MapDeviceModel.make(kind) else { continue }
            model.node.position = SCNVector3(1.5 + Float(index % 6) * 1.4, 0, index < 6 ? 2.1 : 4.4)
            controller.scene.rootNode.addChildNode(model.node)
        }
        let view = SCNView(frame: NSRect(x: 0, y: 0, width: 1200, height: 760))
        view.scene = controller.scene
        view.pointOfView = controller.scene.rootNode.childNode(withName: "camera", recursively: false)
        view.antialiasingMode = .multisampling4X
        controller.orbit(yaw: -0.28, pitch: 0)
        for angle in 0..<2 {
            if angle == 1 { controller.orbit(yaw: 0.92, pitch: 0) }
            let image = view.snapshot()
            if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try png.write(to: out.appendingPathComponent("device-models-\(angle).png"), options: .atomic)
            }
        }
        for node in controller.scene.rootNode.childNodes where node.name == "device-model" { node.removeFromParentNode() }
        if let camera = MapDeviceModel.make(.outdoorCamera), let pointOfView = view.pointOfView {
            camera.node.position = SCNVector3(5, 0, 3.5)
            camera.node.scale = SCNVector3(5, 5, 5)
            controller.scene.rootNode.addChildNode(camera.node)
            for (index, location) in [SCNVector3(2.5, 3.5, 8), SCNVector3(7.5, 3.5, 8)].enumerated() {
                pointOfView.position = location
                pointOfView.look(at: SCNVector3(5, 1, 3.5))
                let image = view.snapshot()
                if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try png.write(to: out.appendingPathComponent("outdoor-camera-close-\(index).png"), options: .atomic)
                }
            }
        }
    }

    private static func airflowAnimation(to out: URL) throws {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let url = out.appendingPathComponent("airflow.gif")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "com.compuserve.gif" as CFString, 48, nil) else { return }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in 0..<48 {
            let content = ACUnitView(power: 1, mode: "cool", intensity: 0.8, swing: true, width: 240, display: "24°", previewTime: Double(frame) / 12)
                .padding(20).background(Theme.base).environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            if let image = renderer.cgImage {
                CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / 12]] as CFDictionary)
            }
        }
        guard CGImageDestinationFinalize(destination) else { throw ProviderError("Couldn't render airflow animation") }
    }

    private static func mapScene(to out: URL, store: HomeStore) throws {
        let controller = MapSceneController(full: true)
        controller.attach(store)
        let view = SCNView(frame: NSRect(x: 0, y: 0, width: 899, height: 760))
        view.scene = controller.scene
        view.pointOfView = controller.scene.rootNode.childNode(withName: "camera", recursively: false)
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = NSColor.black
        controller.view = view
        controller.setAppearance(dark: true)
        controller.fit(animated: false)
        controller.orbit(yaw: -0.52, pitch: 0)
        controller.finishContactShadowsForPreview()
        let image = view.snapshot()
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try png.write(to: out.appendingPathComponent("map-scale-dark.png"), options: .atomic)
        try save(MapWindow(previewImage: image).frame(height: 760), name: "map-layout-dark", width: 1180, scheme: .dark, store: store, log: ActivityLog(), out: out, native: true)
    }

    private static func save<V: View>(_ view: V, name: String, width: CGFloat, scheme: ColorScheme,
                                     store: HomeStore, log: ActivityLog, out: URL, native: Bool = false) throws {
        NSApp.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let content = view
            .environmentObject(store).environmentObject(log)
            .frame(width: width).padding(16).background(Theme.base)
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let png: Data?
        if native {
            // Native switches and glass need an AppKit host. This window is never
            // shown, and caching its own view needs no screen-recording permission.
            let host = NSHostingView(rootView: content)
            let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSApp.appearance
            window.contentView = host
            window.setContentSize(host.fittingSize)
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)
            if let rep { host.cacheDisplay(in: host.bounds, to: rep) }
            png = rep?.representation(using: .png, properties: [:])
            window.close()
        } else {
            png = renderer.cgImage.flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }
        }
        guard let png else {
            throw ProviderError("Couldn't render \(name)")
        }
        try png.write(to: out.appendingPathComponent("\(name).png"), options: .atomic)
    }
}

/// Consistent viewport and native dock for documentation. Only sample views are
/// hosted; this bypasses PanelView's saved-route initialization and never signs in.
private struct PreviewScreenshotPanel<Content: View>: View {
    let selected: Page?
    var settings = false
    @ViewBuilder let content: () -> Content
    private let pages: [Page] = [.climate("climate.preview_living_room"), .security, .rooms, .devices, .map, .activity]

    var body: some View {
        VStack(spacing: 0) {
            content().fixedSize(horizontal: false, vertical: true)
                .frame(width: 404, height: 532, alignment: .top).padding(22).clipped()
            Dock(pages: pages, selected: selected, label: { page in
                switch page {
                case .climate: ("snowflake", "Workspace")
                case .security: ("video", "Security")
                case .rooms: ("square.grid.2x2", "Rooms")
                case .devices: ("plug", "Devices")
                case .map: ("cube.transparent", "3D map")
                case .activity: ("bell", "Activity")
                case .media: ("speaker", "Speakers")
                }
            }, settingsOn: settings, status: (Theme.ok, "Demo"), onSelect: { _ in })
                .padding(.horizontal, 18).frame(height: 72)
        }
        .frame(width: 448, height: 648)
        .environment(\.hearthDocumentationPreview, true)
        .foregroundStyle(Theme.ink).background(Theme.base)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
    }
}

/// Drawn with the app's own illustration and card components, without a
/// generated raster scene or invented device artwork.
private struct PreviewProductShowcase: View {
    var body: some View {
        HStack(spacing: 18) {
            feature("Climate", detail: "Comfort, one degree at a time") {
                ACUnitView(power: 1, mode: "cool", intensity: 0.8, swing: false, width: 196, display: "24°", previewTime: 1.4).scaleEffect(0.78)
            }
            feature("Security", detail: "A clearer view of your home") {
                HStack(spacing: 12) {
                    DeviceArtView(kind: .outdoorCamera, accent: Theme.brand, size: 116)
                    DeviceArtView(kind: .doorbell, accent: Theme.brand, size: 90)
                }
            }
            feature("Speakers", detail: "The right sound, in every room") {
                HStack(spacing: 16) {
                    DeviceArtView(kind: .smartSpeaker, accent: Theme.brand, size: 104)
                    DeviceArtView(kind: .meshSpeaker, accent: Theme.brand, size: 104)
                }
            }
        }
        .padding(12)
    }

    private func feature<Illustration: View>(_ title: String, detail: String, @ViewBuilder illustration: () -> Illustration) -> some View {
        Bezel(radius: 22, inset: 3, lit: true, tint: Theme.brand) {
            VStack(spacing: 14) {
                illustration().frame(height: 132)
                VStack(spacing: 5) {
                    Text(title).font(.system(size: 20, weight: .semibold))
                    Text(detail).font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
            }
            .padding(22).frame(maxWidth: .infinity)
        }
    }
}

/// Explicitly opt-in static native-input illustrations for offline documentation.
/// Normal application views keep real editable fields and system switches.
private struct HearthDocumentationPreviewKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var hearthDocumentationPreview: Bool {
        get { self[HearthDocumentationPreviewKey.self] }
        set { self[HearthDocumentationPreviewKey.self] = newValue }
    }
}
