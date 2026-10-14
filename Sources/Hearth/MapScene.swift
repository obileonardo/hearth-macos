import Combine
import SceneKit
import SwiftUI

/// Builds and runs one view of the house in SceneKit: the demo house or a scan in Hearth's clay,
/// floor by floor, a glowing pin for every placed device, and energy flowing along the floors from
/// the inverter to whatever is using power. It also owns the camera: scroll zooms toward the
/// pointer, a drag moves the house, a right-drag turns it, and the plan looks straight down.
/// The panel preview and the full window each have their own.
@MainActor
final class MapSceneController: NSObject, ObservableObject {
    let scene = SCNScene()
    /// The full window gets shadows, ambient occlusion, bloom and labels; the panel preview stays light.
    let full: Bool

    /// Watts per pin, refreshed every couple of seconds while the view is on screen.
    @Published private(set) var watts: [String: Double] = [:]
    @Published private(set) var loadFailed = false

    /// The ground floor's centre and extent, and how high its floor is.
    private(set) var center = SIMD3<Float>(5, 0, 3.5)
    private(set) var radius: Float = 7
    private(set) var floorY: Float = 0
    /// Floor to floor.
    private(set) var storeyHeight: Float = DemoHouse.storeyHeight

    private let house = SCNNode()
    private let pinsRoot = SCNNode()
    private let flowsRoot = SCNNode()
    private let contactRoot = SCNNode()
    private lazy var rayTracing = full ? MapRayTracing() : nil
    private var contactSignature = ""
    private var contactGeneration = 0
    private let cameraNode = SCNNode()
    private var pinNodes: [String: PinNode] = [:]
    private var builtFor: String?
    private var flowSignature = ""
    private var timer: Timer?
    private var bag: Set<AnyCancellable> = []
    private weak var store: HomeStore?
    let maps = HomeMapStore.shared
    /// Scans read from disk once, then copied for each rebuild.
    private var scanCache: [URL: ScanTemplate] = [:]

    weak var view: SCNView?

    /// Only animates and refreshes while someone can see it.
    var active = false {
        didSet {
            guard active != oldValue else { return }
            scene.isPaused = !active
            if active { startTimer() } else {
                timer?.invalidate(); timer = nil
                contactGeneration += 1
                contactSignature = ""
            }
        }
    }

    init(full: Bool) {
        self.full = full
        super.init()
        scene.rootNode.addChildNode(house)
        scene.rootNode.addChildNode(pinsRoot)
        scene.rootNode.addChildNode(flowsRoot)
        scene.rootNode.addChildNode(contactRoot)
        scene.background.contents = Self.backdrop
        scene.lightingEnvironment.contents = NSColor(white: 0.32, alpha: 1)
        scene.lightingEnvironment.intensity = 0.9
        setUpLights()
        setUpCamera()
        scene.isPaused = true
    }

    func attach(_ store: HomeStore) {
        guard self.store == nil else { return }
        self.store = store
        rebuildHouseIfNeeded()
        refresh()
        syncCamera()
        // Pins, the chosen map, its floors and the style options all come from the shared map store.
        maps.objectWillChange
            .debounce(for: .milliseconds(30), scheduler: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                self.rebuildHouseIfNeeded()
                self.refresh()
                self.syncCamera()
            }
            .store(in: &bag)
    }

    // MARK: Floors

    /// In "all floors", upper floors lift a little higher than they really are, so you can see
    /// between them, and fade so the floors below show through.
    private var exploded: Bool { maps.shownFloor == nil && maps.hasFloors }
    private func lift(_ level: Int) -> Float { exploded ? Float(level) * 1.9 : 0 }
    private func up(_ level: Int) -> Float { Float(level) * storeyHeight }
    /// A floor's surface as drawn, with the lift.
    private func floorSurface(_ level: Int) -> Float { floorY + up(level) + lift(level) }
    private func isVisible(_ level: Int) -> Bool { maps.visibleLevels.contains(level) }

    /// Where a pin is drawn: where it really is, plus its floor's lift.
    private func drawn(_ pin: MapPin) -> SIMD3<Float> { pin.position + SIMD3(0, lift(pin.level), 0) }

    // MARK: Camera

    /// The camera orbits a point on the floor in view. Distance doubles as the plan's scale.
    private var target = SIMD3<Float>(5, 0, 3.5)
    private var distance: Float = 12
    private var yaw: Float = 0
    private var pitch: Float = MapSceneController.defaultPitch
    static let defaultPitch: Float = atan2(0.9, 0.82)
    private static let planPitch: Float = .pi / 2
    /// Lower for the stack, so the gaps between floors open up.
    private static let stackPitch: Float = 0.6
    private var lastFrameKey = ""
    private var lastPlan = false
    private var lastFocus = ""

    private var fov: Float { Float(cameraNode.camera?.fieldOfView ?? 38) * .pi / 180 }

    /// Far enough back that the floor, or the whole stack, fits the lens.
    private var fitDistance: Float {
        let tall = exploded ? Float(maps.floors.count - 1) * (storeyHeight + 1.9) * 0.3 : 0
        let r = radius + tall
        // The panel preview is wide and short, so it can come much closer than the window.
        return r / tan(fov / 2) * (full ? 1.0 : 0.66)
    }
    private var minDistance: Float { fitDistance * 0.16 }
    private var maxDistance: Float { fitDistance * 1.8 }

    /// The height the camera orbits at: the floor on show, or the middle of the stack.
    private var focusY: Float {
        if let f = maps.shownFloor { return floorSurface(f) }
        let levels = maps.floors.map(\.level)
        guard let lo = levels.min(), let hi = levels.max() else { return floorY }
        return (floorSurface(lo) + floorSurface(hi)) / 2
    }

    private static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private func setUpCamera() {
        let camera = SCNCamera()
        camera.fieldOfView = full ? 36 : 40
        camera.zNear = 0.05
        camera.zFar = 400
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = -0.15
        if full {
            camera.bloomIntensity = 0.9
            camera.bloomThreshold = 0.75
            camera.bloomBlurRadius = 10
            camera.screenSpaceAmbientOcclusionIntensity = 1.1
            camera.screenSpaceAmbientOcclusionRadius = 0.35
            camera.vignettingIntensity = 0.35
            camera.vignettingPower = 0.6
        } else {
            camera.bloomIntensity = 0.5
            camera.bloomThreshold = 0.8
        }
        cameraNode.camera = camera
        cameraNode.name = "camera"
        scene.rootNode.addChildNode(cameraNode)
        // A broad, quiet fill follows the viewpoint. The key remains fixed in
        // world space, so turning the house reveals its true shaded surfaces.
        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light!.type = .omni
        fill.light!.intensity = 120
        fill.light!.color = NSColor(calibratedRed: 0.84, green: 0.9, blue: 1, alpha: 1)
        fill.position = SCNVector3(-3, 4, 1)
        cameraNode.addChildNode(fill)
    }

