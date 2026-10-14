import AppKit
import SceneKit

/// Small, authored hardware models for the house. These have actual thickness,
/// rounded silhouettes and lit materials; camera movement never rotates a flat
/// illustration toward the viewer. All dimensions are illustrative scene units.
@MainActor
enum MapDeviceModel {
    struct Model { let node: SCNNode; let height: CGFloat }

    static func supports(_ kind: DeviceKind) -> Bool {
        switch kind {
        case .smartSpeaker, .meshSpeaker, .speakerGroup, .fridge, .airConditioner, .tv,
             .computer, .streamingBox, .router, .securityHub, .securityHubPro, .battery,
             .inverter, .indoorCamera, .outdoorCamera, .doorbell: true
        default: false
        }
    }

    static func make(_ kind: DeviceKind) -> Model? {
        let root = SCNNode()
        let shell = material(NSColor(white: 0.88, alpha: 1), roughness: 0.48)
        let enamel = material(NSColor(white: 0.96, alpha: 1), roughness: 0.3)
        let charcoal = material(NSColor(white: 0.045, alpha: 1), roughness: 0.65)
        let glass = material(NSColor(white: 0.022, alpha: 1), roughness: 0.16)
        let metal = material(NSColor(white: 0.58, alpha: 1), roughness: 0.32, metalness: 0.65)
        let light = material(NSColor(calibratedRed: 0.63, green: 0.83, blue: 0.91, alpha: 1), roughness: 0.35)
        light.emission.contents = NSColor(calibratedRed: 0.1, green: 0.25, blue: 0.3, alpha: 1)
        let fabric = material(NSColor(white: 0.7, alpha: 1), roughness: 0.95)
        fabric.diffuse.contents = weave
        var height: CGFloat = 0.6

        func box(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat, _ m: SCNMaterial,
                 at p: SCNVector3, radius: CGFloat = 0.025, parent: SCNNode? = nil) -> SCNNode {
            let geometry = SCNBox(width: w, height: h, length: d, chamferRadius: min(radius, min(w, h, d) / 2))
            geometry.chamferSegmentCount = 4
            geometry.materials = [m]
            let node = SCNNode(geometry: geometry); node.position = p
            (parent ?? root).addChildNode(node)
            return node
        }
        func cylinder(_ radius: CGFloat, _ h: CGFloat, _ m: SCNMaterial, at p: SCNVector3, parent: SCNNode? = nil) -> SCNNode {
            let geometry = SCNCylinder(radius: radius, height: h)
            geometry.radialSegmentCount = 40
            geometry.materials = [m]
            let node = SCNNode(geometry: geometry); node.position = p
            (parent ?? root).addChildNode(node)
            return node
        }
        func sphere(_ r: CGFloat, _ m: SCNMaterial, at p: SCNVector3, parent: SCNNode? = nil) -> SCNNode {
            let geometry = SCNSphere(radius: r); geometry.segmentCount = 40; geometry.materials = [m]
            let node = SCNNode(geometry: geometry); node.position = p
            (parent ?? root).addChildNode(node)
            return node
        }
        func speaker(at p: SCNVector3, scale: Float = 1, mesh: Bool = false) {
            let group = SCNNode(); group.position = p; group.scale = SCNVector3(scale, scale, scale); root.addChildNode(group)
            let body = sphere(0.25, fabric, at: SCNVector3(0, 0.255, 0), parent: group)
            body.scale = SCNVector3(1, mesh ? 0.92 : 1, 1)
            _ = cylinder(0.175, 0.035, charcoal, at: SCNVector3(0, 0.025, 0), parent: group)
            let ring = SCNTorus(ringRadius: 0.177, pipeRadius: 0.008)
            ring.ringSegmentCount = 48; ring.pipeSegmentCount = 8; ring.materials = [light]
            let glow = SCNNode(geometry: ring); glow.position = SCNVector3(0, 0.045, 0); group.addChildNode(glow)
            if mesh {
                _ = cylinder(0.11, 0.009, glass, at: SCNVector3(0, 0.482, 0), parent: group)
                for x: Float in [-0.03, 0.03] {
                    _ = box(0.016, 0.003, 0.003, shell, at: SCNVector3(x, 0.489, 0), radius: 0.001, parent: group)
                }
            } else {
                // Echo-style fabric sphere: four small physical controls,
                // rather than a HomePod-like glass touch panel.
                for p in [SCNVector3(-0.035, 0.501, 0), SCNVector3(0.035, 0.501, 0),
                          SCNVector3(0, 0.501, -0.035), SCNVector3(0, 0.501, 0.035)] {
                    let control = sphere(0.009, charcoal, at: p, parent: group)
                    control.scale.y = 0.3
                }
            }
        }

        switch kind {
        case .smartSpeaker, .meshSpeaker:
            height = 0.52; speaker(at: SCNVector3Zero, mesh: kind == .meshSpeaker)
            if kind == .smartSpeaker {
                root.scale = SCNVector3(0.7, 0.7, 0.7)
                height *= 0.7
            }
        case .speakerGroup:
            height = 0.52
            speaker(at: SCNVector3(-0.24, 0, 0.08), scale: 0.8)
            speaker(at: SCNVector3(0.24, 0, 0.08), scale: 0.8)
            speaker(at: SCNVector3(0, 0, -0.15))
            root.scale = SCNVector3(0.7, 0.7, 0.7)
            height *= 0.7
        case .fridge:
            height = 1.35
            _ = box(0.65, 1.3, 0.55, shell, at: SCNVector3(0, 0.68, 0), radius: 0.045)
            _ = box(0.618, 0.43, 0.038, enamel, at: SCNVector3(0, 1.1, 0.287), radius: 0.016)
            _ = box(0.618, 0.8, 0.038, enamel, at: SCNVector3(0, 0.469, 0.287), radius: 0.016)
            _ = box(0.018, 0.23, 0.03, metal, at: SCNVector3(0.237, 1.05, 0.32), radius: 0.007)
            _ = box(0.018, 0.34, 0.03, metal, at: SCNVector3(0.237, 0.69, 0.32), radius: 0.007)
            _ = box(0.105, 0.08, 0.005, glass, at: SCNVector3(-0.135, 1.085, 0.311), radius: 0.008)
            _ = box(0.052, 0.008, 0.004, light, at: SCNVector3(-0.135, 1.09, 0.316), radius: 0.003)
            for x: Float in [-0.25, 0.25] { _ = cylinder(0.025, 0.06, charcoal, at: SCNVector3(x, 0.03, 0.18)) }
        case .airConditioner:
            height = 0.42
            _ = box(1.3, 0.38, 0.25, enamel, at: SCNVector3(0, 0.21, 0), radius: 0.055)
            _ = box(1.12, 0.07, 0.012, charcoal, at: SCNVector3(0, 0.096, 0.126), radius: 0.012)
            for y: Float in [0.079, 0.098, 0.117] {
                _ = box(1.07, 0.009, 0.018, shell, at: SCNVector3(0, y, 0.139), radius: 0.003)
            }
            _ = box(0.1, 0.06, 0.004, glass, at: SCNVector3(0.46, 0.23, 0.129), radius: 0.012)
            _ = box(0.042, 0.007, 0.003, light, at: SCNVector3(0.46, 0.23, 0.133), radius: 0.002)
        case .tv:
            height = 0.91
            _ = box(1.25, 0.75, 0.06, charcoal, at: SCNVector3(0, 0.535, 0), radius: 0.025)
            let screen = material(NSColor(calibratedRed: 0.06, green: 0.13, blue: 0.17, alpha: 1), roughness: 0.2)
            screen.diffuse.contents = screenGradient
            screen.emission.contents = screenGradient
            screen.emission.intensity = 0.22
            _ = box(1.18, 0.681, 0.008, screen, at: SCNVector3(0, 0.54, 0.034), radius: 0.013)
            _ = box(0.035, 0.17, 0.035, metal, at: SCNVector3(0, 0.11, 0))
            _ = box(0.42, 0.026, 0.24, metal, at: SCNVector3(0, 0.017, 0), radius: 0.01)
        case .computer, .streamingBox, .router:
            height = kind == .router ? 0.42 : 0.16
            _ = box(0.49, 0.12, 0.43, kind == .streamingBox ? charcoal : metal, at: SCNVector3(0, 0.085, 0), radius: 0.035)
            _ = box(0.04, 0.012, 0.005, glass, at: SCNVector3(-0.12, 0.079, 0.218), radius: 0.004)
            _ = sphere(0.005, light, at: SCNVector3(0.15, 0.079, 0.222))
            if kind == .router {
                for x: Float in [-0.19, 0.19] {
                    _ = cylinder(0.01, 0.28, shell, at: SCNVector3(x, 0.28, -0.16))
                }
            }
        case .securityHub, .securityHubPro, .battery, .inverter:
            let tall = kind == .battery || kind == .inverter
            height = tall ? 0.88 : kind == .securityHubPro ? 0.6 : 0.48
            let w: CGFloat = tall ? 0.58 : 0.4
            let d: CGFloat = tall ? 0.29 : 0.35
            _ = box(w, height - 0.04, d, shell, at: SCNVector3(0, Float(height / 2), 0), radius: 0.045)
            _ = box(w * 0.62, tall ? 0.16 : 0.04, 0.008, glass, at: SCNVector3(0, Float(height * 0.72), Float(d / 2 + 0.004)), radius: 0.012)
            for x: Float in [-0.04, 0, 0.04] {
                _ = sphere(0.005, light, at: SCNVector3(x, Float(height * 0.7), Float(d / 2 + 0.012)))
            }
            _ = box(w * 0.9, 0.035, d * 0.92, charcoal, at: SCNVector3(0, 0.023, 0), radius: 0.012)
        case .indoorCamera:
            height = 0.66
            _ = cylinder(0.18, 0.06, shell, at: SCNVector3(0, 0.033, 0))
            _ = cylinder(0.035, 0.12, metal, at: SCNVector3(0, 0.115, 0))
            let housing = sphere(0.23, enamel, at: SCNVector3(0, 0.407, 0))
            housing.scale = SCNVector3(1, 1, 1)
            let face = cylinder(0.128, 0.016, glass, at: SCNVector3(0, 0.42, 0.22))
            face.eulerAngles.x = .pi / 2
            let lens = sphere(0.048, glass, at: SCNVector3(0, 0.42, 0.239))
            lens.scale.z = 0.25
            _ = sphere(0.006, light, at: SCNVector3(0, 0.51, 0.217))
        case .outdoorCamera:
            // Same authored silhouette as DeviceArt.outdoorCamera: long round
            // shell, circular black face, solar top, and a short rear ball mount.
            // A three-quarter heading shows both lens and body at the default
            // house angle, instead of reading as a small white top-down box.
            height = 0.48
            root.eulerAngles.y = -.pi / 3
            _ = box(0.19, 0.032, 0.15, shell, at: SCNVector3(0, 0.018, -0.17), radius: 0.016)
            _ = cylinder(0.022, 0.14, shell, at: SCNVector3(0, 0.104, -0.17))
            _ = sphere(0.042, metal, at: SCNVector3(0, 0.187, -0.17))
            let head = SCNNode(); head.position = SCNVector3(0, 0.332, 0)
            head.eulerAngles.x = 0.12
            root.addChildNode(head)
            let housing = cylinder(0.13, 0.5, enamel, at: SCNVector3Zero, parent: head)
            housing.eulerAngles.x = .pi / 2
            let back = sphere(0.13, enamel, at: SCNVector3(0, 0, -0.25), parent: head)
            back.scale.z = 0.3
            func ring(_ radius: CGFloat, _ pipe: CGFloat, _ m: SCNMaterial, _ at: SCNVector3) {
                let geometry = SCNTorus(ringRadius: radius, pipeRadius: pipe)
                geometry.ringSegmentCount = 48; geometry.pipeSegmentCount = 12
                geometry.materials = [m]
                let node = SCNNode(geometry: geometry); node.position = at
                node.eulerAngles.x = .pi / 2; head.addChildNode(node)
            }
            ring(0.117, 0.013, enamel, SCNVector3(0, 0, 0.25))
            let face = cylinder(0.112, 0.012, glass, at: SCNVector3(0, 0, 0.253), parent: head)
            face.eulerAngles.x = .pi / 2
            let lensHousing = cylinder(0.065, 0.014, charcoal, at: SCNVector3(0, 0.026, 0.267), parent: head)
            lensHousing.eulerAngles.x = .pi / 2
            let optical = material(NSColor(calibratedRed: 0.055, green: 0.15, blue: 0.2, alpha: 1),
                                   roughness: 0.14, metalness: 0.25)
            ring(0.05, 0.006, metal, SCNVector3(0, 0.026, 0.277))
            let lens = sphere(0.047, optical, at: SCNVector3(0, 0.026, 0.279), parent: head)
            lens.scale.z = 0.16
            let pupil = sphere(0.025, glass, at: SCNVector3(0, 0.026, 0.287), parent: head)
            pupil.scale.z = 0.12
            let reflection = sphere(0.01, light, at: SCNVector3(-0.018, 0.045, 0.289), parent: head)
            reflection.scale = SCNVector3(1, 0.4, 0.12)
            for x: Float in [-0.043, 0.043] {
                _ = sphere(0.009, charcoal, at: SCNVector3(x, -0.055, 0.26), parent: head)
            }
            _ = sphere(0.004, light, at: SCNVector3(0, -0.083, 0.262), parent: head)
            let solar = material(NSColor(calibratedRed: 0.065, green: 0.09, blue: 0.14, alpha: 1), roughness: 0.4)
            solar.diffuse.contents = solarCells
            // Curve the panel around the shell, so its sides do not float above
            // a round housing or disappear through its highest point.
            var vertices: [SCNVector3] = []
            var normals: [SCNVector3] = []
            var uv: [CGPoint] = []
            var indices: [UInt16] = []
            for i in 0...16 {
                let fraction = Float(i) / 16
                let angle = -0.47 + fraction * 0.94
                for (j, z) in [Float(-0.18), 0.13].enumerated() {
                    vertices.append(SCNVector3(0.132 * sin(angle), 0.132 * cos(angle), z))
                    normals.append(SCNVector3(sin(angle), cos(angle), 0))
                    uv.append(CGPoint(x: CGFloat(fraction), y: CGFloat(j)))
                }
                if i < 16 {
                    let n = UInt16(i * 2)
                    indices += [n, n + 1, n + 2, n + 1, n + 3, n + 2]
                }
            }
            let panel = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals),
                                              SCNGeometrySource(textureCoordinates: uv)],
                                    elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
            panel.materials = [solar]
            head.addChildNode(SCNNode(geometry: panel))
        case .doorbell:
            height = 0.61
            _ = box(0.21, 0.6, 0.08, shell, at: SCNVector3(0, 0.31, 0), radius: 0.037)
            _ = box(0.19, 0.3, 0.01, glass, at: SCNVector3(0, 0.45, 0.044), radius: 0.029)
            let button = cylinder(0.054, 0.012, metal, at: SCNVector3(0, 0.19, 0.049))
            button.eulerAngles.x = .pi / 2
            let lens = sphere(0.047, glass, at: SCNVector3(0, 0.46, 0.06)); lens.scale.z = 0.3
        default: return nil
        }
        root.name = "device-model"
        return Model(node: root, height: height)
    }

    private static func material(_ color: NSColor, roughness: CGFloat, metalness: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.roughness.contents = roughness
        m.metalness.contents = metalness
        return m
    }

    private static let weave: NSImage = NSImage(size: NSSize(width: 256, height: 256), flipped: false) { rect in
        NSColor(white: 0.67, alpha: 1).setFill(); rect.fill()
        for y in stride(from: 0, to: 256, by: 4) {
            for x in stride(from: 0, to: 256, by: 4) {
                NSColor(white: (x + y) % 8 == 0 ? 0.79 : 0.53, alpha: 1).setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 3, height: 2), xRadius: 1, yRadius: 1).fill()
            }
        }
        return true
    }

    private static let solarCells: NSImage = NSImage(size: NSSize(width: 128, height: 256), flipped: false) { rect in
        NSColor(calibratedRed: 0.04, green: 0.065, blue: 0.12, alpha: 1).setFill(); rect.fill()
        NSColor(calibratedRed: 0.25, green: 0.32, blue: 0.44, alpha: 1).setStroke()
        let grid = NSBezierPath(); grid.lineWidth = 0.75
        for y in stride(from: 0, through: 256, by: 40) {
            grid.move(to: NSPoint(x: 0, y: y)); grid.line(to: NSPoint(x: 128, y: y))
        }
        grid.move(to: NSPoint(x: 64, y: 0)); grid.line(to: NSPoint(x: 64, y: 256)); grid.stroke()
        return true
    }

    private static let screenGradient: NSImage = NSImage(size: NSSize(width: 128, height: 96), flipped: false) { rect in
        NSGradient(colors: [NSColor(calibratedRed: 0.035, green: 0.07, blue: 0.1, alpha: 1),
                            NSColor(calibratedRed: 0.17, green: 0.32, blue: 0.39, alpha: 1)])?.draw(in: rect, angle: 35)
        return true
    }
}
