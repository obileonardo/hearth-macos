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
        arguments[NavigationGlassPreference.key] = NavigationGlassPreference.defaultValue
        arguments["hiddenSections"] = ""
        arguments[RoomsLayoutPreference.key] = RoomsLayoutPreference.overview.rawValue
        arguments["desktopWidgets.climateEntity"] = "climate.preview_living_room"
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        let engine = DemoEngine(.vehicles)
        let energy = DemoEngine(.energy)
        let climate = Entity(["entity_id": "climate.preview_living_room", "state": "cool",
                              "attributes": ["friendly_name": "Living room", "temperature": 24,
                                             "current_temperature": 25.5,
                                             "hvac_modes": ["off", "cool", "auto", "dry", "fan_only"],
                                             "fan_modes": ["auto", "low", "medium", "high"], "fan_mode": "high",
                                             "swing_modes": ["off", "on"], "swing_mode": "on", "supported_features": 128]])!
        let climateCompanions = [
            Entity(id: "number.preview_living_room_sleep_timer", state: "0", attributes: ["friendly_name": "Sleep timer", "min": 0, "max": 8]),
            Entity(id: "switch.preview_living_room_lighting", state: "on", attributes: ["friendly_name": "Display light"])
        ]
        let climateStore = HomeStore()
        let climateEntities = [climate] + climateCompanions
        climateStore.playDemo(devices: [DeviceInfo(id: "preview-climate", name: "Living room air conditioner", manufacturer: "Demo Climate", model: "Wall air conditioner", areaID: "living")],
                              entities: climateEntities,
                              deviceOf: Dictionary(uniqueKeysWithValues: climateEntities.map { ($0.id, "preview-climate") }),
                              areas: [Area(id: "living", name: "Living Room")], simulator: { _ in nil })
        energy.store.playDemo(update: [climate])
        let now = Date()
        let log = ActivityLog(previewItems: [
            ActivityLog.Item(kind: .person, title: "Person at Front door", place: "Entrance", date: now.addingTimeInterval(-60), entityID: "binary_sensor.preview_front_person", read: true),
            ActivityLog.Item(kind: .doorbell, title: "Someone rang the doorbell", place: "Entrance", date: now.addingTimeInterval(-180), entityID: "event.preview_doorbell", read: true),
            ActivityLog.Item(kind: .motion, title: "Movement in the garden", place: "Garden", date: now.addingTimeInterval(-360), entityID: "binary_sensor.preview_garden_motion", read: true),
            ActivityLog.Item(kind: .person, title: "Person at Garden gate", place: "Garden", date: now.addingTimeInterval(-600), entityID: "binary_sensor.preview_gate_person", read: true),
            ActivityLog.Item(kind: .security, title: "Alarm armed for Home", place: "Home", date: now.addingTimeInterval(-900), entityID: "alarm_control_panel.preview_home", read: true),
            ActivityLog.Item(kind: .person, title: "Person at Driveway", place: "Driveway", date: now.addingTimeInterval(-1200), entityID: "binary_sensor.preview_driveway_person", read: true),
            ActivityLog.Item(kind: .person, title: "Person at Front door", place: "Entrance", date: now.addingTimeInterval(-1500), entityID: "binary_sensor.preview_front_person", read: true)
        ])
        let hub = DevicesHub()
        hub.showGrid()
        guard let car = engine.store.homeDevice("demo-car") else { throw ProviderError("Missing sample car") }
        let speakers = HomeStore()
        let ids = ["media_player.living_homepod", "media_player.kitchen_homepod", "media_player.office_echo", "media_player.bedroom_homepod"]
        let names = ["Living Room HomePod", "Kitchen HomePod", "Echo Dot Upstairs Bedroom", "Guest Bedroom Speaker"]
        let rooms = [Area(id: "living", name: "Living Room", floorID: "ground"), Area(id: "kitchen", name: "Kitchen", floorID: "ground"),
                     Area(id: "master", name: "Upstairs Bedroom", floorID: "first"), Area(id: "bedroom", name: "Guest Bedroom", floorID: "first")]
        let states = ["playing", "playing", "paused", "unavailable"]
        let players = ids.enumerated().map { i, id in
            Entity(id: id, state: states[i], attributes: ["friendly_name": names[i], "media_title": "A quiet morning",
                "media_artist": "Hearth Sessions", "volume_level": 0.45,
                "group_members": i < 2 ? Array(ids.prefix(2)) : []])
        }
        speakers.playDemo(devices: ids.enumerated().map { i, id in
            DeviceInfo(id: id, name: names[i], manufacturer: i == 2 ? "Amazon" : "Apple",
                       model: i == 2 ? "Echo Dot" : "HomePod mini", areaID: rooms[i].id)
        }, entities: players, deviceOf: Dictionary(uniqueKeysWithValues: ids.map { ($0, $0) }), areas: rooms, floors: [Floor(id: "ground", name: "Ground floor", level: 0),
                                                  Floor(id: "first", name: "First floor", level: 1)], simulator: { _ in nil })
        for scheme in [ColorScheme.dark, .light] {
            let suffix = scheme == .dark ? "dark" : "light"
            try save(PreviewProductShowcase(), name: "product-showcase-\(suffix)", width: 1020,
                     scheme: scheme, store: energy.store, log: log, out: out)
            try save(PreviewScreenshotPanel(selected: .devices) { DevicesPage(hub: hub, shown: true, visible: false) },
                     name: "guide-devices-\(suffix)", width: 448, scheme: scheme, store: engine.store, log: log, out: out)
            try save(PreviewScreenshotPanel(selected: .devices) { MediaPage(players: players, shown: true, previewLayout: "grid") },
                     name: "guide-speakers-\(suffix)", width: 448, scheme: scheme, store: speakers, log: log, out: out)
            // Synthetic Home Assistant registry assignments, never a saved home.
            for layout in RoomsLayoutPreference.allCases {
                var previewArguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
                previewArguments[RoomsLayoutPreference.key] = layout.rawValue
                UserDefaults.standard.setVolatileDomain(previewArguments, forName: UserDefaults.argumentDomain)
                let explorer = RoomsExplorerState()
                if layout == .interactive { explorer.selectedRoom = .area("kitchen") }
                try save(PreviewScreenshotPanel(selected: .rooms, nativeScrollViewport: true) {
                    RoomsOverview(shown: true, explorer: explorer, open: { _ in }, openDevice: { _ in })
                }, name: "guide-rooms-\(layout.rawValue)-\(suffix)", width: 448,
                         scheme: scheme, store: speakers, log: log, out: out, native: true)
            }
            try save(PreviewScreenshotPanel(selected: .activity, nativeScrollViewport: true) { ActivityPage(shown: true) },
                     name: "guide-activity-empty-\(suffix)", width: 448, scheme: scheme,
                     store: speakers, log: ActivityLog(previewItems: []), out: out, native: true)
            try save(PreviewScreenshotPanel(selected: .climate(climate.id)) { ClimatePage(entityID: climate.id, shown: true) },
                     name: "guide-climate-\(suffix)", width: 448, scheme: scheme, store: climateStore, log: log, out: out)
            try save(PreviewScreenshotPanel(selected: nil, settings: true, nativeScrollViewport: true) { SettingsView(previewSignedIn: false) {} },
                     name: "guide-connect-\(suffix)", width: 448, scheme: scheme, store: energy.store, log: log, out: out, native: true)
            let adminGuide = HAAdminGuideSnapshot.example()
            try save(PreviewScreenshotPanel(selected: nil, settings: true, nativeScrollViewport: true) {
                AccountPage(documentation: adminGuide) {}
            }, name: "guide-account-\(suffix)", width: 448, scheme: scheme,
                     store: speakers, log: log, out: out, native: true)
            try save(HAAdminWindow(documentation: adminGuide).frame(height: 560),
                     name: "guide-integrations-\(suffix)", width: 940, scheme: scheme,
                     store: speakers, log: log, out: out, native: true)
            try save(HAAdminWindow(documentation: .example(section: .add)).frame(height: 560),
                     name: "guide-integration-add-\(suffix)", width: 940, scheme: scheme,
                     store: speakers, log: log, out: out, native: true)
            try save(PreviewScreenshotPanel(selected: nil, settings: true) { HelpAndSupport {} },
                     name: "guide-help-\(suffix)", width: 448, scheme: scheme, store: energy.store, log: log, out: out)
            try save(PreviewScreenshotPanel(selected: nil, settings: true) { HelpAndSupport(initialRequest: .bug) {} },
                     name: "guide-bug-report-\(suffix)", width: 448, scheme: scheme, store: energy.store, log: log, out: out)
            try save(PreviewScreenshotPanel(selected: nil, settings: true) {
                VStack(alignment: .leading, spacing: 20) {
                    PageHeader(eyebrow: "Hearth", title: "Settings") { EmptyView() }
                    SectionSettings()
                }
            }, name: "guide-navigation-\(suffix)", width: 448, scheme: scheme, store: energy.store, log: log, out: out)
            // Close-up of the actual shared component, with illustrative cameras only.
            try save(PinnedTitleBar(info: PinnedTitle(eyebrow: "7 cameras · Updated now", title: "Security", back: nil,
                         illustrations: [.doorbell, .outdoorCamera, .indoorCamera], count: 7, top: -18, bottom: 32))
                         .background(Theme.base).environment(\.hearthDocumentationPreview, true),
                     name: "guide-heading-\(suffix)", width: 448, scheme: scheme, store: energy.store, log: log, out: out)
            for (name, title, summary, symbols) in [
                ("activity", "Activity", "4 people seen today", ["bell.fill", "figure.walk.motion", "shield.lefthalf.filled"]),
                ("preferences", "Settings", "Hearth", ["person.crop.circle", "slider.horizontal.3", "questionmark.circle"])
            ] {
                try save(PinnedTitleBar(info: PinnedTitle(eyebrow: summary, title: title, back: nil,
                             symbols: symbols, top: -18, bottom: 32))
                             .background(Theme.base).environment(\.hearthDocumentationPreview, true),
                         name: "guide-heading-\(name)-\(suffix)", width: 448, scheme: scheme, store: energy.store, log: log, out: out)
            }
            try save(PreviewScreenshotPanel(selected: .activity) { ActivityPage(shown: true) },
                     name: "guide-activity-\(suffix)", width: 448, scheme: scheme, store: energy.store, log: log, out: out)
            try save(CarCard(device: car) { _ in }, name: "vehicle-\(suffix)", width: 368,
                     scheme: scheme, store: engine.store, log: log, out: out)
            try save(DevicesPage(hub: hub, shown: true, visible: false), name: "devices-\(suffix)", width: 368,
                     scheme: scheme, store: engine.store, log: log, out: out)
            for layout in ["grid", "list"] {
                try save(MediaPage(players: players, shown: true, previewLayout: layout), name: "speakers-\(layout)-\(suffix)", width: 368,
                         scheme: scheme, store: speakers, log: log, out: out)
            }
            for (name, x, y) in [("left", 187.0, 350.0), ("right", 395.0, 350.0),
                                  ("bottom-left", 187.0, 642.0), ("bottom-right", 395.0, 642.0)] {
                try save(TooltipPreview(x: x, y: y), name: "tooltip-\(name)-\(suffix)", width: 448,
                         scheme: scheme, store: climateStore, log: log, out: out)
            }
            try save(TooltipPreview(x: 395, y: 642, message: String(repeating: "A simulated long camera error. ", count: 90)),
                     name: "tooltip-long-message-\(suffix)", width: 448,
                     scheme: scheme, store: climateStore, log: log, out: out)
            for (index, time) in [0.0, 0.8, 1.6, 2.4, 3.2].enumerated() {
                let edge = ACUnitView(power: 1, mode: "cool", intensity: 1, swing: true,
                    width: ClimateIllustrationLayout.bodyWidth, display: "16°", reach: 0.46, chill: 1, previewTime: time)
                    .environment(\.colorScheme, scheme)
                let alphaRenderer = ImageRenderer(content: edge)
                alphaRenderer.scale = 2
                guard let image = alphaRenderer.cgImage,
                      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                    throw ProviderError("Couldn't render the airflow edge review")
                }
                try png.write(to: out.appendingPathComponent("airflow-alpha-\(suffix)-\(index).png"), options: .atomic)
                try save(VStack(spacing: 0) {
                    edge
                    Text("16°").font(.system(size: 76, weight: .thin)).foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }, name: "airflow-edge-\(suffix)-\(index)", width: 404,
                         scheme: scheme, store: climateStore, log: log, out: out)
            }
            try save(HStack(alignment: .top, spacing: 16) {
                ForEach([16.0, 24, 30], id: \.self) { value in
                    VStack(spacing: 6) {
                        Text("\(Int(value))°").font(.system(size: 18, weight: .medium)).foregroundStyle(Theme.ink)
                        ACUnitView(power: 1, mode: "cool", intensity: 0.8, swing: false, width: 180, display: "\(Int(value))°",
                                   reach: 0.46, chill: ACAirAppearance.normalizedChill(target: value, lowerBound: 16, upperBound: 30), previewTime: 1.4)
                    }
                }
            }, name: "airflow-temperature-\(suffix)", width: 780, scheme: scheme, store: climateStore, log: log, out: out)
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
        try save(MapWindow(previewImage: image).frame(height: 760), name: "map-layout-dark", width: 1180, scheme: .dark, store: store, log: ActivityLog(previewItems: []), out: out, native: true)
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
            // Give native controls, lazy scroll content and geometry preferences
            // bounded layout passes before capture. Nothing is ordered on screen;
            // only synthetic views are mounted and no device session is started.
            for _ in 0..<6 {
                host.needsLayout = true
                host.layoutSubtreeIfNeeded()
                host.displayIfNeeded()
                _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
            }
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
    /// Menus and lazy room strips need an AppKit-backed scroll viewport. The
    /// ImageRenderer path stays flat because it cannot render native scroll views.
    var nativeScrollViewport = false
    @ViewBuilder let content: () -> Content
    private let pages: [Page] = [.climate("climate.preview_living_room"), .security, .rooms, .devices, .map, .activity]

    private var contentBottomInset: CGFloat {
        if case .climate = selected { return PanelView.fixedContentBottomInset }
        return 0
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if nativeScrollViewport {
                // Mirror PanelView.scrolling so CenteredPageEmptyState receives
                // the same viewport, unscrolled content origin and dock bounds.
                GeometryReader { viewport in
                    ScrollView {
                        content()
                            .padding(.horizontal, PanelView.scrollContentInset)
                            .padding(.top, PanelView.scrollContentInset)
                            .padding(.bottom, PanelView.scrollBottomPadding)
                            .coordinateSpace(name: PageContentCoordinates.space)
                            .environment(\.hearthPageViewportHeight, viewport.size.height)
                            .environment(\.hearthPageDockObstruction, PanelView.footerHeight - PanelView.footerTopExtra)
                    }
                    .scrollIndicators(.never)
                    .coordinateSpace(name: PinnedTitleBar.space)
                    .overlayPreferenceValue(PinnedTitleKey.self, alignment: .top) { PinnedTitleBar(info: $0) }
                }
                .clipped()
            } else {
                content().fixedSize(horizontal: false, vertical: true)
                    .frame(width: 404, height: Theme.panelSize.height - contentBottomInset - 44, alignment: .top)
                    .padding(22).clipped()
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.bottom, contentBottomInset)
            }
            Dock(pages: pages, selected: selected, label: { page in
                switch page {
                case .climate: ("snowflake", "Workspace")
                case .security: ("video", "Security")
                case .rooms: ("square.grid.2x2", "Rooms")
                case .devices: ("plug", "Assets")
                case .map: ("cube.transparent", "3D map")
                case .activity: ("bell", "Activity")
                case .media: ("speaker", "Speakers")
                }
            }, settingsOn: settings, status: (Theme.ok, "Demo"), onSelect: { _ in })
                .padding(.horizontal, 18)
                .padding(.top, PanelView.footerTopExtra).padding(.bottom, PanelView.footerBottomExtra)
                .frame(height: PanelView.footerHeight)
        }
        .frame(width: Theme.panelSize.width, height: Theme.panelSize.height)
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

/// Fixed synthetic anchor positions exercise the actual shared tooltip layout.
private struct TooltipPreview: View {
    let x: CGFloat
    let y: CGFloat
    var message = GridCamera.unreachableNote
    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.base
            VStack(alignment: .leading, spacing: 14) {
                Text("Security").font(.system(size: 24, weight: .semibold))
                Text("Demo cameras").foregroundStyle(Theme.muted)
                HStack(spacing: 10) {
                    ForEach(["Backyard", "Entrance"], id: \.self) { title in
                        VStack(alignment: .leading, spacing: 8) {
                            DeviceArtView(kind: .outdoorCamera, accent: Theme.brand, size: 58)
                            Text(title).font(.system(size: 13, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.raised))
                    }
                }
            }.padding(22)
            Image(systemName: "info.circle").font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26).background(Circle().fill(Theme.raised))
                .panelTooltip(message, presented: true)
                .position(x: x, y: y)
        }
        .frame(width: 448, height: Theme.panelSize.height)
        .panelTooltipHost()
    }
}