    private func setUpLights() {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.intensity = 320
        ambient.light!.color = NSColor(calibratedRed: 0.86, green: 0.9, blue: 1.0, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light!.type = .directional
        key.light!.intensity = 950
        key.light!.color = NSColor(calibratedRed: 1.0, green: 0.95, blue: 0.88, alpha: 1)
        key.eulerAngles = SCNVector3(-1.05, 0.6, 0)
        if full {
            key.light!.castsShadow = true
            key.light!.shadowMode = .deferred
            key.light!.shadowRadius = 6
            key.light!.shadowSampleCount = 12
            key.light!.shadowColor = NSColor(white: 0, alpha: 0.45)
            key.light!.automaticallyAdjustsShadowProjection = true
        }
        scene.rootNode.addChildNode(key)

        // A soft light from below, so the underside of the floors reads as clay when the camera
        // swings under the house in Turn mode, rather than a black slab.
        let under = SCNNode()
        under.light = SCNLight()
        under.light!.type = .directional
        under.light!.intensity = 420
        under.light!.color = NSColor(calibratedRed: 0.9, green: 0.93, blue: 1.0, alpha: 1)
        under.eulerAngles = SCNVector3(1.15, -0.5, 0)
        scene.rootNode.addChildNode(under)
    }

    /// Places the camera from the orbit: above and in front of the target, looking at it.
    private func applyCamera(animated: Bool = false, duration: Double = 0.45, completion: (() -> Void)? = nil) {
        let dir = SIMD3<Float>(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
        let orientation = simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0)) * simd_quatf(angle: -pitch, axis: SIMD3(1, 0, 0))
        let animate = animated && !Self.reduceMotion
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animate ? duration : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(controlPoints: 0.3, 0, 0.2, 1)
        SCNTransaction.completionBlock = completion
        cameraNode.simdPosition = target + dir * distance
        cameraNode.simdOrientation = orientation
        cameraNode.camera?.orthographicScale = Double(distance * tan(fov / 2))
        SCNTransaction.commit()
    }

    /// Frames the floor in view (or every floor) from above and in front.
    func fit(animated: Bool) {
        target = SIMD3(center.x, focusY, center.z)
        distance = fitDistance
        yaw = 0
        pitch = maps.planView ? Self.planPitch : exploded ? Self.stackPitch : Self.defaultPitch
        cameraNode.camera?.usesOrthographicProjection = maps.planView
        applyCamera(animated: animated, duration: 0.55)
    }

    /// The first frame, and whenever the map, the floor on show or the plan changes.
    func syncCamera() {
        let frameKey = "\(maps.current?.path ?? "demo")|\(center)|\(radius)|\(maps.floors.count)"
        if frameKey != lastFrameKey {
            let first = lastFrameKey.isEmpty
            lastFrameKey = frameKey
            lastPlan = maps.planView
            lastFocus = focusKey
            fit(animated: !first)
            return
        }
        if maps.planView != lastPlan {
            lastPlan = maps.planView
            lastFocus = focusKey
            transitionPlan(maps.planView)
            return
        }
        if focusKey != lastFocus {
            lastFocus = focusKey
            // A new floor comes into view centred, whatever panning happened on the last one.
            target = SIMD3(center.x, focusY, center.z)
            if exploded {
                distance = max(distance, fitDistance * 0.9)
                pitch = min(pitch, Self.stackPitch)
            }
            distance = min(max(distance, minDistance), maxDistance)
            applyCamera(animated: true, duration: 0.5)
        }
    }

    private var focusKey: String { "\(maps.shownFloor.map(String.init) ?? "all")|\(maps.floors.count)" }

    /// Into the plan: tilt to straight down, then flatten to a true plan. Out: lift the
    /// perspective back, then tilt.
    private func transitionPlan(_ on: Bool) {
        target.y = focusY
        if on {
            pitch = Self.planPitch
            applyCamera(animated: true, duration: 0.76) { [weak self] in
                guard let self, self.maps.planView else { return }
                self.cameraNode.camera?.usesOrthographicProjection = true
            }
        } else {
            cameraNode.camera?.usesOrthographicProjection = false
            pitch = exploded ? Self.stackPitch : Self.defaultPitch
            applyCamera(animated: true, duration: 0.76)
        }
    }

    // MARK: Moving the camera

    /// Where the pointer meets the horizontal plane at `y`, through the current camera.
    func groundPoint(_ p: CGPoint, in view: SCNView, y: Float) -> SIMD3<Float>? {
        let near = view.unprojectPoint(SCNVector3(p.x, p.y, 0))
        let far = view.unprojectPoint(SCNVector3(p.x, p.y, 1))
        let a = SIMD3<Float>(Float(near.x), Float(near.y), Float(near.z))
        let b = SIMD3<Float>(Float(far.x), Float(far.y), Float(far.z))
        let d = b - a
        guard abs(d.y) > 1e-6 else { return nil }
        let t = (y - a.y) / d.y
        guard t > 0 else { return nil }
        return a + d * t
    }

    /// Zooms by `factor` (under 1 is closer) toward the point under the pointer, which stays put.
    /// Past the limits it gives a little, like a rubber band, and springs back when you stop.
    func zoom(by factor: Float, at p: CGPoint, in view: SCNView) {
        guard factor.isFinite, factor > 0 else { return }
        // Past a limit the excess is squeezed, so it gives a little and no more.
        var next = distance * factor
        if next < minDistance { next = minDistance * pow(next / minDistance, 0.25) }
        if next > maxDistance { next = maxDistance * pow(next / maxDistance, 0.25) }
        let f = next / distance
        if let g = groundPoint(p, in: view, y: target.y) {
            target.x = g.x + (target.x - g.x) * f
            target.z = g.z + (target.z - g.z) * f
        }
        distance *= f
        applyCamera()
    }

    /// The point on the floor under the pointer when a drag starts.
    func grab(at p: CGPoint, in view: SCNView) -> SIMD3<Float>? {
        groundPoint(p, in: view, y: target.y)
    }

    /// Moves the house with the pointer, so the grabbed spot stays under it.
    func pan(grabbed: SIMD3<Float>, to p: CGPoint, in view: SCNView) {
        guard let now = groundPoint(p, in: view, y: grabbed.y) else { return }
        target.x += grabbed.x - now.x
        target.z += grabbed.z - now.z
        applyCamera()
    }

    /// Turns around the target. In the plan it only spins. In Turn mode the camera may swing
    /// right under the floor, to look up at the house; in Move mode it stays above it.
    func orbit(yaw dYaw: Float, pitch dPitch: Float) {
        yaw += dYaw
        if !maps.planView {
            let floor: Float = maps.dragMode == .turn ? -1.45 : 0.17
            pitch = min(max(pitch + dPitch, floor), 1.53)
        }
        applyCamera()
    }

    /// Back above the floor when Turn mode is switched off, so Move mode never starts upside down.
    func surface() {
        guard pitch < 0.17, !maps.planView else { return }
        pitch = Self.defaultPitch
        applyCamera(animated: true, duration: 0.5)
    }

    /// After a zoom or a drag: back inside the limits, softly.
    func settle() {
        let clampedDistance = min(max(distance, minDistance), maxDistance)
        let reach = radius * 1.25
        let clampedX = min(max(target.x, center.x - reach), center.x + reach)
        let clampedZ = min(max(target.z, center.z - reach), center.z + reach)
        guard clampedDistance != distance || clampedX != target.x || clampedZ != target.z else { return }
        distance = clampedDistance
        target.x = clampedX
        target.z = clampedZ
        applyCamera(animated: true, duration: 0.38)
    }

    // MARK: The house

    /// Dark or light, following the view's appearance.
    private(set) var dark = true
    /// The small menu preview always reveals the rooms. The full window keeps
    /// the owner's independently chosen solid / see-through / cut setting.
    private var wallMode: WallMode { full ? maps.wallMode : .seeThrough }

    /// Repaints the backdrop, the room names and the flows for the other appearance.
    func setAppearance(dark: Bool) {
        guard dark != self.dark else { return }
        self.dark = dark
        scene.background.contents = dark ? Self.backdrop : Self.paperBackdrop
        rebuildHouseIfNeeded()
        flowSignature = ""
        updateFlows()
        updateContactShadows()
    }

    private func rebuildHouseIfNeeded() {
        let floorsKey = maps.floors.map { "\($0.level):\($0.scan ?? "")" }.joined(separator: ",")
        let signature = "\(maps.current?.path ?? "demo")|\(maps.showTextures)|\(wallMode.rawValue)|\(dark)|\(maps.planView)|\(floorsKey)|\(maps.visibleLevels)|\(exploded)"
        guard signature != builtFor else { return }
        builtFor = signature
        house.childNodes.forEach { $0.removeFromParentNode() }
        house.transform = SCNMatrix4Identity
        loadFailed = false
        if let url = maps.current {
            if !buildScanMap(url) {
                loadFailed = true
                buildDemoHouse()
            }
        } else {
            buildDemoHouse()
        }
        flowSignature = ""
    }

    /// A floor's own node, named so a drop can tell which floor it landed on, lifted when the
    /// floors are spread apart, and faded when it sits above another floor in the stack.
    private func levelNode(_ level: Int) -> SCNNode {
        let node = SCNNode()
        node.name = "level-\(level)"
        node.position = SCNVector3(0, CGFloat(lift(level)), 0)
        let lowest = maps.visibleLevels.min() ?? 0
        if exploded && level > lowest { node.opacity = 0.36 }
        house.addChildNode(node)
        return node
    }

    private func buildDemoHouse() {
        floorY = 0
        storeyHeight = DemoHouse.storeyHeight
        center = SIMD3(DemoHouse.size.x / 2, 0, DemoHouse.size.y / 2)
        radius = 7

        let lowest = maps.visibleLevels.min() ?? 0
        for storey in DemoHouse.floors where isVisible(storey.level) {
            let node = levelNode(storey.level)
            let base = up(storey.level)

            // The ground under the lowest floor on show, then the floor itself.
            if storey.level == lowest {
                let ground = SCNNode(geometry: SCNCylinder(radius: 7.6, height: 0.02))
                ground.geometry!.materials = [Self.clay(dark ? 0.06 : 0.86)]
                ground.position = SCNVector3(center.x, base - 0.06, center.z)
                node.addChildNode(ground)
            }
            let slab = SCNNode(geometry: SCNBox(width: CGFloat(DemoHouse.size.x) + 0.24, height: 0.08, length: CGFloat(DemoHouse.size.y) + 0.24, chamferRadius: 0.02))
            slab.geometry!.materials = [maps.planView ? Self.flat(dark ? 0.13 : 0.93) : Self.clay(0.34)]
            slab.position = SCNVector3(center.x, base - 0.04, center.z)
            slab.name = "floor"
            node.addChildNode(slab)

            let height: Float = maps.planView || wallMode == .cut ? 1.15 : DemoHouse.wallHeight
            for wall in storey.walls {
                for (a, b) in segments(of: wall) {
                    node.addChildNode(wallNode(from: a, to: b, height: height, base: base))
                }
            }
            for block in storey.furniture {
                let box = SCNBox(width: CGFloat(block.size.x), height: CGFloat(block.size.y), length: CGFloat(block.size.z), chamferRadius: min(0.04, CGFloat(block.size.y) / 3))
                box.materials = [maps.planView ? Self.flat(dark ? 0.24 : 0.82) : Self.clay(block.tone)]
                let piece = SCNNode(geometry: box)
                piece.position = SCNVector3(block.center.x, base + block.center.y, block.center.z)
                if maps.planView { piece.opacity = 0.7 }
                node.addChildNode(piece)
            }
            if full || maps.planView {
                for room in storey.rooms {
                    let label = Self.floorLabel(room.name, dark: dark)
                    label.position = SCNVector3(room.center.x, base + 0.012, room.center.y + (maps.planView ? 0 : 0.9))
                    node.addChildNode(label)
                }
            }
        }
    }

    /// A wall split around its door openings.
    private func segments(of wall: DemoHouse.Wall) -> [(SIMD2<Float>, SIMD2<Float>)] {
        let length = simd_distance(wall.from, wall.to)
        let dir = (wall.to - wall.from) / length
        var cuts: [(Float, Float)] = wall.doors.map { ($0.0 - $0.1 / 2, $0.0 + $0.1 / 2) }.sorted { $0.0 < $1.0 }
        cuts.append((length, length))
        var start: Float = 0
        var parts: [(SIMD2<Float>, SIMD2<Float>)] = []
        for (a, b) in cuts {
            if a - start > 0.05 { parts.append((wall.from + dir * start, wall.from + dir * a)) }
            start = b
        }
        return parts
    }

    private func wallNode(from a: SIMD2<Float>, to b: SIMD2<Float>, height: Float, base: Float) -> SCNNode {
        let length = simd_distance(a, b) + 0.12
        let box = SCNBox(width: CGFloat(length), height: CGFloat(height), length: 0.12, chamferRadius: 0.012)
        let node = SCNNode(geometry: box)
        if maps.planView {
            // The plan draws walls as clean ink lines.
            box.materials = [Self.flat(dark ? 0.86 : 0.16)]
        } else if wallMode == .seeThrough {
            box.materials = [Self.frosted(dark: dark)]
            node.addChildNode(Self.edges(width: length, height: height, length: 0.12, dark: dark))
        } else {
            box.materials = [Self.clay(0.93)]
        }
        let mid = (a + b) / 2
        node.position = SCNVector3(mid.x, base + height / 2, mid.y)
        node.eulerAngles.y = CGFloat(-atan2(b.y - a.y, b.x - a.x))
        node.name = "wall"
        return node
    }

    // MARK: Scans

    /// A scan read from disk, scaled to metres, with its bounds.
    private struct ScanTemplate {
        let node: SCNNode
        let lo: SIMD3<Float>
        let hi: SIMD3<Float>
        var size: SIMD3<Float> { hi - lo }
        var middle: SIMD3<Float> { (lo + hi) / 2 }
    }

    private func template(_ url: URL) -> ScanTemplate? {
        if let cached = scanCache[url] { return cached }
        guard let source = try? SCNScene(url: url, options: [.convertToYUp: true]) else { return nil }
        let container = SCNNode()
        for child in source.rootNode.childNodes { container.addChildNode(child) }
        let (l, h) = container.boundingBox
        var lo = SIMD3<Float>(Float(l.x), Float(l.y), Float(l.z))
        var hi = SIMD3<Float>(Float(h.x), Float(h.y), Float(h.z))
        let size = hi - lo
        guard size.x.isFinite, max(size.x, size.y, size.z) > 0.01 else { return nil }
        // OBJ files are often in centimetres; RoomPlan and most phone scanners use metres.
        if max(size.x, size.y, size.z) > 80 {
            container.scale = SCNVector3(0.01, 0.01, 0.01)
            lo *= 0.01
            hi *= 0.01
        }
        let made = ScanTemplate(node: container, lo: lo, hi: hi)
        scanCache[url] = made
        return made
    }

    /// The scanned map: the ground floor's scan sets the frame; each upper floor's scan is
    /// centred over it and stood a storey higher. False if the ground floor can't be read.
    private func buildScanMap(_ url: URL) -> Bool {
        guard let ground = template(url) else { return false }
        floorY = ground.lo.y
        center = SIMD3(ground.middle.x, floorY, ground.middle.z)
        radius = max(3, max(ground.size.x, ground.size.z) * 0.72)
        storeyHeight = max(2.6, ground.size.y + 0.25)

        let lowest = maps.visibleLevels.min() ?? 0
        for floor in maps.floors where isVisible(floor.level) {
            let node = levelNode(floor.level)
            guard let file = maps.scanURL(for: floor), let scan = floor.level == 0 ? ground : template(file) else { continue }
            let copy = Self.copy(scan.node)
            if floor.level != 0 {
                copy.position = SCNVector3(center.x - scan.middle.x, floorY + up(floor.level) - scan.lo.y, center.z - scan.middle.z)
            }
            node.addChildNode(copy)

            if maps.planView || !maps.showTextures { restyle(copy) }
            let cutAt = floorY + up(floor.level) + lift(floor.level) + 1.2
            if maps.planView || wallMode == .cut {
                applyCut(to: copy, height: cutAt)
            } else if wallMode == .seeThrough {
                frost(copy)
            }

            if floor.level == lowest {
                let disc = SCNNode(geometry: SCNCylinder(radius: CGFloat(radius * 1.35), height: 0.02))
                disc.geometry!.materials = [Self.clay(dark ? 0.06 : 0.86)]
                disc.position = SCNVector3(center.x, floorY + up(floor.level) - 0.03, center.z)
                node.addChildNode(disc)
            }
        }
        return true
    }

    /// A copy whose materials can change without touching the cached scan.
    private static func copy(_ node: SCNNode) -> SCNNode {
        let clone = node.clone()
        clone.enumerateHierarchy { child, _ in
            if let g = child.geometry?.copy() as? SCNGeometry {
                g.materials = g.materials.map { ($0.copy() as? SCNMaterial) ?? $0 }
                child.geometry = g
            }
        }
        return clone
    }

    /// Hearth's clay instead of the scan's own surfaces: light walls, a darker floor, glassy windows.
    private func restyle(_ node: SCNNode) {
        node.enumerateHierarchy { child, _ in
            guard let geometry = child.geometry else { return }
            let name = (child.name ?? "").lowercased() + " " + (child.parent?.name ?? "").lowercased()
            let material: SCNMaterial
            if name.contains("floor") {
                material = maps.planView ? Self.flat(dark ? 0.13 : 0.93) : Self.clay(0.34)
            } else if name.contains("window") || name.contains("opening") {
                material = Self.clay(0.75)
                material.transparency = 0.35
            } else if name.contains("door") {
                material = Self.clay(0.62)
            } else if name.contains("wall") {
                material = maps.planView ? Self.flat(dark ? 0.86 : 0.16) : Self.clay(0.93)
            } else {
                material = maps.planView ? Self.flat(dark ? 0.24 : 0.82) : Self.clay(0.78)
            }
            geometry.materials = Array(repeating: material, count: max(1, geometry.elements.count))
        }
    }

    /// Frosts everything that isn't floor, so devices behind walls show through.
    private func frost(_ node: SCNNode) {
        node.enumerateHierarchy { child, _ in
            let name = (child.name ?? "").lowercased() + " " + (child.parent?.name ?? "").lowercased()
            guard !name.contains("floor"), let geometry = child.geometry else { return }
            for m in geometry.materials {
                m.transparency = 0.2
                m.writesToDepthBuffer = false
                m.isDoubleSided = true
            }
        }
    }

    /// Cuts every surface at waist height so you can look into the rooms from above.
    private func applyCut(to node: SCNNode, height: Float) {
        node.enumerateHierarchy { child, _ in
            for material in child.geometry?.materials ?? [] {
                material.shaderModifiers = [.fragment: Self.cutModifier]
                material.setValue(NSNumber(value: height), forKey: "cutHeight")
                material.isDoubleSided = true
            }
        }
    }

    private static let cutModifier = """
    #pragma arguments
    float cutHeight;
    #pragma body
    float4 hearthWorld = scn_frame.inverseViewTransform * float4(_surface.position, 1.0);
    if (hearthWorld.y > cutHeight) { discard_fragment(); }
    """

    // MARK: Pins and power

    private func startTimer() {
        timer?.invalidate()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Reads every pin's power, updates the pins, and redraws the energy flow when it has changed.
    func refresh() {
        guard let store else { return }
        var next: [String: Double] = [:]
        for pin in maps.pins {
            if let w = MapPower.watts(pin, store: store) { next[pin.id] = w }
        }
        watts = next
        updatePins()
        updateFlows()
        updateContactShadows()
    }

    private func updatePins() {
        let ids = Set(maps.pins.map(\.id))
        for (id, node) in pinNodes where !ids.contains(id) {
            node.removeFromParentNode()
            pinNodes[id] = nil
        }
        for pin in maps.pins {
            let node = pinNodes[pin.id] ?? {
                let n = PinNode(pin: pin, full: full)
                pinsRoot.addChildNode(n)
                pinNodes[pin.id] = n
                return n
            }()
            node.isHidden = !isVisible(pin.level)
            node.update(pin: pin, at: drawn(pin), watts: watts[pin.id], role: MapPower.role(of: pin), floorY: floorSurface(pin.level))
        }
    }

    /// Trace only the native device geometry, with short hemisphere rays. The
    /// pass is cached until placements/floors/style change, never on camera motion.
    private func contactInput() -> (String, [MapRayTracing.Tile]) {
        let pins = maps.pins.filter { isVisible($0.level) && MapDeviceModel.supports($0.art) }
        let signature = "\(builtFor ?? "")|\(dark)|\(maps.planView)|" + pins.map {
            "\($0.id):\($0.x),\($0.y),\($0.z),\($0.level):\(floorSurface($0.level))"
        }.joined(separator: "|")
        let tiles = pins.map { pin in
            let large = [.fridge, .tv, .airConditioner].contains(pin.art)
            return MapRayTracing.Tile(center: SIMD3(pin.x, floorSurface(pin.level) + 0.007, pin.z),
                                      span: large ? 3 : 1.6, opacity: dark ? 0.28 : 0.18)
        }
        return (signature, tiles)
    }

    private func updateContactShadows() {
        guard full, active, !maps.planView, let rayTracing else {
            if maps.planView { contactRoot.childNodes.forEach { $0.removeFromParentNode() }; contactSignature = "" }
            return
        }
        let (signature, tiles) = contactInput()
        guard signature != contactSignature else { return }
        contactSignature = signature
        contactRoot.childNodes.forEach { $0.removeFromParentNode() }
        contactGeneration += 1
        let token = contactGeneration
        let vertices = MapRayTracing.triangles(in: pinsRoot)
        rayTracing.request(vertices: vertices, tiles: tiles) { [weak self] images in
            guard let self, token == self.contactGeneration, self.active, !self.maps.planView else { return }
            self.installContactShadows(images, tiles: tiles)
        }
    }

    /// Offline exports explicitly finish the pass before snapshotting. Production
    /// always schedules it off the main thread and continues using native shadows.
    func finishContactShadowsForPreview() {
        guard full, !maps.planView, let rayTracing else { return }
        let (_, tiles) = contactInput()
        installContactShadows(rayTracing.render(vertices: MapRayTracing.triangles(in: pinsRoot), tiles: tiles), tiles: tiles)
    }

    private func installContactShadows(_ images: [CGImage?], tiles: [MapRayTracing.Tile]) {
        contactRoot.childNodes.forEach { $0.removeFromParentNode() }
        for (tile, image) in zip(tiles, images) {
            guard let image else { continue }
            let plane = SCNPlane(width: CGFloat(tile.span), height: CGFloat(tile.span))
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = image
            material.blendMode = .alpha
            material.writesToDepthBuffer = false
            material.isDoubleSided = false
            plane.materials = [material]
            let node = SCNNode(geometry: plane)
            node.name = "ray-contact-shadow"
            node.castsShadow = false
            node.categoryBitMask = 1 // Kept outside the house/pin hit-test roots.
            node.simdPosition = tile.center
            node.eulerAngles.x = -.pi / 2
            contactRoot.addChildNode(node)
        }
    }

    var selected: String? {
        didSet {
            for (id, node) in pinNodes { node.setSelected(id == selected) }
        }
    }

    /// The source energy flows out of: the inverter if one is placed, else a battery, else solar.
    private var source: MapPin? {
        let sources = maps.pins.filter { MapPower.role(of: $0) == .source }
        return sources.first { $0.art == .inverter } ?? sources.first { $0.art == .battery } ?? sources.first
    }

    private func updateFlows() {
        guard let source else {
            if !flowSignature.isEmpty { flowsRoot.childNodes.forEach { $0.removeFromParentNode() }; flowSignature = "" }
            return
        }
        let loads = maps.pins.filter { MapPower.role(of: $0) == .load && (watts[$0.id] ?? 0) > 1 && isVisible($0.level) }
        // Only rebuild when a flow appears, goes, moves or changes size noticeably, or the view changes.
        let view = "\(maps.visibleLevels)|\(exploded)|\(dark)"
        let signature = view + "|" + ([source] + loads).map { pin -> String in
            let bucket = Int((MapPower.glow(watts[pin.id]) * 6).rounded())
            return "\(pin.id)@\(pin.x),\(pin.y),\(pin.z),\(pin.level)#\(bucket)"
        }.joined(separator: "|")
        guard signature != flowSignature else { return }
        flowSignature = signature
        flowsRoot.childNodes.forEach { $0.removeFromParentNode() }
        let riser = maps.isDemo ? DemoHouse.riser : SIMD2(source.x, source.z)
        for load in loads {
            let points = route(from: source, to: load, riser: riser)
            guard points.count > 1 else { continue }
            flowsRoot.addChildNode(FlowNode(points: points, strength: MapPower.glow(watts[load.id]), full: full, dark: dark))
        }
    }

    /// The path power takes: down to the floor, along it in straight runs, and up to the device.
    /// Between floors it climbs the riser; when the source's floor is hidden it rises out of it.
    private func route(from source: MapPin, to load: MapPin, riser: SIMD2<Float>) -> [SIMD3<Float>] {
        let a = drawn(source), b = drawn(load)
        let yA = floorSurface(source.level) + 0.035, yB = floorSurface(load.level) + 0.035
        var points: [SIMD3<Float>]
        if source.level == load.level {
            points = [a] + run(from: SIMD2(a.x, a.z), to: SIMD2(b.x, b.z), y: yA) + [b]
        } else if isVisible(source.level) {
            points = [a] + run(from: SIMD2(a.x, a.z), to: riser, y: yA)
                + run(from: riser, to: SIMD2(b.x, b.z), y: yB) + [b]
        } else {
            points = run(from: riser, to: SIMD2(b.x, b.z), y: yB) + [b]
        }
        return points.enumerated().filter { i, p in i == 0 || simd_distance(p, points[i - 1]) > 0.01 }.map(\.element)
    }

    /// Two straight runs along a floor, the longer first.
    private func run(from a: SIMD2<Float>, to b: SIMD2<Float>, y: Float) -> [SIMD3<Float>] {
        var points = [SIMD3(a.x, y, a.y)]
        let dx = abs(b.x - a.x), dz = abs(b.y - a.y)
        if dx > 0.05 && dz > 0.05 {
            points.append(dx > dz ? SIMD3(b.x, y, a.y) : SIMD3(a.x, y, b.y))
        }
        points.append(SIMD3(b.x, y, b.y))
        return points
    }

    // MARK: Hit testing

    func pinID(at point: CGPoint, in view: SCNView) -> String? {
        let hits = view.hitTest(point, options: [.rootNode: pinsRoot, .searchMode: SCNHitTestSearchMode.all.rawValue, .ignoreHiddenNodes: true])
        for hit in hits {
            var node: SCNNode? = hit.node
            while let n = node {
                if let pin = n as? PinNode { return pin.pinID }
                node = n.parent
            }
        }
        return nil
    }

    /// A named keyboard/assistive alternative to dragging. Try a spaced
    /// point near the current floor's centre without moving existing devices.
    func suggestedPlacement() -> (SIMD3<Float>, Int) {
        let level = maps.shownFloor ?? maps.visibleLevels.min() ?? 0
        let occupied = maps.pins.filter { $0.level == level }
        let spacing: Float = 0.9
        var choice = SIMD2(center.x, center.z)
        search: for ring in 0...3 {
            for x in -ring...ring {
                for z in -ring...ring {
                    guard ring == 0 || abs(x) == ring || abs(z) == ring else { continue }
                    let candidate = SIMD2(center.x + Float(x) * spacing, center.z + Float(z) * spacing)
                    guard simd_distance(candidate, SIMD2(center.x, center.z)) < radius * 0.6 else { continue }
                    if occupied.allSatisfy({ simd_distance(candidate, SIMD2($0.x, $0.z)) >= spacing }) {
                        choice = candidate
                        break search
                    }
                }
            }
        }
        // Pins store their original floor position, not the exploded display lift.
        return (SIMD3(choice.x, floorY + up(level) + 0.04, choice.y), level)
    }

    /// Where a dropped device lands, in the map's own space, and on which floor.
    func surfacePoint(at point: CGPoint, in view: SCNView) -> (SIMD3<Float>, Int)? {
        let hits = view.hitTest(point, options: [.rootNode: house, .searchMode: SCNHitTestSearchMode.closest.rawValue, .ignoreHiddenNodes: true])
        guard let hit = hits.first else { return nil }
        var level = maps.shownFloor ?? 0
        var node: SCNNode? = hit.node
        while let n = node {
            if let name = n.name, name.hasPrefix("level-"), let l = Int(name.dropFirst(6)) { level = l; break }
            node = n.parent
        }
        let p = hit.worldCoordinates, n = hit.worldNormal
        let nudge: CGFloat = abs(n.y) > 0.7 ? 0.04 : 0.08
        let surface = CGFloat(floorSurface(level)) + 0.04
        let y = Float(max(p.y + n.y * nudge, surface)) - lift(level)
        return (SIMD3(Float(p.x + n.x * nudge), y, Float(p.z + n.z * nudge)), level)
    }

    // MARK: Development

    /// `-mapCam "zoom:0.7@0.3,0.6; pan:120,40; orbit:30,10; settle; fit"` drives the camera after
    /// the map appears and logs how far the point under the pointer drifted, to check the maths.
    func runScript(_ script: String, in view: SCNView) {
        var delay = 1.2
        for raw in script.split(separator: ";") {
            let step = raw.trimmingCharacters(in: .whitespaces)
            delay += 0.9
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak view] in
                guard let self, let view else { return }
                self.perform(step, in: view)
            }
        }
    }

    private func perform(_ step: String, in view: SCNView) {
        let parts = step.split(separator: ":", maxSplits: 1).map(String.init)
        let arg = parts.count > 1 ? parts[1] : ""
        let size = view.bounds.size
        func point(_ s: Substring) -> CGPoint {
            let xy = s.split(separator: ",").compactMap { Double($0) }
            return CGPoint(x: size.width * (xy.first ?? 0.5), y: size.height * (xy.count > 1 ? xy[1] : 0.5))
        }
        switch parts.first ?? "" {
        case "zoom":
            let bits = arg.split(separator: "@")
            let f = Float(bits.first ?? "1") ?? 1
            let p = bits.count > 1 ? point(bits[1]) : CGPoint(x: size.width / 2, y: size.height / 2)
            let before = groundPoint(p, in: view, y: target.y)
            zoom(by: f, at: p, in: view)
            if let g = before {
                let after = view.projectPoint(SCNVector3(CGFloat(g.x), CGFloat(g.y), CGFloat(g.z)))
                NSLog("Hearth map: zoom ×\(f) at \(p) drift \(String(format: "%.2f", hypot(after.x - p.x, after.y - p.y))) pt · distance \(distance)")
            }
        case "pan":
            let d = arg.split(separator: ",").compactMap { Double($0) }
            let from = CGPoint(x: size.width / 2, y: size.height / 2)
            let to = CGPoint(x: from.x + (d.first ?? 0), y: from.y + (d.count > 1 ? d[1] : 0))
            if let g = grab(at: from, in: view) {
                pan(grabbed: g, to: to, in: view)
                let after = view.projectPoint(SCNVector3(CGFloat(g.x), CGFloat(g.y), CGFloat(g.z)))
                NSLog("Hearth map: pan to \(to) drift \(String(format: "%.2f", hypot(after.x - to.x, after.y - to.y))) pt")
            }
        case "orbit":
            let d = arg.split(separator: ",").compactMap { Float($0) }
            orbit(yaw: (d.first ?? 0) * .pi / 180, pitch: (d.count > 1 ? d[1] : 0) * .pi / 180)
            NSLog("Hearth map: orbit yaw \(yaw) pitch \(pitch)")
        case "settle": settle(); NSLog("Hearth map: settled to distance \(distance) (limits \(minDistance)…\(maxDistance))")
        case "fit": fit(animated: true)
        case "plan": maps.planView = arg != "off"
        case "floor": maps.floorFilter = arg == "all" ? nil : Int(arg)
        case "walls": if let m = WallMode(rawValue: arg) { maps.wallMode = m }
        default: break
        }
    }

    // MARK: Materials and images

    static func clay(_ white: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor(calibratedWhite: white, alpha: 1)
        m.roughness.contents = NSNumber(value: 0.86)
        m.metalness.contents = NSNumber(value: 0)
        return m
    }

    /// Unlit, for the plan: the same tone however the light falls.
    static func flat(_ white: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = NSColor(calibratedWhite: white, alpha: 1)
        return m
    }

    /// Frosted glass for see-through walls: a faint body that still catches the light.
    static func frosted(dark: Bool) -> SCNMaterial {
        let m = clay(dark ? 0.9 : 0.97)
        m.transparency = 0.17
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        return m
    }

    /// The twelve edges of a wall, so a frosted wall keeps a crisp outline.
    static func edges(width: Float, height: Float, length: Float, dark: Bool) -> SCNNode {
        let x = width / 2, y = height / 2, z = length / 2
        let corners: [SCNVector3] = [
            SCNVector3(-x, -y, -z), SCNVector3(x, -y, -z), SCNVector3(x, y, -z), SCNVector3(-x, y, -z),
            SCNVector3(-x, -y, z), SCNVector3(x, -y, z), SCNVector3(x, y, z), SCNVector3(-x, y, z),
        ]
        let pairs: [Int32] = [0, 1, 1, 2, 2, 3, 3, 0, 4, 5, 5, 6, 6, 7, 7, 4, 0, 4, 1, 5, 2, 6, 3, 7]
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: corners)],
                                   elements: [SCNGeometryElement(indices: pairs, primitiveType: .line)])
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = dark ? NSColor(white: 1, alpha: 0.42) : NSColor(white: 0, alpha: 0.38)
        m.writesToDepthBuffer = false
        geometry.materials = [m]
        let node = SCNNode(geometry: geometry)
        node.renderingOrder = 4
        return node
    }

    /// The panel's near-black, a little lighter in the middle.
    static let backdrop: NSImage = {
        let size = NSSize(width: 512, height: 512)
        return NSImage(size: size, flipped: false) { rect in
            let gradient = NSGradient(colors: [NSColor(calibratedWhite: 0.085, alpha: 1), NSColor(calibratedRed: 0.027, green: 0.027, blue: 0.034, alpha: 1)])
            gradient?.draw(in: NSBezierPath(rect: rect), relativeCenterPosition: NSPoint(x: 0, y: 0.15))
            return true
        }
    }()

    /// The light panel's paper, a little brighter in the middle.
    static let paperBackdrop: NSImage = {
        let size = NSSize(width: 512, height: 512)
        return NSImage(size: size, flipped: false) { rect in
            let gradient = NSGradient(colors: [NSColor(calibratedWhite: 0.995, alpha: 1), NSColor(calibratedRed: 0.93, green: 0.93, blue: 0.94, alpha: 1)])
            gradient?.draw(in: NSBezierPath(rect: rect), relativeCenterPosition: NSPoint(x: 0, y: 0.15))
            return true
        }
    }()

    /// A room name lying flat on the floor.
    static func floorLabel(_ text: String, dark: Bool = true) -> SCNNode {
        let image = render(Text(text.uppercased()).font(.system(size: 22, weight: .semibold)).tracking(3)
            .foregroundStyle(dark ? Color.white.opacity(0.55) : Color.black.opacity(0.55)).padding(4))
        let plane = SCNPlane(width: CGFloat(image.size.width / 120), height: CGFloat(image.size.height / 120))
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = image
        m.writesToDepthBuffer = false
        plane.materials = [m]
        let node = SCNNode(geometry: plane)
        node.castsShadow = false
        node.eulerAngles.x = -.pi / 2
        node.renderingOrder = 5
        return node
    }

    static func render<V: View>(_ view: V) -> NSImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.nsImage ?? NSImage(size: NSSize(width: 2, height: 2))
    }
}

// MARK: Pin

/// A placed device: a glowing bead with a halo sized by its power, its picture floating above,
/// a thin stem to the floor and, in the full map, a label with its name and power.
@MainActor
final class PinNode: SCNNode {
    let pinID: String
    private let full: Bool
    private let core = SCNNode()
    private let halo = SCNNode()
    private let icon = SCNNode()
    private let stem = SCNNode()
    private let label = SCNNode()
    private let ring = SCNNode()
    private var labelText = ""
    private var tint = NSColor.white
    private let illustrationSize: CGFloat
    private var labelHeight: CGFloat = 0

    init(pin: MapPin, full: Bool) {
        pinID = pin.id
        self.full = full
        // Deliberately illustrative proportions: large appliances read as large,
        // while the saved position, power bead and selection target stay unchanged.
        let relativeSize: CGFloat = switch pin.art {
        case .fridge: 2.5
        case .tv: 2.15
        case .airConditioner: 2.1
        default: 1
        }
        illustrationSize = (full ? 0.62 : 0.9) * relativeSize
        super.init()

        let bead = SCNSphere(radius: 0.055)
        bead.segmentCount = 24
        core.geometry = bead
        addChildNode(core)

        let haloPlane = SCNPlane(width: 0.9, height: 0.9)
        let hm = SCNMaterial()
        hm.lightingModel = .constant
        hm.diffuse.contents = Self.haloImage
        hm.blendMode = .add
        hm.writesToDepthBuffer = false
        haloPlane.materials = [hm]
        halo.geometry = haloPlane
        halo.castsShadow = false
        halo.constraints = [SCNBillboardConstraint()]
        halo.renderingOrder = 10
        addChildNode(halo)

        if let model = MapDeviceModel.make(pin.art) {
            let scale: CGFloat = full ? 1 : 1.45
            model.node.simdScale *= SIMD3(repeating: Float(scale))
            icon.addChildNode(model.node)
            icon.position.y = full ? 0.13 : 0.15
            labelHeight = model.height * scale + 0.39
        } else {
        let art = MapSceneController.render(DeviceArtView(kind: pin.art, active: true, accent: Color(red: 0.86, green: 0.78, blue: 0.66), size: 72 * relativeSize).padding(10 * relativeSize))
        let iconPlane = SCNPlane(width: illustrationSize, height: illustrationSize)
        let im = SCNMaterial()
        im.lightingModel = .constant
        im.diffuse.contents = art
        im.isDoubleSided = true
        im.blendMode = .alpha
        im.transparencyMode = .aOne
        im.writesToDepthBuffer = false
        iconPlane.materials = [im]
        icon.geometry = iconPlane
        icon.position = SCNVector3(0, Float(illustrationSize / 2 + (full ? 0.13 : 0.15)), 0)
        icon.constraints = [SCNBillboardConstraint()]
        icon.renderingOrder = 20
        // An alpha illustration has no solid rectangle in the house. Allowing
        // its quad to cast shadows creates the cutout seen in the recording.
        icon.castsShadow = false
        labelHeight = illustrationSize + 0.33
        }
        addChildNode(icon)

        let stick = SCNCylinder(radius: 0.006, height: 1)
        let sm = SCNMaterial()
        sm.lightingModel = .constant
        sm.diffuse.contents = NSColor(white: 1, alpha: 0.18)
        stick.materials = [sm]
        stem.geometry = stick
        stem.castsShadow = false
        addChildNode(stem)

        if full {
            label.constraints = [SCNBillboardConstraint()]
            label.castsShadow = false
            label.renderingOrder = 30
            addChildNode(label)

            let torus = SCNTorus(ringRadius: 0.16, pipeRadius: 0.012)
            let rm = SCNMaterial()
            rm.lightingModel = .constant
            rm.diffuse.contents = NSColor.white
            torus.materials = [rm]
            ring.geometry = torus
            ring.castsShadow = false
            ring.isHidden = true
            addChildNode(ring)
        }
        update(pin: pin, at: pin.position, watts: nil, role: .none, floorY: 0)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// `at` is where the pin is drawn, which differs from where it is when the floors are spread out.
    func update(pin: MapPin, at drawn: SIMD3<Float>, watts: Double?, role: PinRole, floorY: Float) {
        position = SCNVector3(drawn.x, drawn.y, drawn.z)
        let glow = MapPower.glow(watts)
        // Sources glow green; loads warm from white to amber as they use more.
        tint = role == .source ? NSColor(Theme.ok)
            : watts == nil ? NSColor(white: 0.75, alpha: 1)
            : NSColor(calibratedRed: 1.0, green: 0.92 - 0.3 * glow, blue: 0.78 - 0.5 * glow, alpha: 1)
        let cm = SCNMaterial()
        cm.lightingModel = .constant
        cm.diffuse.contents = tint
        cm.emission.contents = tint
        core.geometry?.materials = [cm]

        let haloStrength = role == .source ? 0.7 : glow
        halo.isHidden = haloStrength <= 0
        halo.scale = SCNVector3(0.55 + 1.1 * haloStrength, 0.55 + 1.1 * haloStrength, 1)
        halo.geometry?.firstMaterial?.multiply.contents = tint
        halo.opacity = CGFloat(0.35 + 0.55 * haloStrength)

        let height = max(0, drawn.y - floorY)
        stem.isHidden = height < 0.15
        (stem.geometry as? SCNCylinder)?.height = CGFloat(height)
        stem.position = SCNVector3(0, -height / 2, 0)

        if full {
            let text = labelFor(pin: pin, watts: watts, role: role)
            if text != labelText {
                labelText = text
                let image = MapSceneController.render(
                    Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(.black.opacity(0.62)))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.75))
                )
                let plane = SCNPlane(width: CGFloat(image.size.width) / 100, height: CGFloat(image.size.height) / 100)
                let m = SCNMaterial()
                m.lightingModel = .constant
                m.diffuse.contents = image
                m.readsFromDepthBuffer = false
                m.writesToDepthBuffer = false
                plane.materials = [m]
                label.geometry = plane
                label.position = SCNVector3(0, Float(labelHeight), 0)
            }
        }
    }

    func setSelected(_ on: Bool) {
        ring.isHidden = !on
        ring.removeAllActions()
        if on {
            ring.runAction(.repeatForever(.sequence([.scale(to: 1.25, duration: 0.6), .scale(to: 1.0, duration: 0.6)])))
        }
    }

    private func labelFor(pin: MapPin, watts: Double?, role: PinRole) -> String {
        if role == .source { return "\(pin.name) · supplying" }
        guard let w = watts else { return pin.name }
        return "\(pin.name) · \(EnergyUnits.power(w))"
    }

    /// A soft round glow, white so it can be tinted.
    static let haloImage: NSImage = {
        let size = NSSize(width: 128, height: 128)
        return NSImage(size: size, flipped: false) { rect in
            let gradient = NSGradient(colors: [NSColor(white: 1, alpha: 0.9), NSColor(white: 1, alpha: 0.25), NSColor(white: 1, alpha: 0)],
                                      atLocations: [0, 0.35, 1], colorSpace: .deviceRGB)
            gradient?.draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: .zero)
            return true
        }
    }()
}

// MARK: Flow

/// Energy travelling from the source to one device along a path: a faint channel, and bright
/// motes moving down it, more and faster the more power the device draws.
@MainActor
final class FlowNode: SCNNode {
    init(points: [SIMD3<Float>], strength: Double, full: Bool, dark: Bool = true) {
        super.init()
        let amber = dark ? NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.42, alpha: 1)
            : NSColor(calibratedRed: 0.86, green: 0.46, blue: 0.04, alpha: 1)
        let blend: SCNBlendMode = dark ? .add : .alpha
        let channel = SCNMaterial()
        channel.lightingModel = .constant
        channel.diffuse.contents = amber.withAlphaComponent(0.3 + 0.3 * strength)
        channel.blendMode = blend
        channel.writesToDepthBuffer = false
        let thickness = CGFloat(0.012 + 0.022 * strength)
        var length: Float = 0
        for i in 1..<points.count {
            let a = points[i - 1], b = points[i]
            let d = simd_distance(a, b)
            length += d
            let tube = SCNCylinder(radius: thickness, height: CGFloat(d))
            tube.radialSegmentCount = 8
            tube.materials = [channel]
            let node = SCNNode(geometry: tube)
            node.position = SCNVector3((a + b) / 2)
            node.look(at: SCNVector3(b), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 1, 0))
            node.renderingOrder = 8
            addChildNode(node)
        }

        // The motes.
        let speed = Float(0.55 + 1.6 * strength)
        let count = full ? 3 + Int((strength * 6).rounded()) : 2 + Int((strength * 3).rounded())
        let loop = Double(length / speed)
        let mote = SCNSphere(radius: CGFloat(0.034 + 0.034 * strength))
        mote.segmentCount = 12
        let mm = SCNMaterial()
        mm.lightingModel = .constant
        mm.diffuse.contents = amber
        mm.emission.contents = amber
        mm.blendMode = blend
        mote.materials = [mm]
        var moves: [SCNAction] = [.move(to: SCNVector3(points[0]), duration: 0)]
        for i in 1..<points.count {
            moves.append(.move(to: SCNVector3(points[i]), duration: Double(simd_distance(points[i - 1], points[i]) / speed)))
        }
        let path = SCNAction.repeatForever(.sequence(moves))
        for i in 0..<count {
            let m = SCNNode(geometry: mote)
            m.position = SCNVector3(points[0])
            m.renderingOrder = 9
            m.opacity = 0
            addChildNode(m)
            m.runAction(.sequence([.wait(duration: loop * Double(i) / Double(count)), .fadeIn(duration: 0.2), path]))
        }
    }

    required init?(coder: NSCoder) { fatalError() }
}

private extension SCNVector3 {
    init(_ v: SIMD3<Float>) { self.init(CGFloat(v.x), CGFloat(v.y), CGFloat(v.z)) }
}

// MARK: View

/// The SceneKit view. Scroll or pinch zooms toward the pointer, a drag moves the house (open hand,
/// closed while dragging), a right-drag or Option-drag turns it, a two-finger twist spins it,
/// a double-click fits it, a click picks a pin, and dropping a device pins it.
final class HearthMapView: SCNView {
    var onClick: ((CGPoint) -> Void)?
    var onDrop: ((String, CGPoint) -> Bool)?
    weak var controller: MapSceneController?

    private enum Drag { case pan(SIMD3<Float>), orbit }
    private var drag: Drag?
    private var pushedDragCursor = false
    private var downAt: CGPoint?
    private var moved = false
    private var settleWork: DispatchWorkItem?
    private var tracking: NSTrackingArea?

    override init(frame: NSRect, options: [String: Any]? = nil) {
        super.init(frame: frame, options: options)
        registerForDraggedTypes([.string])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func location(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    /// Springs back inside the limits a moment after the last scroll, pinch or drag.
    private func scheduleSettle() {
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.controller?.settle() }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    // MARK: Pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func cursorUpdate(with event: NSEvent) { updateCursor(event) }
    override func mouseMoved(with event: NSEvent) { updateCursor(event) }
    override func mouseEntered(with event: NSEvent) { updateCursor(event) }
    override func mouseExited(with event: NSEvent) {
        if drag == nil { NSCursor.arrow.set() }
    }

    /// SwiftUI's toolbar and inspector overlap the SceneKit view. A tracking area
    /// over the whole viewport must not give those controls the map's grab cursor.
    private func isCanvas(at event: NSEvent) -> Bool {
        guard let root = window?.contentView,
              let hit = root.hitTest(root.convert(event.locationInWindow, from: nil)) else { return false }
        return hit === self || hit.isDescendant(of: self)
    }

    /// A grab cursor on the house; the arrow over controls and empty space.
    private func updateCursor(_ event: NSEvent) {
        guard drag == nil else { return }
        let p = location(event)
        if isCanvas(at: event), let controller,
           controller.surfacePoint(at: p, in: self) != nil || controller.pinID(at: p, in: self) != nil {
            NSCursor.openHand.set()
        } else { NSCursor.arrow.set() }
    }

    // MARK: Zoom and turn

    override func scrollWheel(with event: NSEvent) {
        // No gliding on after the fingers lift: the map stops where you stop.
        guard event.momentumPhase.isEmpty else { return }
        let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 10
        guard dy != 0 else { return }
        controller?.zoom(by: Float(exp(-Double(dy) * 0.008)), at: location(event), in: self)
        scheduleSettle()
    }

    override func magnify(with event: NSEvent) {
        controller?.zoom(by: Float(1 / max(0.2, 1 + event.magnification)), at: location(event), in: self)
        scheduleSettle()
    }

    override func rotate(with event: NSEvent) {
        controller?.orbit(yaw: Float(event.rotation) * .pi / 180, pitch: 0)
    }

    // MARK: Drag to move, right-drag to turn

    override func mouseDown(with event: NSEvent) {
        let p = location(event)
        downAt = p
        moved = false
        if event.modifierFlags.contains(.option) || controller?.maps.dragMode == .turn {
            drag = .orbit
            NSCursor.closedHand.push()
            pushedDragCursor = true
        } else if let g = controller?.grab(at: p, in: self) {
            drag = .pan(g)
            NSCursor.closedHand.push()
            pushedDragCursor = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = location(event)
        if !moved, let d = downAt, hypot(p.x - d.x, p.y - d.y) > 3 { moved = true }
        guard moved else { return }
        switch drag {
        case .pan(let grabbed): controller?.pan(grabbed: grabbed, to: p, in: self)
        case .orbit: controller?.orbit(yaw: -Float(event.deltaX) * 0.008, pitch: Float(event.deltaY) * 0.006)
        case nil: break
        }
    }

    override func mouseUp(with event: NSEvent) {
        if pushedDragCursor { NSCursor.pop(); pushedDragCursor = false }
        drag = nil
        let p = location(event)
        if event.clickCount == 2 {
            controller?.fit(animated: true)
        } else if !moved {
            onClick?(p)
        } else {
            scheduleSettle()
        }
        downAt = nil
        updateCursor(event)
    }

    override func rightMouseDown(with event: NSEvent) { drag = .orbit }

    override func rightMouseDragged(with event: NSEvent) {
        controller?.orbit(yaw: -Float(event.deltaX) * 0.008, pitch: Float(event.deltaY) * 0.006)
    }

    override func rightMouseUp(with event: NSEvent) {
        drag = nil
        updateCursor(event)
    }

    /// A right-drag turns the house, so no menu.
    override func menu(for event: NSEvent) -> NSMenu? { nil }

    // MARK: Dropping a device

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.string(forType: .string)?.hasPrefix(MapDrag.prefix) == true ? .move : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let text = sender.draggingPasteboard.string(forType: .string), text.hasPrefix(MapDrag.prefix) else { return false }
        return onDrop?(String(text.dropFirst(MapDrag.prefix.count)), convert(sender.draggingLocation, from: nil)) ?? false
    }
}

/// What a device carries while it's dragged onto the map.
enum MapDrag {
    static let prefix = "hearth-map-pin:"
}

struct MapSceneView: NSViewRepresentable {
    @ObservedObject var controller: MapSceneController
    var onPin: ((String?) -> Void)? = nil
    var onDrop: ((String, SIMD3<Float>, Int) -> Void)? = nil

    func makeNSView(context: Context) -> HearthMapView {
        let view = HearthMapView(frame: .zero, options: nil)
        view.scene = controller.scene
        view.backgroundColor = view.effectiveAppearance.isDark
            ? NSColor(calibratedRed: 0.027, green: 0.027, blue: 0.034, alpha: 1) : NSColor(calibratedWhite: 0.957, alpha: 1)
        controller.setAppearance(dark: view.effectiveAppearance.isDark)
        // Hearth drives the camera itself: SceneKit's own control pans on scroll.
        view.allowsCameraControl = false
        view.antialiasingMode = controller.full ? .multisampling4X : .multisampling2X
        view.preferredFramesPerSecond = controller.full ? 60 : 30
        view.rendersContinuously = false
        view.pointOfView = controller.scene.rootNode.childNode(withName: "camera", recursively: false)
        view.controller = controller
        controller.view = view
        controller.syncCamera()
        if let script = UserDefaults.standard.string(forKey: "mapCam"), controller.full == UserDefaults.standard.bool(forKey: "mapCamFull") {
            controller.runScript(script, in: view)
        }
        return view
    }

    func updateNSView(_ view: HearthMapView, context: Context) {
        let dark = context.environment.colorScheme == .dark
        if dark != controller.dark {
            controller.setAppearance(dark: dark)
            view.backgroundColor = dark ? NSColor(calibratedRed: 0.027, green: 0.027, blue: 0.034, alpha: 1)
                : NSColor(calibratedWhite: 0.957, alpha: 1)
        }
        view.isPlaying = controller.active
        view.controller = controller
        view.onClick = { [weak view] p in
            guard let view else { return }
            onPin?(controller.pinID(at: p, in: view))
        }
        view.onDrop = { [weak view] id, p in
            guard let view, let (point, level) = controller.surfacePoint(at: p, in: view) else { return false }
            onDrop?(id, point, level)
            return true
        }
        controller.syncCamera()
    }
}
