import AppKit
import SwiftUI

/// The kinds of hardware Hearth knows how to picture. Each is a generic product
/// archetype, never a particular brand's design.
enum DeviceKind: String, CaseIterable {
    case smartSpeaker, speakerGroup
    case meshSpeaker  // squat mesh sphere with a glowing glass top
    case streamingBox  // TV box with its remote
    case indoorCamera  // pan-tilt dome on a base
    case outdoorCamera  // wire-free bullet camera
    case doorbell  // video doorbell
    case securityHub  // home base station
    case securityHubPro  // larger, rectangular base station
    case printer3D  // enclosed 3D printer
    case gameConsole  // upright games console with its controller
    case computer  // small square desktop computer
    case electricCar, evCharger, robotVacuum, lawnMower, aircraft, robot  // drawn in VehicleArt.swift
    case inverter, battery, solarPanel  // home energy, drawn in EnergyArt
    case airConditioner, fridge, tv, router, phone, generic

    var title: String {
        switch self {
        case .smartSpeaker: "Smart speaker"
        case .meshSpeaker: "Mini speaker"
        case .streamingBox: "Streaming box"
        case .speakerGroup: "Speaker group"
        case .indoorCamera: "Indoor camera"
        case .outdoorCamera: "Outdoor camera"
        case .doorbell: "Doorbell"
        case .securityHub: "Security hub"
        case .securityHubPro: "Security hub Pro"
        case .printer3D: "3D printer"
        case .gameConsole: "Games console"
        case .computer: "Computer"
        case .electricCar, .evCharger, .robotVacuum, .lawnMower, .aircraft, .robot: vehicleTitle
        case .inverter: "Inverter"
        case .battery: "Battery"
        case .solarPanel: "Solar panel"
        case .airConditioner: "Air conditioner"
        case .fridge: "Fridge"
        case .tv: "TV"
        case .router: "Router"
        case .phone: "Phone"
        case .generic: "Device"
        }
    }
}

extension DeviceKind {
    /// Picks the picture for a Home Assistant device from what it says about itself,
    /// falling back on the kinds of entity it has.
    static func classify(manufacturer: String?, model: String?, name: String, domains: Set<String>) -> DeviceKind {
        let maker = (manufacturer ?? "").lowercased()
        let m = (model ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        let n = name.lowercased()
        let text = m + " " + n
        func says(_ words: String...) -> Bool { words.contains { text.contains($0) } }

        if let vehicle = vehicle(maker: maker, model: m, name: n, domains: domains) { return vehicle }
        if says("speaker group", "everywhere") { return .speakerGroup }
        if says("doorbell", "door bell") { return .doorbell }

        // Eufy model numbers: T84xx indoor, T82xx doorbells, T80xx and T90xx base stations,
        // T81xx and the rest of the T8 range outdoor cameras.
        if maker.contains("eufy") || m.range(of: #"^t[89]\d{3}"#, options: .regularExpression) != nil {
            if m.hasPrefix("t84") { return .indoorCamera }
            if m.hasPrefix("t82") { return .doorbell }
            if m.hasPrefix("t90") || (says("homebase", "home base") && says("pro")) { return .securityHubPro }
            if m.hasPrefix("t80") || says("homebase", "home base") { return .securityHub }
            if m.hasPrefix("t8") { return .outdoorCamera }
        }
        if says("homebase", "home base", "base station") { return says("pro") ? .securityHubPro : .securityHub }

        if !domains.contains("climate"), let energy = energyKind(maker: maker, text: text) { return energy }

        // Gadgets: 3D printers, games consoles and computers.
        if maker.contains("bambu") || says("3d printer", "bambu")
            || (says("printer") && (says("3d", "prusa", "creality", "voron") || maker.contains("prusa") || maker.contains("creality"))) {
            return .printer3D
        }
        if maker.contains("sony interactive") || says("playstation", "ps5", "ps4", "xbox", "nintendo switch") { return .gameConsole }
        // Apple reports Macs as "Macmini9,1", "MacBookPro18,3", "Mac16,10", "iMac21,1".
        if (maker.contains("apple") && (m.hasPrefix("mac") || m.hasPrefix("imac")))
            || says("mac mini", "macbook", "imac", "mac studio", "mac pro", "desktop", "laptop", "gaming pc") || n.hasSuffix(" pc") {
            return .computer
        }

        if domains.contains("climate") || says("air conditioner", "aircon", "heat pump") { return .airConditioner }
        if says("fridge", "refrigerator", "freezer") { return .fridge }
        // Apple reports model identifiers such as "AppleTV11,1" and "AudioAccessory5,1".
        if says("homepod", "audioaccessory") { return .meshSpeaker }
        if says("apple tv", "appletv", "streaming", "chromecast", "fire tv", "roku", "shield tv") { return .streamingBox }
        if says("echo", "smart speaker", "nest mini") { return .smartSpeaker }
        if says(" tv", "television", "tv ") || n == "tv" { return .tv }
        if says("router", "mesh", "access point", "wi-fi", "wifi", "gateway") { return .router }
        if says("phone") || isPhoneNumber(name) || (model == nil && domains == ["button"]) { return .phone }
        if domains.contains("camera") { return says("indoor") ? .indoorCamera : .outdoorCamera }
        if domains.contains("media_player") { return .smartSpeaker }
        if domains.contains("alarm_control_panel") { return .securityHub }
        return .generic
    }

    /// "+254 712 345678", "(555) 010-0199" and the like.
    private static func isPhoneNumber(_ s: String) -> Bool {
        let digits = s.filter(\.isNumber).count
        let others = s.filter { !$0.isNumber && !" +-().".contains($0) }.count
        return digits >= 7 && others == 0
    }
}

/// A device, rendered in layers of light like `ACUnitView`: soft shadows, satin and glass
/// materials with real highlights, and indicator lights that glow when it is on.
/// Lights that breathe (speaker rings, the doorbell button) run on a separate, cheap
/// overlay, so the body is drawn once and only the glow is redrawn.
struct DeviceArtView: View {
    var kind: DeviceKind
    var active: Bool = true
    var accent: Color = Theme.air("cool")
    var size: CGFloat = 64

    var body: some View {
        let art = DeviceArt(kind: kind, size: size, on: active, accent: accent)
        ZStack {
            Canvas { ctx, _ in art.draw(&ctx) }
            if active && art.breathes {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: !active)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let breath = 0.5 - 0.5 * cos(t * 2 * .pi / 4.2)
                    Canvas { ctx, _ in art.drawBreath(&ctx, amount: breath) }
                }
            }
        }
        .frame(width: size, height: size)
        .saturation(active ? 1 : 0.12)
        .brightness(active ? 0 : -0.04)
        .accessibilityElement()
        .accessibilityLabel("\(kind.title), \(active ? "on" : "off")")
    }
}

/// The art at list-row size, sitting on a soft circular plate of its own light.
struct DeviceBadge: View {
    var kind: DeviceKind
    var active: Bool = true
    var accent: Color = Theme.air("cool")
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [accent.opacity(active ? 0.2 : 0.05), Color.white.opacity(0.025)],
                                     center: .center, startRadius: 0, endRadius: size * 0.55))
            Circle()
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.03)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 0.75)
            DeviceArtView(kind: kind, active: active, accent: accent, size: size * 0.9)
        }
        .frame(width: size, height: size)
    }
}

// MARK: Drawing

/// All geometry is laid out on a 100 by 100 grid and scaled to the view.
private struct DeviceArt {
    let kind: DeviceKind
    let size: CGFloat
    let on: Bool
    let accent: Color

    var breathes: Bool { [.smartSpeaker, .speakerGroup, .meshSpeaker, .doorbell].contains(kind) }

    private var k: CGFloat { size / 100 }
    /// The accent with enough colour in it to read as a light, not a tint.
    private var glow: Color { accent.vivid() }

    private func u(_ v: CGFloat) -> CGFloat { v * k }
    private func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * k, y: y * k) }
    private func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: x * k, y: y * k, width: w * k, height: h * k)
    }
    private func disc(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path { Path(ellipseIn: R(x - r, y - r, r * 2, r * 2)) }
    private func oval(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        Path(ellipseIn: R(x - rx, y - ry, rx * 2, ry * 2))
    }

    func draw(_ ctx: inout GraphicsContext) {
        switch kind {
        case .smartSpeaker: speaker(ctx, 50, 47, 33)
        case .meshSpeaker: meshSpeaker(ctx)
        case .streamingBox: streamingBox(ctx)
        case .speakerGroup:
            var back = ctx
            back.addFilter(.colorMultiply(Color(white: 0.72)))
            speaker(back, 64, 38, 23)
            speaker(ctx, 39, 54, 27)
        case .indoorCamera: indoorCamera(ctx)
        case .outdoorCamera: outdoorCamera(ctx)
        case .doorbell: doorbell(ctx)
        case .securityHub: securityHub(ctx)
        case .securityHubPro: securityHubPro(ctx)
        case .printer3D: printer3D(ctx)
        case .gameConsole: gameConsole(ctx)
        case .computer: computer(ctx)
        case .electricCar, .evCharger, .robotVacuum, .lawnMower, .aircraft, .robot:
            VehicleArt(kind: kind, size: size, on: on, accent: accent).draw(ctx)
        case .inverter, .battery, .solarPanel: EnergyArt(kind: kind, size: size, on: on, accent: accent).draw(ctx)
        case .airConditioner: airConditioner(ctx)
        case .fridge: fridge(ctx)
        case .tv: tv(ctx)
        case .router: router(ctx)
        case .phone: phone(ctx)
        case .generic: generic(ctx)
        }
    }

    /// The breathing part of the lights, added on top of the static drawing.
    func drawBreath(_ ctx: inout GraphicsContext, amount: Double) {
        switch kind {
        case .smartSpeaker: speakerBreath(ctx, 50, 47, 33, amount)
        case .meshSpeaker: meshBreath(ctx, amount)
        case .speakerGroup:
            // The far speaker's light passes behind the near one.
            var behind = ctx
            behind.clip(to: speakerPaths(SpeakerShape(cx: 39, cy: 54, r: 27)).body, options: .inverse)
            speakerBreath(behind, 64, 38, 23, amount * 0.6)
            speakerBreath(ctx, 39, 54, 27, amount)
        case .doorbell: doorbellBreath(ctx, amount)
        default: break
        }
    }

    // MARK: Materials

    /// A soft cast shadow under something standing on a surface.
    private func ground(_ ctx: GraphicsContext, _ cx: CGFloat, _ y: CGFloat, w: CGFloat, h: CGFloat, opacity: Double = 0.85) {
        ctx.layer(blur: u(h * 0.55)) { $0.fill(oval(cx, y, w / 2, h / 2), with: .color(.black.opacity(opacity))) }
        ctx.layer(blur: u(max(h * 0.14, 0.6))) {
            $0.fill(oval(cx, y - h * 0.08, w * 0.36, h * 0.16), with: .color(.black.opacity(opacity)))
        }
    }

    /// Satin plastic lit from above, its ends turning away from the light, with a broad
    /// soft reflection along the top.
    private func satin(_ ctx: GraphicsContext, _ shape: Path, _ r: CGRect, light: Double = 1, dark: Double = 0.72,
                       turn: CGFloat = 0.14, gloss: Double = 0.85) {
        ctx.fill(shape, with: vertical(r, [(Color(white: light), 0), (Color(white: light - 0.035), 0.4),
                                          (Color(white: dark + (light - dark) * 0.45), 0.78), (Color(white: dark), 1)]))
        var inside = ctx
        inside.clip(to: shape)
        inside.fill(Path(r), with: horizontal(r, [(.black.opacity(0.16), 0), (.clear, turn), (.clear, 1 - turn),
                                                  (.black.opacity(0.2), 1)]))
        if gloss > 0 {
            inside.layer(blur: min(r.width, r.height) * 0.12) {
                $0.fill(Path(ellipseIn: CGRect(x: r.minX + r.width * 0.13, y: r.minY - r.height * 0.06,
                                               width: r.width * 0.74, height: r.height * 0.36)),
                        with: .color(.white.opacity(gloss)))
            }
        }
    }

    /// A fine highlight along the upper edge of a shape, drawn just inside it.
    private func rim(_ ctx: GraphicsContext, _ shape: Path, _ r: CGRect, _ strength: Double = 0.9, reach: CGFloat = 0.35) {
        var c = ctx
        c.clip(to: shape)
        c.stroke(shape, with: vertical(r, [(.white.opacity(strength), 0), (.white.opacity(0), reach)]), lineWidth: u(1.3))
    }

    /// Black gloss: a deep gradient with a soft reflection up top and a hairline edge.
    private func blackGlass(_ ctx: GraphicsContext, _ shape: Path, _ r: CGRect, sheen: Double = 0.2) {
        ctx.fill(shape, with: vertical(r, [(Color(white: 0.16), 0), (Color(white: 0.05), 0.42),
                                          (Color(white: 0.025), 0.8), (Color(white: 0.08), 1)]))
        var inside = ctx
        inside.clip(to: shape)
        inside.layer(blur: min(r.width, r.height) * 0.08) {
            $0.fill(Path(ellipseIn: CGRect(x: r.minX + r.width * 0.12, y: r.minY - r.height * 0.18,
                                           width: r.width * 0.76, height: r.height * 0.5)),
                    with: .color(.white.opacity(sheen)))
        }
        inside.stroke(shape, with: vertical(r, [(.white.opacity(0.3), 0), (.white.opacity(0.04), 0.5), (.white.opacity(0.1), 1)]),
                      lineWidth: u(0.9))
    }

    /// A camera lens: a dark metal bezel, the barrel, coated glass with a violet depth,
    /// and the bright reflections that make it read as glass.
    private func lens(_ ctx: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
        let c = P(cx, cy)
        ctx.fill(disc(cx, cy, r), with: .linearGradient(Gradient(colors: [Color(white: 0.5), Color(white: 0.1), Color(white: 0.32)]),
                                                         startPoint: P(cx - r, cy - r), endPoint: P(cx + r, cy + r)))
        ctx.fill(disc(cx, cy, r * 0.84), with: .color(Color(white: 0.02)))
        let g = r * 0.68
        ctx.fill(disc(cx, cy, g), with: .radialGradient(Gradient(stops: [
            .init(color: Color(red: 0.26, green: 0.28, blue: 0.62), location: 0),
            .init(color: Color(red: 0.08, green: 0.07, blue: 0.2), location: 0.5),
            .init(color: Color(white: 0.01), location: 1),
        ]), center: CGPoint(x: c.x + u(g * 0.15), y: c.y + u(g * 0.2)), startRadius: 0, endRadius: u(g)))
        ctx.stroke(disc(cx, cy, g * 0.52), with: .color(.white.opacity(0.08)), lineWidth: u(0.35))
        // A teal coating flare across the lower right.
        ctx.layer(blur: u(g * 0.18), additive: true) {
            $0.fill(oval(cx + g * 0.28, cy + g * 0.3, g * 0.34, g * 0.2), with: .color(Color(red: 0.2, green: 0.6, blue: 0.55).opacity(0.5)))
        }
        // The window's reflection.
        ctx.layer(blur: u(g * 0.08)) {
            $0.fill(oval(cx - g * 0.32, cy - g * 0.38, g * 0.36, g * 0.2), with: .color(.white.opacity(0.85)))
        }
        ctx.fill(disc(cx + g * 0.36, cy + g * 0.1, g * 0.07), with: .color(.white.opacity(0.55)))
    }

    /// An indicator: a hot core and a halo when lit, a dark bead when not.
    private func led(_ ctx: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ color: Color, lit: Bool) {
        if lit {
            ctx.layer(blur: u(r * 1.6), additive: true) { $0.fill(disc(cx, cy, r * 2.6), with: .color(color.opacity(0.75))) }
            ctx.fill(disc(cx, cy, r), with: .radialGradient(Gradient(colors: [.white, color, color.opacity(0.9)]),
                                                            center: P(cx, cy), startRadius: 0, endRadius: u(r)))
        } else {
            ctx.fill(disc(cx, cy, r), with: .color(Color(white: 0.2)))
            ctx.fill(disc(cx - r * 0.3, cy - r * 0.3, r * 0.35), with: .color(.white.opacity(0.25)))
        }
    }

    private func vertical(_ r: CGRect, _ stops: [(Color, CGFloat)]) -> GraphicsContext.Shading {
        .linearGradient(gradient(stops), startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY))
    }

    private func horizontal(_ r: CGRect, _ stops: [(Color, CGFloat)]) -> GraphicsContext.Shading {
        .linearGradient(gradient(stops), startPoint: CGPoint(x: r.minX, y: r.midY), endPoint: CGPoint(x: r.maxX, y: r.midY))
    }

    private func gradient(_ stops: [(Color, CGFloat)]) -> Gradient {
        Gradient(stops: stops.map { Gradient.Stop(color: $0.0, location: $0.1) })
    }

    // MARK: Smart speaker

    /// A fabric sphere with a flat foot that carries the light ring, seen from a little above.
    private struct SpeakerShape {
        let cx, cy, r: CGFloat
        var cutY: CGFloat { cy + r * 0.8 }
        var ringW: CGFloat { r * 1.2 }
        var ringH: CGFloat { r * 0.26 }
        var band: CGFloat { r * 0.1 }
    }

    private func speakerPaths(_ s: SpeakerShape) -> (body: Path, foot: Path, ring: Path) {
        let ball = disc(s.cx, s.cy, s.r)
        let top = Path(R(s.cx - s.r - 1, s.cy - s.r - 1, s.r * 2 + 2, s.r * 1.8 + 1))
        let base = oval(s.cx, s.cutY, s.ringW / 2, s.ringH / 2)
        let body = ball.intersection(top.union(base))
        let foot = oval(s.cx, s.cutY + s.band, s.ringW / 2 * 0.97, s.ringH / 2)
            .union(Path(R(s.cx - s.ringW / 2 * 0.985, s.cutY, s.ringW * 0.985, s.band)))
        // The front half of the ring, where the light shows.
        var ring = Path()
        let rx = s.ringW / 2 * 0.97, ry = s.ringH / 2, ry0 = s.cutY + s.band * 0.6
        for i in 0...24 {
            let a = Double.pi * Double(i) / 24
            let p = P(s.cx + rx * CGFloat(cos(a)), ry0 + ry * CGFloat(sin(a)))
            i == 0 ? ring.move(to: p) : ring.addLine(to: p)
        }
        return (body, foot, ring)
    }

    private func speaker(_ ctx: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
        let s = SpeakerShape(cx: cx, cy: cy, r: r)
        let (body, foot, ring) = speakerPaths(s)
        let footRect = R(cx - s.ringW / 2, s.cutY - s.ringH / 2, s.ringW, s.band + s.ringH)

        ground(ctx, cx, s.cutY + s.band + s.ringH * 0.25, w: r * 1.9, h: r * 0.34)
        if on {
            // Light pooling on the table.
            ctx.layer(blur: u(r * 0.16), additive: true) {
                $0.fill(oval(cx, s.cutY + s.band + s.ringH * 0.3, r * 1.0, s.ringH * 0.75), with: .color(glow.opacity(0.32)))
            }
        }

        // The foot: frosted, glowing through when lit.
        if on {
            ctx.fill(foot, with: vertical(footRect, [(glow.opacity(0.6), 0.3), (Color.white.opacity(0.95), 0.72), (glow, 1)]))
        } else {
            ctx.fill(foot, with: vertical(footRect, [(Color(white: 0.2), 0.3), (Color(white: 0.34), 0.72), (Color(white: 0.16), 1)]))
        }

        // Fabric, lit from the upper left.
        let bodyRect = R(cx - r, cy - r, r * 2, r * 1.8 + s.ringH / 2)
        ctx.fill(body, with: .radialGradient(Gradient(stops: [
            .init(color: Color(white: 0.9), location: 0),
            .init(color: Color(white: 0.8), location: 0.35),
            .init(color: Color(white: 0.58), location: 0.75),
            .init(color: Color(white: 0.4), location: 1),
        ]), center: P(cx - r * 0.32, cy - r * 0.45), startRadius: 0, endRadius: u(r * 1.75)))
        var inside = ctx
        inside.clip(to: body)
        // The weave: tiny holes, foreshortened toward the edge of the sphere.
        let weave = Fabric.holes.applying(CGAffineTransform(a: u(r), b: 0, c: 0, d: u(r), tx: u(cx), ty: u(cy)))
        inside.fill(weave, with: .color(.black.opacity(0.08 + 0.1 * Double(min(max((k - 0.5) / 1.1, 0), 1)))))
        // Rim falloff makes it round.
        inside.fill(Path(bodyRect.insetBy(dx: -2, dy: -2)), with: .radialGradient(Gradient(stops: [
            .init(color: .clear, location: 0.55),
            .init(color: .black.opacity(0.22), location: 0.85),
            .init(color: .black.opacity(0.42), location: 1),
        ]), center: P(cx + r * 0.05, cy - r * 0.05), startRadius: 0, endRadius: u(r * 1.02)))
        // A soft sheen; fabric scatters light rather than reflecting it.
        inside.layer(blur: u(r * 0.22)) {
            $0.fill(oval(cx - r * 0.28, cy - r * 0.48, r * 0.42, r * 0.26), with: .color(.white.opacity(0.45)))
        }
        // The ring's light washes up the fabric just above it.
        if on {
            var wash = inside
            wash.blendMode = .plusLighter
            wash.fill(Path(R(cx - r, s.cutY - r * 0.5, r * 2, r * 0.7)),
                      with: .linearGradient(Gradient(colors: [.clear, glow.opacity(0.22)]),
                                            startPoint: P(cx, s.cutY - r * 0.5), endPoint: P(cx, s.cutY + s.ringH * 0.5)))
        }

        // A cool rim of light from behind, lifting the lower edge off the dark.
        inside.stroke(disc(cx, cy, r), with: .linearGradient(Gradient(stops: [
            .init(color: .clear, location: 0.45), .init(color: Color(red: 0.75, green: 0.85, blue: 1).opacity(0.5), location: 1),
        ]), startPoint: P(cx - r * 0.6, cy - r * 0.6), endPoint: P(cx + r * 0.7, cy + r * 0.7)), lineWidth: u(r * 0.07))

        // Four buttons in an arc across the top, foreshortened on the curve.
        let elevation = 0.4, spread = 0.5
        for phi in [-0.95, -0.32, 0.32, 0.95] {
            let x = sin(spread) * sin(phi)
            let up = cos(spread) * cos(elevation) - sin(spread) * cos(phi) * sin(elevation)
            let facing = cos(spread) * sin(elevation) + sin(spread) * cos(phi) * cos(elevation)
            let bx = cx + r * CGFloat(x), by = cy - r * CGFloat(up)
            let w = r * 0.075 * CGFloat(cos(spread * sin(phi))), h = r * 0.075 * CGFloat(facing)
            inside.fill(oval(bx, by, w, h), with: .color(Color(white: 0.42).opacity(0.75)))
            inside.fill(oval(bx, by + h * 0.3, w * 0.8, h * 0.6), with: .color(Color(white: 0.7).opacity(0.6)))
            inside.stroke(oval(bx, by + h * 0.12, w, h), with: .color(.white.opacity(0.45)), lineWidth: u(0.25))
        }

        // The seam where fabric meets the foot.
        if on {
            ctx.layer(blur: u(r * 0.03), additive: true) {
                $0.stroke(ring, with: .color(.white.opacity(0.9)), lineWidth: u(r * 0.035))
            }
            ctx.layer(blur: u(r * 0.08), additive: true) {
                $0.stroke(ring, with: .color(glow.opacity(0.7)), lineWidth: u(r * 0.12))
            }
        } else {
            ctx.stroke(ring, with: .color(.black.opacity(0.35)), lineWidth: u(r * 0.025))
        }
    }

    private func speakerBreath(_ ctx: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ amount: Double) {
        let s = SpeakerShape(cx: cx, cy: cy, r: r)
        let (_, foot, ring) = speakerPaths(s)
        ctx.layer(blur: u(r * 0.06), additive: true, opacity: amount) { $0.fill(foot, with: .color(glow.opacity(0.55))) }
        ctx.layer(blur: u(r * 0.2), additive: true, opacity: amount) {
            $0.stroke(ring, with: .color(glow.opacity(0.6)), lineWidth: u(r * 0.3))
        }
        ctx.layer(blur: u(r * 0.18), additive: true, opacity: amount) {
            $0.fill(oval(cx, s.cutY + s.band + s.ringH * 0.4, r * 0.9, s.ringH * 0.6), with: .color(glow.opacity(0.25)))
        }
    }

    // MARK: Mesh speaker

    /// A squat sphere of fine mesh, flat top and bottom, seen a little from above.
    private enum Mesh {
        static let cx: CGFloat = 50, cy: CGFloat = 54, r: CGFloat = 33
        static let topY = cy - r * 0.68, topRx = r * 0.733, topRy = r * 0.21
        static let botY = cy + r * 0.8, botRx = r * 0.6, botRy = r * 0.12
    }

    /// The glass touch surface inset in the top.
    private var meshPanel: Path { oval(Mesh.cx, Mesh.topY + 0.3, Mesh.topRx * 0.8, Mesh.topRy * 0.78) }

    private func meshSpeaker(_ ctx: GraphicsContext) {
        let (cx, cy, r) = (Mesh.cx, Mesh.cy, Mesh.r)
        ground(ctx, cx, Mesh.botY + Mesh.botRy * 0.5, w: r * 1.75, h: r * 0.3)
        ctx.fill(oval(cx, Mesh.botY + 1, Mesh.botRx * 0.94, Mesh.botRy), with: .color(Color(white: 0.1)))

        let ball = disc(cx, cy, r)
        let band = Path(R(cx - r - 1, Mesh.topY, r * 2 + 2, Mesh.botY - Mesh.topY))
        let body = ball.intersection(band.union(oval(cx, Mesh.topY, Mesh.topRx, Mesh.topRy))
            .union(oval(cx, Mesh.botY, Mesh.botRx, Mesh.botRy)))
        let bodyRect = R(cx - r, cy - r, r * 2, r * 2)

        // Mesh, lit from the upper left.
        ctx.fill(body, with: .radialGradient(Gradient(stops: [
            .init(color: Color(white: 0.96), location: 0),
            .init(color: Color(white: 0.87), location: 0.35),
            .init(color: Color(white: 0.64), location: 0.75),
            .init(color: Color(white: 0.44), location: 1),
        ]), center: P(cx - r * 0.3, cy - r * 0.35), startRadius: 0, endRadius: u(r * 1.7)))
        var inside = ctx
        inside.clip(to: body)
        let weave = Fabric.holes.applying(CGAffineTransform(a: u(r), b: 0, c: 0, d: u(r), tx: u(cx), ty: u(cy)))
        inside.fill(weave, with: .color(.black.opacity(0.07 + 0.08 * Double(min(max((k - 0.5) / 1.1, 0), 1)))))
        inside.fill(Path(bodyRect.insetBy(dx: -2, dy: -2)), with: .radialGradient(Gradient(stops: [
            .init(color: .clear, location: 0.55),
            .init(color: .black.opacity(0.2), location: 0.85),
            .init(color: .black.opacity(0.4), location: 1),
        ]), center: P(cx, cy), startRadius: 0, endRadius: u(r * 1.02)))
        inside.layer(blur: u(r * 0.2)) {
            $0.fill(oval(cx - r * 0.34, cy - r * 0.3, r * 0.36, r * 0.22), with: .color(.white.opacity(0.4)))
        }
        inside.stroke(ball, with: .linearGradient(Gradient(stops: [
            .init(color: .clear, location: 0.45), .init(color: Color(red: 0.75, green: 0.85, blue: 1).opacity(0.5), location: 1),
        ]), startPoint: P(cx - r * 0.6, cy - r * 0.6), endPoint: P(cx + r * 0.7, cy + r * 0.7)), lineWidth: u(r * 0.07))

        // The top: a lip of mesh around a dark glass panel.
        let top = oval(cx, Mesh.topY, Mesh.topRx, Mesh.topRy)
        inside.fill(top, with: .linearGradient(Gradient(colors: [Color(white: 0.98), Color(white: 0.84)]),
                                               startPoint: P(cx, Mesh.topY - Mesh.topRy), endPoint: P(cx, Mesh.topY + Mesh.topRy)))
        inside.stroke(top, with: .color(.white.opacity(0.7)), lineWidth: u(0.5))
        let panelRect = R(cx - Mesh.topRx * 0.8, Mesh.topY - Mesh.topRy * 0.78, Mesh.topRx * 1.6, Mesh.topRy * 1.56)
        ctx.fill(meshPanel, with: vertical(panelRect, [(Color(white: 0.04), 0), (Color(white: 0.16), 1)]))
        var glass = ctx
        glass.clip(to: meshPanel)
        if on {
            // A soft swirl of colour under the glass.
            glass.layer(blur: u(2.6), additive: true) {
                $0.fill(oval(cx - 8, Mesh.topY + 0.8, 8, 3.4), with: .color(glow.opacity(0.95)))
                $0.fill(oval(cx + 8, Mesh.topY - 0.2, 7, 3), with: .color(Color(red: 0.95, green: 0.4, blue: 0.9).opacity(0.8)))
                $0.fill(oval(cx + 1, Mesh.topY + 2, 6, 1.8), with: .color(Color(red: 0.55, green: 0.4, blue: 1).opacity(0.75)))
                $0.fill(oval(cx - 1, Mesh.topY - 0.4, 3.6, 1.3), with: .color(.white.opacity(0.8)))
            }
        }
        glass.layer(blur: u(0.6)) {
            $0.fill(oval(cx - 4, Mesh.topY - Mesh.topRy * 0.5, Mesh.topRx * 0.5, Mesh.topRy * 0.18), with: .color(.white.opacity(0.35)))
        }
        ctx.stroke(meshPanel, with: .color(.black.opacity(0.4)), lineWidth: u(0.4))

        if on {
            // Light from the top spilling over the lip.
            ctx.layer(blur: u(4), additive: true) {
                $0.fill(oval(cx, Mesh.topY - 1, Mesh.topRx * 0.75, Mesh.topRy * 1.2), with: .color(glow.opacity(0.22)))
            }
        }
    }

    private func meshBreath(_ ctx: GraphicsContext, _ amount: Double) {
        var glass = ctx
        glass.clip(to: meshPanel)
        glass.layer(blur: u(2), additive: true, opacity: amount) {
            $0.fill(oval(Mesh.cx + 2, Mesh.topY, 10, 3.4), with: .color(glow.opacity(0.55)))
        }
        ctx.layer(blur: u(7), additive: true, opacity: amount) {
            $0.fill(oval(Mesh.cx, Mesh.topY - 2, Mesh.topRx * 0.8, Mesh.topRy * 1.6), with: .color(glow.opacity(0.28)))
        }
    }

    // MARK: Streaming box

    /// A black box seen from a little above, glossy on top and satin round the sides,
    /// with its aluminium remote standing beside it.
    private func streamingBox(_ ctx: GraphicsContext) {
        ground(ctx, 37, 77, w: 66, h: 7)
        ground(ctx, 77.5, 85, w: 18, h: 3.5)

        let topRect = R(7, 40, 60, 24)
        let corner = CGSize(width: u(13), height: u(6))
        let topFace = Path(roundedRect: topRect, cornerSize: corner, style: .continuous)
        let sideHeight: CGFloat = 13
        let side = topFace.offsetBy(dx: 0, dy: u(sideHeight)).union(Path(R(7, 52, 60, sideHeight)))
        let sideRect = R(7, 52, 60, sideHeight + 12)

        // Satin black sides, rounding away at the corners.
        ctx.fill(side, with: horizontal(sideRect, [(Color(white: 0.04), 0), (Color(white: 0.17), 0.22), (Color(white: 0.12), 0.6),
                                                 (Color(white: 0.2), 0.85), (Color(white: 0.05), 1)]))
        var sides = ctx
        sides.clip(to: side)
        sides.fill(Path(sideRect), with: vertical(sideRect, [(.white.opacity(0.08), 0.4), (.black.opacity(0.3), 1)]))
        ctx.stroke(topFace.offsetBy(dx: 0, dy: u(0.9)), with: .color(.white.opacity(0.3)), lineWidth: u(0.6))

        // The glossy top, with a broad reflection across it.
        ctx.fill(topFace, with: vertical(topRect, [(Color(white: 0.2), 0), (Color(white: 0.06), 0.55), (Color(white: 0.1), 1)]))
        var top = ctx
        top.clip(to: topFace)
        var streak = Path()
        streak.move(to: P(18, 38))
        streak.addLine(to: P(40, 38))
        streak.addLine(to: P(30, 66))
        streak.addLine(to: P(8, 66))
        streak.closeSubpath()
        top.layer(blur: u(1.5)) {
            $0.fill(streak, with: .linearGradient(Gradient(colors: [.white.opacity(0.2), .white.opacity(0.02)]),
                                                  startPoint: P(26, 40), endPoint: P(20, 64)))
        }
        top.stroke(topFace, with: vertical(topRect, [(.white.opacity(0.45), 0), (.white.opacity(0.05), 0.4), (.white.opacity(0.12), 1)]),
                   lineWidth: u(1))
        if on {
            // The picture it sends reflects faintly in the gloss.
            top.layer(blur: u(5), additive: true) { $0.fill(oval(50, 44, 14, 4), with: .color(glow.opacity(0.18))) }
        }

        led(ctx, 37, 71.5, 0.7, .white, lit: on)

        // The remote.
        let rr = R(69.5, 28, 16, 57)
        let remote = Path(roundedRect: rr, cornerRadius: u(8), style: .continuous)
        ctx.layer(blur: u(2)) { $0.fill(remote.offsetBy(dx: u(1), dy: u(1.5)), with: .color(.black.opacity(0.7))) }
        ctx.fill(remote, with: horizontal(rr, [(Color(white: 0.5), 0), (Color(white: 0.9), 0.25), (Color(white: 0.97), 0.45),
                                              (Color(white: 0.78), 0.75), (Color(white: 0.5), 1)]))
        var body = ctx
        body.clip(to: remote)
        body.fill(Path(rr), with: vertical(rr, [(.white.opacity(0.2), 0), (.clear, 0.3), (.black.opacity(0.15), 1)]))
        rim(ctx, remote, rr, 0.9, reach: 0.06)
        // Clickpad: a dark ring around a touch surface.
        ctx.fill(disc(77.5, 40, 6.3), with: .linearGradient(Gradient(colors: [Color(white: 0.3), Color(white: 0.08)]),
                                                             startPoint: P(77.5, 33.7), endPoint: P(77.5, 46.3)))
        ctx.fill(disc(77.5, 40, 4.4), with: .radialGradient(Gradient(colors: [Color(white: 0.2), Color(white: 0.07)]),
                                                            center: P(76, 38.5), startRadius: 0, endRadius: u(5)))
        ctx.stroke(disc(77.5, 40, 6.3), with: .color(.white.opacity(0.35)), lineWidth: u(0.3))
        // Buttons.
        for (x, y) in [(74, 52), (81, 52), (74, 58.5)] as [(CGFloat, CGFloat)] {
            ctx.fill(disc(x, y, 2.1), with: .linearGradient(Gradient(colors: [Color(white: 0.28), Color(white: 0.1)]),
                                                            startPoint: P(x, y - 2), endPoint: P(x, y + 2)))
        }
        let volume = R(78.9, 56.4, 4.2, 10)
        ctx.fill(Path(roundedRect: volume, cornerRadius: u(2.1), style: .continuous),
                 with: vertical(volume, [(Color(white: 0.28), 0), (Color(white: 0.1), 1)]))
    }

    // MARK: Indoor camera

    private func indoorCamera(_ ctx: GraphicsContext) {
        ground(ctx, 50, 88.5, w: 52, h: 8)

        // The base: a soft block the head turns on.
        let baseRect = R(29, 58, 42, 30)
        let base = Path(roundedRect: baseRect, cornerRadius: u(11), style: .continuous)
        satin(ctx, base, baseRect, light: 0.96, dark: 0.66, turn: 0.2, gloss: 0.5)
        rim(ctx, base, baseRect, 0.8)
        // A recess on top that holds the head.
        ctx.layer(blur: u(1.6)) { $0.fill(oval(50, 61, 15, 3.4), with: .color(.black.opacity(0.55))) }

        // The head: a satin sphere.
        let head = disc(50, 38, 25)
        let headRect = R(25, 13, 50, 50)
        ctx.layer(blur: u(2.5)) { $0.fill(oval(50, 60, 17, 4), with: .color(.black.opacity(0.4))) }
        ctx.fill(head, with: .radialGradient(Gradient(stops: [
            .init(color: .white, location: 0),
            .init(color: Color(white: 0.95), location: 0.35),
            .init(color: Color(white: 0.76), location: 0.78),
            .init(color: Color(white: 0.6), location: 1),
        ]), center: P(41, 25), startRadius: 0, endRadius: u(46)))
        var inside = ctx
        inside.clip(to: head)
        inside.fill(Path(headRect), with: .radialGradient(Gradient(stops: [
            .init(color: .clear, location: 0.7), .init(color: .black.opacity(0.2), location: 1),
        ]), center: P(50, 38), startRadius: 0, endRadius: u(25)))
        inside.layer(blur: u(3)) { $0.fill(oval(41, 20, 12, 6), with: .color(.white.opacity(0.95))) }
        rim(ctx, head, headRect, 0.7, reach: 0.25)

        // The black face, set into the sphere.
        let face = disc(50, 41, 16.5)
        let faceRect = R(33.5, 24.5, 33, 33)
        ctx.stroke(face.offsetBy(dx: 0, dy: u(0.7)), with: .color(.white.opacity(0.8)), lineWidth: u(0.8))
        blackGlass(ctx, face, faceRect, sheen: 0.22)

        // Infrared emitters around the lens; they glow a faint deep red when watching.
        for i in 0..<8 {
            let a = Double(i) / 8 * 2 * .pi + .pi / 8
            let x = 50 + 12.3 * CGFloat(cos(a)), y = 40 + 12.3 * CGFloat(sin(a))
            ctx.fill(disc(x, y, 0.95), with: .color(Color(red: 0.2, green: 0.06, blue: 0.07)))
            if on {
                ctx.layer(blur: u(0.8), additive: true) {
                    $0.fill(disc(x, y, 1.2), with: .color(Color(red: 0.55, green: 0.08, blue: 0.08).opacity(0.55)))
                }
            }
        }
        lens(ctx, 50, 40, 8.6)
        led(ctx, 50, 53.2, 1.1, glow, lit: on)
    }

    // MARK: Outdoor camera

    private func outdoorCamera(_ ctx: GraphicsContext) {
        // Shadow of the whole unit on the wall behind it.
        ctx.layer(blur: u(5)) {
            $0.fill(Path(roundedRect: R(24, 40, 62, 30), cornerRadius: u(15)), with: .color(.black.opacity(0.75)))
            $0.fill(Path(roundedRect: R(60, 70, 26, 14), cornerRadius: u(5)), with: .color(.black.opacity(0.6)))
        }

        // The wall mount and its arm.
        let plateRect = R(59, 75, 25, 10)
        let plate = Path(roundedRect: plateRect, cornerRadius: u(5), style: .continuous)
        satin(ctx, plate, plateRect, light: 0.9, dark: 0.62, gloss: 0.5)
        rim(ctx, plate, plateRect, 0.7)
        let armRect = R(66.5, 57, 6, 20)
        let arm = Path(roundedRect: armRect, cornerRadius: u(3), style: .continuous)
        ctx.fill(arm, with: horizontal(armRect, [(Color(white: 0.55), 0), (Color(white: 0.95), 0.35), (Color(white: 0.7), 0.7), (Color(white: 0.45), 1)]))
        // The ball joint, tucked up into the underside of the body, in its shade.
        ctx.fill(disc(69.5, 59.5, 4.4), with: .radialGradient(Gradient(colors: [.white, Color(white: 0.8), Color(white: 0.5)]),
                                                              center: P(68, 61), startRadius: 0, endRadius: u(5)))
        ctx.layer(blur: u(1.6)) { $0.fill(oval(69, 56.5, 8, 3), with: .color(.black.opacity(0.55))) }

        // The body, tilted slightly down toward the garden.
        var tilt = ctx
        tilt.translateBy(x: u(52), y: u(45))
        tilt.rotate(by: .degrees(-7))
        tilt.translateBy(x: -u(52), y: -u(45))

        let bodyRect = R(22, 29, 64, 32)
        let body = Path(roundedRect: bodyRect, cornerRadius: u(16), style: .continuous)
        satin(tilt, body, bodyRect, light: 1, dark: 0.7, turn: 0.08, gloss: 0.9)
        rim(tilt, body, bodyRect, 0.9)
        // Solar cells set into the top of the shell.
        let solarRect = R(46, 31.2, 34, 5.2)
        let solar = Path(roundedRect: solarRect, cornerRadius: u(2.6), style: .continuous)
        tilt.fill(solar, with: vertical(solarRect, [(Color(red: 0.2, green: 0.25, blue: 0.4), 0), (Color(red: 0.05, green: 0.07, blue: 0.15), 1)]))
        var cells = tilt
        cells.clip(to: solar)
        var grid = Path()
        for i in 1..<7 {
            let x = 46 + 34 * CGFloat(i) / 7
            grid.move(to: P(x, 31))
            grid.addLine(to: P(x, 37))
        }
        grid.move(to: P(46, 33.8))
        grid.addLine(to: P(80, 33.8))
        cells.stroke(grid, with: .color(Color(red: 0.55, green: 0.65, blue: 0.9).opacity(0.3)), lineWidth: u(0.3))
        cells.layer(blur: u(0.8)) { $0.fill(oval(56, 31.5, 9, 1.4), with: .color(.white.opacity(0.4))) }
        tilt.stroke(solar.offsetBy(dx: 0, dy: u(0.5)), with: .color(.white.opacity(0.6)), lineWidth: u(0.4))

        // The front: a collar of shell around a black glass face.
        let collar = oval(28.5, 45, 12.5, 16)
        tilt.fill(collar, with: horizontal(R(16, 29, 25, 32), [(Color(white: 0.98), 0), (Color(white: 0.86), 0.7), (Color(white: 0.68), 1)]))
        rim(tilt, collar, R(16, 29, 25, 32), 0.9)
        let face = oval(28, 45, 10.4, 13.6)
        blackGlass(tilt, face, R(17.6, 31.4, 20.8, 27.2), sheen: 0.26)
        var squash = tilt
        squash.translateBy(x: u(28.5), y: u(42.5))
        squash.scaleBy(x: 0.82, y: 1)
        squash.translateBy(x: -u(28.5), y: -u(42.5))
        lens(squash, 28.5, 42.5, 6.6)
        // A pair of infrared emitters and the status light below the lens.
        for y in [52.2] as [CGFloat] {
            tilt.fill(oval(24.4, y, 1.1, 1.0), with: .color(Color(red: 0.2, green: 0.06, blue: 0.07)))
            tilt.fill(oval(32.4, y, 1.1, 1.0), with: .color(Color(red: 0.2, green: 0.06, blue: 0.07)))
            if on {
                tilt.layer(blur: u(1), additive: true) {
                    $0.fill(oval(24.4, y, 1.4, 1.3), with: .color(Color(red: 0.6, green: 0.1, blue: 0.08).opacity(0.6)))
                    $0.fill(oval(32.4, y, 1.4, 1.3), with: .color(Color(red: 0.6, green: 0.1, blue: 0.08).opacity(0.6)))
                }
            }
        }
        led(tilt, 28.4, 54.6, 0.85, glow, lit: on)
    }

    // MARK: Doorbell

    private var bellRect: CGRect { R(34, 7, 32, 86) }

    private func doorbell(_ ctx: GraphicsContext) {
        let r = bellRect
        let shape = Path(roundedRect: r, cornerRadius: u(16), style: .continuous)
        // Mounted flat on the wall: a close, soft shadow.
        ctx.layer(blur: u(4)) { $0.fill(shape.offsetBy(dx: u(1.5), dy: u(3)), with: .color(.black.opacity(0.8))) }

        // Brushed satin metal faceplate.
        ctx.fill(shape, with: horizontal(r, [(Color(white: 0.5), 0), (Color(white: 0.8), 0.18), (Color(white: 0.93), 0.4),
                                            (Color(white: 0.84), 0.62), (Color(white: 0.62), 0.88), (Color(white: 0.45), 1)]))
        var inside = ctx
        inside.clip(to: shape)
        inside.fill(Path(r), with: vertical(r, [(.white.opacity(0.18), 0), (.clear, 0.35), (.black.opacity(0.18), 1)]))
        var brush = Path()
        for i in 0..<22 {
            let x = 34 + 32 * (CGFloat(i) + 0.5) / 22
            brush.move(to: P(x, 7))
            brush.addLine(to: P(x, 93))
        }
        inside.stroke(brush, with: .color(.white.opacity(0.07)), lineWidth: u(0.3))
        rim(ctx, shape, r, 0.9, reach: 0.12)

        // The camera window, following the curve of the top.
        let winRect = R(37.5, 10.5, 25, 34)
        let window = Path(roundedRect: winRect, cornerRadius: u(12.5), style: .continuous)
        ctx.stroke(window.offsetBy(dx: 0, dy: u(0.5)), with: .color(.white.opacity(0.55)), lineWidth: u(0.7))
        blackGlass(ctx, window, winRect, sheen: 0.24)
        lens(ctx, 50, 24, 6.4)
        led(ctx, 50, 35.5, 0.9, glow, lit: on)
        for x in [42.5, 57.5] as [CGFloat] {
            ctx.fill(disc(x, 24, 0.9), with: .color(Color(red: 0.2, green: 0.06, blue: 0.07)))
        }
        // Speaker holes.
        var holes = Path()
        for i in 0..<5 {
            holes.addEllipse(in: R(43.8 + CGFloat(i) * 2.8, 50.2, 1.2, 1.2))
        }
        ctx.fill(holes, with: .color(.black.opacity(0.45)))
        ctx.fill(holes.offsetBy(dx: 0, dy: u(0.35)), with: .color(.white.opacity(0.35)))

        // The button: a light ring around a concave metal face.
        let ring = disc(50, 72, 10.5)
        ctx.fill(disc(50, 72, 11.6), with: .linearGradient(Gradient(colors: [.black.opacity(0.4), .white.opacity(0.6)]),
                                                            startPoint: P(50, 60.4), endPoint: P(50, 83.6)))
        if on {
            ctx.fill(ring, with: .radialGradient(Gradient(stops: [
                .init(color: glow, location: 0.78), .init(color: .white, location: 0.9), .init(color: glow, location: 1),
            ]), center: P(50, 72), startRadius: 0, endRadius: u(10.5)))
            ctx.layer(blur: u(2.4), additive: true) {
                $0.stroke(disc(50, 72, 9.4), with: .color(glow.opacity(0.8)), lineWidth: u(3))
            }
        } else {
            ctx.fill(ring, with: .linearGradient(Gradient(colors: [Color(white: 0.2), Color(white: 0.36)]),
                                                 startPoint: P(50, 61.5), endPoint: P(50, 82.5)))
        }
        let button = disc(50, 72, 8)
        ctx.fill(button, with: .linearGradient(Gradient(colors: [Color(white: 0.6), Color(white: 0.92)]),
                                               startPoint: P(46, 64), endPoint: P(54, 80)))
        ctx.stroke(button, with: .linearGradient(Gradient(colors: [.black.opacity(0.35), .white.opacity(0.8)]),
                                                 startPoint: P(50, 64), endPoint: P(50, 80)), lineWidth: u(0.6))
        ctx.layer(blur: u(1.4)) { $0.fill(oval(51.5, 75.5, 4, 2.4), with: .color(.white.opacity(0.6))) }
    }

    private func doorbellBreath(_ ctx: GraphicsContext, _ amount: Double) {
        ctx.layer(blur: u(4), additive: true, opacity: amount) {
            $0.stroke(disc(50, 72, 10), with: .color(glow.opacity(0.7)), lineWidth: u(5))
        }
        ctx.layer(blur: u(1), additive: true, opacity: amount) {
            $0.stroke(disc(50, 72, 9.4), with: .color(.white.opacity(0.4)), lineWidth: u(1))
        }
    }

    // MARK: Security hub

    /// Security lights are green when the system is armed and well, whatever the accent.
    private var secure: Color { Theme.ok.vivid(0.62) }

    /// A base station: a softly rounded satin tower with a black glass visor across its
    /// shoulders, a light bar that glows green inside it, a siren grille below and a
    /// halo of light where it stands.
    private func securityHub(_ ctx: GraphicsContext) {
        ground(ctx, 50, 89.5, w: 50, h: 7)
        if on {
            ctx.layer(blur: u(6), additive: true) { $0.fill(oval(50, 88, 22, 3.4), with: .color(secure.opacity(0.32))) }
        }
        // A dark plinth, set back under the tower.
        let footRect = R(34, 82, 32, 7.5)
        let foot = Path(roundedRect: footRect, cornerRadius: u(3.75), style: .continuous)
        ctx.fill(foot, with: vertical(footRect, [(Color(white: 0.3), 0), (Color(white: 0.12), 1)]))
        rim(ctx, foot, footRect, 0.3)

        let r = R(30, 9, 40, 75)
        let shape = UnevenRoundedRectangle(topLeadingRadius: u(17), bottomLeadingRadius: u(9),
                                           bottomTrailingRadius: u(9), topTrailingRadius: u(17), style: .continuous).path(in: r)
        ctx.layer(blur: u(1.2)) { $0.fill(shape.offsetBy(dx: 0, dy: u(1)), with: .color(.black.opacity(0.6))) }
        satin(ctx, shape, r, light: 1, dark: 0.68, turn: 0.26, gloss: 0.75)
        rim(ctx, shape, r, 0.95, reach: 0.08)
        var inside = ctx
        inside.clip(to: shape)

        // The visor: black glass wrapping round the tower, darker where it turns away.
        let visorRect = R(30, 22, 40, 13)
        let visor = Path(visorRect)
        inside.layer(blur: u(0.8)) { $0.fill(Path(R(30, 21.2, 40, 1.4)), with: .color(.black.opacity(0.25))) }
        blackGlass(inside, visor, visorRect, sheen: 0.2)
        inside.fill(visor, with: horizontal(visorRect, [(.black.opacity(0.55), 0), (.clear, 0.28), (.clear, 0.72), (.black.opacity(0.6), 1)]))
        inside.fill(Path(R(30, 35, 40, 0.7)), with: .color(.white.opacity(0.85)))

        // The light bar inside the visor.
        let barRect = R(40.5, 27.6, 19, 1.9)
        let bar = Path(roundedRect: barRect, cornerRadius: u(0.95), style: .continuous)
        if on {
            inside.layer(blur: u(3), additive: true) { $0.fill(Path(roundedRect: R(37, 25.5, 26, 6), cornerRadius: u(3)), with: .color(secure.opacity(0.5))) }
            ctx.fill(bar, with: horizontal(barRect, [(secure.opacity(0.8), 0), (Color(red: 0.9, green: 1, blue: 0.92), 0.5), (secure.opacity(0.8), 1)]))
            ctx.layer(blur: u(0.8), additive: true) { $0.fill(bar, with: .color(secure.opacity(0.9))) }
        } else {
            ctx.fill(bar, with: .color(Color(white: 0.17)))
        }

        // The status light sits alone on the white, above the visor.
        led(ctx, 50, 16, 0.75, glow, lit: on)

        // The siren grille: a field of fine holes, fading at the curved edges.
        var holes = Path()
        for row in 0..<6 {
            let odd = !row.isMultiple(of: 2)
            for col in 0..<(odd ? 6 : 7) {
                let x = 37 + CGFloat(col) * 4.33 + (odd ? 2.17 : 0)
                holes.addEllipse(in: R(x - 0.65, 52 + CGFloat(row) * 3.6, 1.3, 1.3))
            }
        }
        var grille = inside
        grille.clip(to: Path(roundedRect: R(34, 49, 32, 24), cornerRadius: u(8), style: .continuous))
        grille.fill(holes, with: .color(.black.opacity(0.45)))
        grille.fill(holes.offsetBy(dx: 0, dy: u(0.35)), with: .color(.white.opacity(0.5)))

        if on {
            // The plinth's light washing up the base of the tower.
            var wash = inside
            wash.blendMode = .plusLighter
            wash.fill(Path(R(30, 70, 40, 14)), with: .linearGradient(Gradient(colors: [.clear, secure.opacity(0.22)]),
                                                                    startPoint: P(50, 70), endPoint: P(50, 84)))
            let seam = R(35, 82.6, 30, 1.4)
            ctx.fill(Path(roundedRect: seam, cornerRadius: u(0.7)), with: horizontal(seam, [(secure.opacity(0.5), 0), (.white, 0.5), (secure.opacity(0.5), 1)]))
            ctx.layer(blur: u(1.6), additive: true) { $0.fill(Path(roundedRect: seam, cornerRadius: u(0.7)), with: .color(secure.opacity(0.9))) }
        }
    }

    /// The larger base station: a broad satin box seen a little from above, a black glass
    /// band with the green light bar and a row of status lights, and a slotted vent.
    private func securityHubPro(_ ctx: GraphicsContext) {
        ground(ctx, 50, 85, w: 80, h: 7)
        if on {
            ctx.layer(blur: u(7), additive: true) { $0.fill(oval(50, 84, 32, 3.6), with: .color(secure.opacity(0.25))) }
        }
        // Feet.
        for x in [24, 70] as [CGFloat] {
            ctx.fill(Path(roundedRect: R(x, 80, 6, 3), cornerRadius: u(1.2)), with: .color(Color(white: 0.14)))
        }

        let r = R(12, 22, 76, 59)
        let shape = Path(roundedRect: r, cornerRadius: u(7.5), style: .continuous)
        satin(ctx, shape, r, light: 0.98, dark: 0.66, turn: 0.1, gloss: 0)
        var inside = ctx
        inside.clip(to: shape)

        // The top face, catching the light, and the crisp edge where it turns into the front.
        let topRect = R(12, 22, 76, 9)
        inside.fill(Path(topRect), with: vertical(topRect, [(Color(white: 1), 0), (Color(white: 0.92), 1)]))
        inside.layer(blur: u(1.5)) { $0.fill(oval(50, 25, 26, 2.2), with: .color(.white)) }
        inside.fill(Path(R(12, 31, 76, 0.5)), with: .color(.black.opacity(0.14)))
        inside.fill(Path(R(12, 31.5, 76, 0.7)), with: .color(.white.opacity(0.9)))
        inside.fill(Path(R(12, 32.2, 76, 6)), with: .linearGradient(Gradient(colors: [.black.opacity(0.07), .clear]),
                                                                   startPoint: P(50, 32.2), endPoint: P(50, 38)))
        // Vents along the top.
        var topVents = Path()
        for i in 0..<9 {
            topVents.addRoundedRect(in: R(31 + CGFloat(i) * 4.4, 25.6, 2.6, 1.0), cornerSize: CGSize(width: u(0.5), height: u(0.5)))
        }
        inside.fill(topVents, with: .color(.black.opacity(0.2)))
        rim(ctx, shape, r, 0.95, reach: 0.06)

        // The glass band across the front.
        let bandRect = R(18, 37, 64, 15)
        let band = Path(roundedRect: bandRect, cornerRadius: u(4.5), style: .continuous)
        ctx.stroke(band.offsetBy(dx: 0, dy: u(0.5)), with: .color(.white.opacity(0.75)), lineWidth: u(0.6))
        blackGlass(ctx, band, bandRect, sheen: 0.2)

        let barRect = R(24, 43.6, 30, 1.9)
        let bar = Path(roundedRect: barRect, cornerRadius: u(0.95), style: .continuous)
        if on {
            ctx.layer(blur: u(3), additive: true) { $0.fill(Path(roundedRect: R(22, 41.5, 34, 6), cornerRadius: u(3)), with: .color(secure.opacity(0.5))) }
            ctx.fill(bar, with: horizontal(barRect, [(secure.opacity(0.8), 0), (Color(red: 0.9, green: 1, blue: 0.92), 0.5), (secure.opacity(0.8), 1)]))
            ctx.layer(blur: u(0.8), additive: true) { $0.fill(bar, with: .color(secure.opacity(0.9))) }
        } else {
            ctx.fill(bar, with: .color(Color(white: 0.17)))
        }
        // Status lights: power, network, storage.
        for (i, color) in [secure, glow, glow].enumerated() {
            led(ctx, 63 + CGFloat(i) * 5, 44.5, 0.75, color, lit: on)
        }

        // A slotted vent across the lower front.
        var slots = Path()
        for row in 0..<4 {
            slots.addRoundedRect(in: R(22, 59 + CGFloat(row) * 4, 56, 1.3), cornerSize: CGSize(width: u(0.65), height: u(0.65)))
        }
        inside.fill(slots, with: .color(.black.opacity(0.32)))
        inside.fill(slots.offsetBy(dx: 0, dy: u(0.5)), with: .color(.white.opacity(0.5)))
        inside.fill(Path(R(12, 74, 76, 7)), with: .linearGradient(Gradient(colors: [.clear, .black.opacity(0.1)]),
                                                                 startPoint: P(50, 74), endPoint: P(50, 81)))
    }

    // MARK: 3D printer

    /// An enclosed printer in the Bambu Lab P1S mould: a charcoal cabinet a little taller
    /// than wide, a smoked glass lid on top, a small screen in the band above a full
    /// height smoked glass door, and through it the toolhead on its rods over a textured
    /// build plate. A neutral chamber light reveals the mechanism when printing.
    private func printer3D(_ ctx: GraphicsContext) {
        let x: CGFloat = 19, w: CGFloat = 62
        let topY: CGFloat = 8, lidDepth: CGFloat = 8, frontY: CGFloat = 16, bottom: CGFloat = 89
        let warm = Color(red: 0.94, green: 0.96, blue: 1)
        ground(ctx, 50, bottom, w: w + 14, h: 6)

        // The top: a charcoal frame round a smoked glass lid.
        let topRect = R(x, topY, w, lidDepth + 2)
        let top = Path(roundedRect: topRect, cornerRadius: u(2.5), style: .continuous)
        ctx.fill(top, with: vertical(topRect, [(Color(white: 0.3), 0), (Color(white: 0.2), 1)]))
        let lidRect = R(x + 3, topY + 1.3, w - 6, lidDepth - 2.4)
        let lid = Path(roundedRect: lidRect, cornerRadius: u(1.2), style: .continuous)
        ctx.fill(lid, with: vertical(lidRect, [(Color(red: 0.16, green: 0.14, blue: 0.12), 0), (Color(red: 0.08, green: 0.07, blue: 0.06), 1)]))
        if on {
            ctx.fill(lid, with: vertical(lidRect, [(warm.opacity(0.06), 0), (warm.opacity(0.2), 1)]))
        }
        var glassTop = ctx
        glassTop.clip(to: lid)
        glassTop.layer(blur: u(1)) { $0.fill(Path(R(x + 10, topY + 1.3, 22, 1.4)), with: .color(.white.opacity(0.22))) }
        ctx.stroke(lid, with: .color(.white.opacity(0.12)), lineWidth: u(0.35))

        // The cabinet front, with its sides turning away.
        let bodyRect = R(x, frontY, w, bottom - frontY)
        let body = Path(roundedRect: bodyRect, cornerSize: CGSize(width: u(2.5), height: u(2.5)), style: .continuous)
        ctx.fill(body, with: vertical(bodyRect, [(Color(white: 0.22), 0), (Color(white: 0.15), 0.5), (Color(white: 0.095), 1)]))
        var cabinet = ctx
        cabinet.clip(to: body)
        cabinet.fill(Path(bodyRect), with: horizontal(bodyRect, [(.black.opacity(0.45), 0), (.clear, 0.07), (.clear, 0.93), (.black.opacity(0.5), 1)]))
        // The crease where the top folds into the front.
        cabinet.fill(Path(R(x, frontY, w, 0.5)), with: .color(.white.opacity(0.28)))
        cabinet.fill(Path(R(x, frontY + 0.5, w, 0.6)), with: .color(.black.opacity(0.4)))

        // The screen, top left of the band above the door.
        let sr = R(x + 3.5, frontY + 2.4, 12, 5.6)
        let screen = Path(roundedRect: sr, cornerRadius: u(0.9), style: .continuous)
        blackGlass(ctx, screen, sr, sheen: 0.12)
        if on {
            var lit = ctx
            lit.clip(to: screen)
            lit.fill(Path(sr), with: .color(Color(red: 0.06, green: 0.08, blue: 0.1)))
            lit.fill(Path(roundedRect: R(x + 5, frontY + 3.6, 5, 0.8), cornerRadius: u(0.4)), with: .color(.white.opacity(0.8)))
            lit.fill(Path(roundedRect: R(x + 5, frontY + 5.6, 9, 0.8), cornerRadius: u(0.4)), with: .color(.white.opacity(0.18)))
            lit.fill(Path(roundedRect: R(x + 5, frontY + 5.6, 5.6, 0.8), cornerRadius: u(0.4)), with: .color(glow))
        }

        // The chamber, seen through the door. Everything inside is laid out in grid units.
        let dx = x + 2.5, dy = frontY + 10.5, dw = w - 5, dh = bottom - frontY - 13
        let dr = R(dx, dy, dw, dh)
        let door = Path(roundedRect: dr, cornerRadius: u(1.8), style: .continuous)
        ctx.fill(door, with: vertical(dr, [(Color(white: 0.07), 0), (Color(white: 0.035), 0.7), (Color(white: 0.05), 1)]))
        var chamber = ctx
        chamber.clip(to: door)
        if on {
            // The light strip along the top of the chamber, and its wash down the back wall.
            chamber.fill(Path(dr), with: vertical(dr, [(warm.opacity(0.34), 0), (warm.opacity(0.1), 0.45), (warm.opacity(0.03), 1)]))
            // The chamber has an overhead LED strip, not a glowing nozzle or an
            // amber wash over the entire cabinet.
            chamber.fill(Path(roundedRect: R(dx + 8, dy + 1.4, dw - 16, 0.8), cornerRadius: u(0.4)),
                         with: .color(warm.opacity(0.85)))
        }
        // Side walls receding, so the box has depth.
        for left in [true, false] {
            var wall = Path()
            let ox = left ? dx : dx + dw
            let ix = left ? ox + 5 : ox - 5
            wall.move(to: P(ox, dy))
            wall.addLine(to: P(ix, dy + 4))
            wall.addLine(to: P(ix, dy + dh - 7))
            wall.addLine(to: P(ox, dy + dh))
            wall.closeSubpath()
            chamber.fill(wall, with: .color(.black.opacity(0.28)))
        }
        // Vertical bed guides sit behind the moving gantry and support the plate.
        // These are only resolved at larger sizes; row icons keep a clean chamber.
        if size >= 60 {
            for gx in [dx + 7, dx + dw - 7] {
                let guide = R(gx, dy + 12, 0.9, dh - 17)
                chamber.fill(Path(guide), with: horizontal(guide, [
                    (Color(white: 0.14), 0), (Color(white: 0.5), 0.45), (Color(white: 0.19), 1)
                ]))
            }
        }
        // The carbon rods the toolhead rides on.
        let rodY = dy + 9
        for gap in [0, 3.4] as [CGFloat] {
            let rod = R(dx + 4, rodY + gap, dw - 8, 1)
            chamber.fill(Path(roundedRect: rod, cornerRadius: u(0.5)),
                         with: vertical(rod, [(Color(white: on ? 0.55 : 0.32), 0), (Color(white: 0.08), 1)]))
        }
        // The toolhead: a dark block with a lighter front cover, a fan, and the nozzle below.
        let headBottom = rodY + 9.5
        let hr = R(42, rodY - 3.5, 15, 13)
        let head = Path(roundedRect: hr, cornerRadius: u(2), style: .continuous)
        chamber.fill(head, with: vertical(hr, [(Color(white: on ? 0.42 : 0.26), 0), (Color(white: on ? 0.24 : 0.15), 0.5), (Color(white: 0.08), 1)]))
        chamber.stroke(head, with: vertical(hr, [(.white.opacity(on ? 0.45 : 0.2), 0), (.clear, 0.4)]), lineWidth: u(0.5))
        chamber.fill(disc(49.5, rodY + 2.6, 3.4), with: .color(Color(white: 0.05)))
        var blades = Path()
        for i in 0..<7 {
            let a = Double(i) * 2 * .pi / 7
            blades.move(to: P(49.5, rodY + 2.6))
            blades.addLine(to: P(49.5 + 2.9 * CGFloat(cos(a)), rodY + 2.6 + 2.9 * CGFloat(sin(a))))
        }
        chamber.stroke(blades, with: .color(.white.opacity(0.22)), lineWidth: u(0.45))
        chamber.stroke(disc(49.5, rodY + 2.6, 3.4), with: .color(.white.opacity(0.18)), lineWidth: u(0.35))
        var nozzle = Path()
        nozzle.move(to: P(48.1, headBottom))
        nozzle.addLine(to: P(50.9, headBottom))
        nozzle.addLine(to: P(49.5, headBottom + 2.6))
        nozzle.closeSubpath()
        chamber.fill(nozzle, with: .linearGradient(Gradient(colors: [Color(red: 0.9, green: 0.72, blue: 0.42), Color(red: 0.42, green: 0.3, blue: 0.14)]),
                                                   startPoint: P(48, headBottom), endPoint: P(51, headBottom + 2.6)))

        // The build plate, seen a little from above: a textured gold sheet on the bed.
        let plateY = dy + dh - 15
        var plate = Path()
        plate.move(to: P(dx + 9, plateY))
        plate.addLine(to: P(dx + dw - 9, plateY))
        plate.addLine(to: P(dx + dw - 6, plateY + 5))
        plate.addLine(to: P(dx + 6, plateY + 5))
        plate.closeSubpath()
        let plateRect = R(dx + 6, plateY, dw - 12, 5)
        let gold = on ? Color(red: 0.72, green: 0.6, blue: 0.38) : Color(red: 0.4, green: 0.36, blue: 0.3)
        chamber.fill(plate, with: vertical(plateRect, [(gold.opacity(0.75), 0), (gold, 1)]))
        chamber.fill(Path(R(dx + 6, plateY + 5, dw - 12, 1)), with: .color(Color(white: 0.16)))
        chamber.fill(Path(R(dx + 8, plateY + 6, dw - 16, 2.4)), with: .color(Color(white: 0.02)))

        // The part being printed, standing on the plate in the filament's colour.
        var part = Path()
        part.move(to: P(44.5, plateY + 2.5))
        part.addCurve(to: P(46.2, plateY - 9), control1: P(43.2, plateY - 1.5), control2: P(44.5, plateY - 6))
        part.addLine(to: P(52.8, plateY - 9))
        part.addCurve(to: P(54.5, plateY + 2.5), control1: P(54.5, plateY - 6), control2: P(55.8, plateY - 1.5))
        part.closeSubpath()
        let pr = R(43, plateY - 9, 13, 11.5)
        let filament = on ? glow : Color(white: 0.55)
        chamber.fill(part, with: horizontal(pr, [(filament.opacity(0.55), 0), (filament, 0.35), (filament.opacity(0.95), 0.6), (filament.opacity(0.5), 1)]))
        var layers = chamber
        layers.clip(to: part)
        var lines = Path()
        var ly = plateY - 8.2
        while ly < plateY + 2.5 {
            lines.addRect(R(42, ly, 15, 0.3))
            ly += 1.15
        }
        layers.fill(lines, with: .color(.black.opacity(0.2)))
        // A short carriage beneath the bed connects it to the vertical guides.
        chamber.fill(Path(R(46, plateY + 6, 7, 4.4)), with: .color(Color(white: 0.12)))

        // Smoked glass over it all: a tint, a long reflection and the thin door frame.
        chamber.fill(Path(dr), with: .color(Color(red: 0.07, green: 0.085, blue: 0.1).opacity(on ? 0.12 : 0.38)))
        var streak = Path()
        streak.move(to: P(dx + 7, dy))
        streak.addLine(to: P(dx + 24, dy))
        streak.addLine(to: P(dx + 8, dy + dh))
        streak.addLine(to: P(dx - 9, dy + dh))
        streak.closeSubpath()
        chamber.fill(streak, with: .linearGradient(Gradient(colors: [.white.opacity(0.16), .white.opacity(0.02)]),
                                                   startPoint: P(dx + 14, dy), endPoint: P(dx + 4, dy + dh)))
        ctx.stroke(door, with: .color(Color(white: 0.02)), lineWidth: u(1.4))
        ctx.stroke(door.offsetBy(dx: 0, dy: u(0.3)), with: vertical(dr, [(.white.opacity(0.28), 0), (.white.opacity(0.05), 0.5), (.white.opacity(0.12), 1)]),
                   lineWidth: u(0.45))
        // The handle, down the right edge of the door.
        let handle = R(dx + dw - 3.4, dy + dh / 2 - 10, 1.5, 20)
        ctx.fill(Path(roundedRect: handle, cornerRadius: u(0.75)),
                 with: horizontal(handle, [(Color(white: 0.3), 0), (Color(white: 0.75), 0.5), (Color(white: 0.3), 1)]))
    }

    // MARK: Games console

    /// Near-front Slim-style proportions: the dark front is bounded by four curved
    /// white covers, with a distinct lower disc-drive shoulder. All paths are native.
    private func gameConsole(_ ctx: GraphicsContext) {
        func polygon(_ points: [(CGFloat, CGFloat)]) -> Path {
            var path = Path()
            guard let first = points.first else { return path }
            path.move(to: P(first.0, first.1))
            for point in points.dropFirst() { path.addLine(to: P(point.0, point.1)) }
            path.closeSubpath()
            return path
        }
        func line(_ points: [(CGFloat, CGFloat)]) -> Path {
            var path = Path()
            guard let first = points.first else { return path }
            path.move(to: P(first.0, first.1))
            for point in points.dropFirst() { path.addLine(to: P(point.0, point.1)) }
            return path
        }
        let blue = Color(red: 0.3, green: 0.64, blue: 1)
        ground(ctx, 43, 87.7, w: 48, h: 4.4, opacity: 0.55)
        ground(ctx, 75, 92, w: 36, h: 3.4, opacity: 0.4)
        let foot = Path(ellipseIn: R(21, 84.2, 45, 3.8))
        ctx.fill(foot, with: vertical(R(21, 84.2, 45, 3.8), [
            (Color(white: 0.34), 0), (Color(white: 0.13), 0.35), (Color(white: 0.045), 1)
        ]))
        ctx.stroke(foot, with: .color(.white.opacity(0.25)), lineWidth: u(0.35))

        var core = Path()
        core.move(to: P(31, 13))
        core.addQuadCurve(to: P(55.5, 13), control: P(43, 18))
        core.addCurve(to: P(54, 84.5), control1: P(54.3, 36), control2: P(53.2, 64))
        core.addQuadCurve(to: P(31.2, 84.5), control: P(42.5, 86))
        core.addCurve(to: P(31, 13), control1: P(32, 62), control2: P(32.2, 35))
        core.closeSubpath()
        ctx.fill(core, with: horizontal(R(30, 13, 26, 73), [
            (Color(white: 0.025), 0), (Color(white: 0.115), 0.38),
            (Color(white: 0.075), 0.73), (Color(white: 0.018), 1)
        ]))

        var left = Path()
        left.move(to: P(25.3, 8.4))
        left.addQuadCurve(to: P(28, 9.5), control: P(26.5, 7.2))
        left.addCurve(to: P(34, 15), control1: P(29.2, 12), control2: P(30.7, 14))
        left.addCurve(to: P(32.5, 83.5), control1: P(32.5, 39), control2: P(32.3, 63))
        left.addQuadCurve(to: P(25.5, 83.6), control: P(29, 86))
        left.addCurve(to: P(26.3, 43), control1: P(27.4, 68), control2: P(28, 55))
        left.addCurve(to: P(24.4, 11), control1: P(25.8, 31), control2: P(24.9, 18))
        left.addQuadCurve(to: P(25.3, 8.4), control: P(23.9, 8.3))
        left.closeSubpath()
        ctx.fill(left.offsetBy(dx: u(-0.5), dy: u(0.4)), with: .color(Color(white: 0.48)))
        ctx.fill(left, with: horizontal(R(24, 8, 10.5, 78), [
            (Color(white: 0.87), 0), (Color(white: 0.98), 0.3), (Color(white: 0.74), 1)
        ]))

        var right = Path()
        right.move(to: P(57.4, 8.5))
        right.addQuadCurve(to: P(59.4, 11.2), control: P(60.8, 6.5))
        right.addCurve(to: P(57.8, 40), control1: P(59, 21), control2: P(57.4, 31))
        right.addCurve(to: P(61.4, 53), control1: P(57.3, 47), control2: P(58.7, 50))
        right.addQuadCurve(to: P(65, 61), control: P(65, 56))
        right.addLine(to: P(65, 83))
        right.addQuadCurve(to: P(53, 84.3), control: P(60.3, 86.2))
        right.addCurve(to: P(54, 15), control1: P(52.6, 63), control2: P(53.1, 38))
        right.addQuadCurve(to: P(57.4, 8.5), control: P(56.6, 13.5))
        right.closeSubpath()
        ctx.fill(right.offsetBy(dx: u(0.65), dy: u(0.35)), with: .color(Color(white: 0.43)))
        ctx.fill(right, with: horizontal(R(53, 8, 13, 78), [
            (Color(white: 0.8), 0), (Color(white: 0.96), 0.38), (Color(white: 0.86), 0.8), (Color(white: 0.64), 1)
        ]))
        // The split is a physical gap between upper and lower covers, not a stripe.
        for (shape, points) in [(left, [(25.9, 40.3), (32.9, 38.8)]),
                                (right, [(53.7, 38.8), (58.1, 40.5)])] as [(Path, [(CGFloat, CGFloat)])] {
            var split = ctx
            split.clip(to: shape)
            split.stroke(line(points), with: .color(Color(white: 0.07)),
                         style: StrokeStyle(lineWidth: u(0.9), lineCap: .butt))
        }
        // Slight inner ventilation recesses ground the covers against the black core.
        ctx.stroke(line([(34, 16), (33.2, 31), (32.8, 38)]), with: .color(.black.opacity(0.75)), lineWidth: u(0.65))
        ctx.stroke(line([(54, 16), (53.6, 30), (53.7, 38)]), with: .color(.black.opacity(0.7)), lineWidth: u(0.65))
        if on {
            for points in [[(33.7, 17.0), (33.2, 30.0)], [(54.1, 17.0), (53.7, 30.0)]] as [[(CGFloat, CGFloat)]] {
                ctx.stroke(line(points), with: .color(blue.opacity(0.8)),
                           style: StrokeStyle(lineWidth: u(0.48), lineCap: .round))
            }
        }
        // Tall slot belongs to the lower drive bulge, with a small eject key beneath.
        let slot = Path(roundedRect: R(59.3, 57.5, 1.55, 21.7), cornerRadius: u(0.65))
        ctx.fill(slot, with: .color(Color(white: 0.035)))
        ctx.stroke(slot, with: .color(Color(white: 0.56)), lineWidth: u(0.2))
        ctx.fill(Path(roundedRect: R(59.5, 80.1, 1.1, 1.8), cornerRadius: u(0.3)), with: .color(Color(white: 0.5)))
        if size >= 60 {
            for y: CGFloat in [61, 66] {
                ctx.fill(Path(roundedRect: R(49.5, y, 1.1, 2.2), cornerRadius: u(0.35)), with: .color(Color(white: 0.025)))
                ctx.stroke(Path(roundedRect: R(49.5, y, 1.1, 2.2), cornerRadius: u(0.35)), with: .color(.white.opacity(0.15)), lineWidth: u(0.18))
            }
            ctx.fill(disc(49.8, 79.8, 0.45), with: .color(on ? Color(white: 0.85) : Color(white: 0.25)))
        }

        // DualSense-like front: long tapered white grips, dark central bridge,
        // broad trapezoid touchpad, aligned lower sticks and four separate directions.
        let px: CGFloat = 77, py: CGFloat = 79.5
        let padRect = R(px - 17, py - 7.5, 34, 23)
        var shell = Path()
        shell.move(to: P(px - 12, py - 6))
        shell.addQuadCurve(to: P(px + 12, py - 6), control: P(px, py - 9))
        shell.addCurve(to: P(px + 17, py + 10), control1: P(px + 15, py - 1), control2: P(px + 17.8, py + 5))
        shell.addQuadCurve(to: P(px + 13.2, py + 14), control: P(px + 17, py + 15.3))
        shell.addCurve(to: P(px + 7, py + 5.5), control1: P(px + 11.5, py + 12), control2: P(px + 10.3, py + 6.2))
        shell.addQuadCurve(to: P(px - 7, py + 5.5), control: P(px, py + 4.1))
        shell.addCurve(to: P(px - 13.2, py + 14), control1: P(px - 10.3, py + 6.2), control2: P(px - 11.5, py + 12))
        shell.addQuadCurve(to: P(px - 17, py + 10), control: P(px - 17, py + 15.3))
        shell.addCurve(to: P(px - 12, py - 6), control1: P(px - 17.8, py + 5), control2: P(px - 15, py - 1))
        shell.closeSubpath()
        ctx.fill(shell.offsetBy(dx: 0, dy: u(0.6)), with: .color(Color(white: 0.43)))
        ctx.fill(shell, with: vertical(padRect, [(Color(white: 0.98), 0), (Color(white: 0.9), 0.55), (Color(white: 0.73), 1)]))
        var pad = ctx
        pad.clip(to: shell)
        var bridge = Path()
        bridge.move(to: P(px - 7.6, py - 5))
        bridge.addLine(to: P(px + 7.6, py - 5))
        bridge.addCurve(to: P(px + 13.2, py + 14), control1: P(px + 7, py + 1), control2: P(px + 10.8, py + 8))
        bridge.addLine(to: P(px - 13.2, py + 14))
        bridge.addCurve(to: P(px - 7.6, py - 5), control1: P(px - 10.8, py + 8), control2: P(px - 7, py + 1))
        bridge.closeSubpath()
        pad.fill(bridge, with: vertical(padRect, [(Color(white: 0.19), 0), (Color(white: 0.055), 1)]))
        let touch = polygon([(px - 7.4, py - 6.6), (px + 7.4, py - 6.6),
                             (px + 6.1, py - 0.2), (px - 6.1, py - 0.2)])
        pad.fill(touch, with: vertical(padRect, [(Color(white: 0.97), 0), (Color(white: 0.82), 1)]))
        pad.stroke(touch, with: .color(.black.opacity(0.16)), lineWidth: u(0.25))
        if on {
            for sign: CGFloat in [-1, 1] {
                pad.stroke(line([(px + sign * 7.8, py - 6.2), (px + sign * 6.6, py - 0.4)]),
                           with: .color(blue.opacity(0.9)), lineWidth: u(0.45))
            }
        }
        for x in [px - 4.5, px + 4.5] {
            pad.fill(disc(x, py + 3.3, 2.2), with: .color(Color(white: 0.025)))
            pad.stroke(disc(x, py + 3.3, 1.75), with: .color(Color(white: 0.3)), lineWidth: u(0.35))
            pad.fill(disc(x, py + 3.1, 1.45), with: .color(Color(white: 0.15)))
        }
        for (dx, dy) in [(-11.7, -2.1), (-9.9, -3.9), (-8.1, -2.1), (-9.9, -0.3)] as [(CGFloat, CGFloat)] {
            let key = Path(roundedRect: R(px + dx - 0.7, py + dy - 0.7, 1.4, 1.4), cornerRadius: u(0.4))
            pad.fill(key, with: .color(Color(white: 0.76)))
            pad.stroke(key, with: .color(Color(white: 0.4)), lineWidth: u(0.25))
        }
        for (dx, dy) in [(10, -4), (8.2, -2.1), (11.8, -2.1), (10, -0.2)] as [(CGFloat, CGFloat)] {
            pad.fill(disc(px + dx, py + dy, 0.88), with: .color(Color(white: 0.84)))
            pad.stroke(disc(px + dx, py + dy, 0.88), with: .color(Color(white: 0.45)), lineWidth: u(0.22))
        }
        if size >= 100 {
            let mark = Color(white: 0.43)
            pad.stroke(polygon([(px + 10, py - 4.45), (px + 9.55, py - 3.65), (px + 10.45, py - 3.65)]), with: .color(mark), lineWidth: u(0.15))
            pad.stroke(Path(R(px + 7.8, py - 2.5, 0.8, 0.8)), with: .color(mark), lineWidth: u(0.15))
            pad.stroke(disc(px + 11.8, py - 2.1, 0.4), with: .color(mark), lineWidth: u(0.15))
            pad.stroke(line([(px + 9.65, py - 0.55), (px + 10.35, py + 0.15)]), with: .color(mark), lineWidth: u(0.15))
            pad.stroke(line([(px + 10.35, py - 0.55), (px + 9.65, py + 0.15)]), with: .color(mark), lineWidth: u(0.15))
            for x: CGFloat in [-0.8, 0, 0.8] { pad.fill(disc(px + x, py + 1, 0.16), with: .color(Color(white: 0.4))) }
        }
    }

    // MARK: Computer

    /// A Mac mini style desktop: a nearly cubic block of anodised aluminium, five inches
    /// square and two tall, seen a little from above. Softly rounded vertical corners,
    /// a crisp highlight where the top rolls into the front, two ports and a jack on
    /// the left of the front and a tiny status light on the right.
    private func computer(_ ctx: GraphicsContext) {
        let x: CGFloat = 13, w: CGFloat = 74
        let topY: CGFloat = 27, depth: CGFloat = 27, height: CGFloat = 25
        ground(ctx, 50, topY + depth + height - 0.5, w: w + 8, h: 6.5, opacity: 0.9)

        let topRect = R(x, topY, w, depth)
        let corner = CGSize(width: u(13), height: u(13 * depth / w + 0.6))
        let topFace = Path(roundedRect: topRect, cornerSize: corner, style: .continuous)
        let front = topFace.offsetBy(dx: 0, dy: u(height)).union(Path(R(x, topY + depth / 2, w, height)))
        let frontRect = R(x, topY + depth / 2, w, depth / 2 + height)
        let silver = Color(red: 0.86, green: 0.87, blue: 0.89)

        // The front and the rounded corners turning away to either side.
        ctx.fill(front, with: horizontal(frontRect, [(Color(white: 0.3), 0), (Color(white: 0.55), 0.035), (Color(white: 0.74), 0.09),
                                                   (silver.opacity(0.95), 0.2), (silver, 0.5), (Color(white: 0.8), 0.82),
                                                   (Color(white: 0.6), 0.93), (Color(white: 0.34), 1)]))
        var sides = ctx
        sides.clip(to: front)
        // Lighter just under the edge where it faces the room, darker toward the desk.
        sides.fill(Path(frontRect), with: vertical(frontRect, [(.white.opacity(0.0), 0), (.white.opacity(0.14), 0.42),
                                                               (.clear, 0.62), (.black.opacity(0.3), 1)]))
        // The thin dark base set in under the aluminium.
        sides.fill(topFace.offsetBy(dx: 0, dy: u(height + 0.2)).subtracting(topFace.offsetBy(dx: 0, dy: u(height - 1.1))),
                   with: .color(Color(white: 0.06).opacity(0.9)))

        // Front: two USB-C ports and a headphone jack on the left, the light on the right.
        let midY = topY + depth + height / 2 - 1
        for px in [22.5, 28] as [CGFloat] {
            let port = R(px, midY - 0.85, 4, 1.7)
            sides.fill(Path(roundedRect: port, cornerRadius: u(0.85)), with: .color(Color(white: 0.07)))
            sides.fill(Path(roundedRect: R(px + 0.9, midY - 0.25, 2.2, 0.5), cornerRadius: u(0.25)), with: .color(Color(white: 0.3)))
            sides.stroke(Path(roundedRect: port.offsetBy(dx: 0, dy: u(0.35)), cornerRadius: u(0.85)), with: .color(.white.opacity(0.35)),
                         lineWidth: u(0.25))
        }
        sides.fill(disc(34.6, midY, 0.95), with: .color(Color(white: 0.07)))
        sides.stroke(disc(34.6, midY + 0.3, 0.95), with: .color(.white.opacity(0.35)), lineWidth: u(0.25))
        // The status light: a pinprick, not a lamp.
        if on {
            sides.layer(blur: u(0.5), additive: true) { $0.fill(disc(79, midY, 0.7), with: .color(.white.opacity(0.3))) }
            sides.fill(disc(79, midY, 0.35), with: .color(.white))
        } else {
            sides.fill(disc(79, midY, 0.45), with: .color(Color(white: 0.45)))
        }

        // The top: satin aluminium with a broad soft reflection across it.
        ctx.fill(topFace, with: vertical(topRect, [(Color(white: 0.8), 0), (Color(red: 0.88, green: 0.89, blue: 0.9), 0.5),
                                                   (Color(white: 0.85), 1)]))
        var top = ctx
        top.clip(to: topFace)
        top.fill(Path(topRect), with: horizontal(topRect, [(.black.opacity(0.14), 0), (.clear, 0.12), (.clear, 0.88), (.black.opacity(0.16), 1)]))
        top.layer(blur: u(5)) { $0.fill(oval(40, topY + depth * 0.5, w * 0.28, depth * 0.22), with: .color(.white.opacity(0.22))) }
        // The far edge, a shade darker where it turns down out of sight.
        top.stroke(topFace, with: vertical(topRect, [(.black.opacity(0.18), 0), (.clear, 0.3)]), lineWidth: u(1.2))
        // The crisp roll-over from the top into the front.
        var lip = ctx
        lip.clip(to: Path(R(x - 1, topY + depth / 2, w + 2, depth)))
        lip.stroke(topFace.offsetBy(dx: 0, dy: u(0.35)), with: horizontal(topRect, [(.white.opacity(0.3), 0), (.white, 0.3),
                                                                                    (.white, 0.7), (.white.opacity(0.3), 1)]),
                   lineWidth: u(0.9))
        lip.stroke(topFace.offsetBy(dx: 0, dy: u(1.1)), with: .color(.black.opacity(0.12)), lineWidth: u(0.5))

    }

    // MARK: Air conditioner

    private func airConditioner(_ ctx: GraphicsContext) {
        let r = R(6, 27, 88, 25)
        let h = r.height
        let shape = UnevenRoundedRectangle(topLeadingRadius: h * 0.17, bottomLeadingRadius: h * 0.36,
                                           bottomTrailingRadius: h * 0.36, topTrailingRadius: h * 0.17, style: .continuous)
            .path(in: r)
        ctx.layer(blur: u(6)) {
            $0.fill(Path(roundedRect: R(12, 38, 76, 22), cornerRadius: u(10)), with: .color(.black.opacity(0.75)))
        }
        ctx.layer(blur: u(1.2)) { $0.fill(shape.offsetBy(dx: 0, dy: u(1.2)), with: .color(.black.opacity(0.5))) }
        if on { conditionedAir(ctx, top: 27 + 25 * 0.88 + 25 * 0.24) }

        satin(ctx, shape, r)
        var inside = ctx
        inside.clip(to: shape)
        let seamY: CGFloat = 27 + 25 * 0.6
        var seam = Path()
        seam.move(to: P(9, seamY))
        seam.addLine(to: P(91, seamY))
        inside.stroke(seam, with: .color(.black.opacity(0.13)), lineWidth: u(0.45))
        inside.stroke(seam.offsetBy(dx: 0, dy: u(0.6)), with: .color(.white.opacity(0.75)), lineWidth: u(0.45))
        inside.fill(Path(R(6, seamY, 88, 10)), with: .linearGradient(Gradient(colors: [.clear, .black.opacity(0.08)]),
                                                                    startPoint: P(50, seamY), endPoint: P(50, 52)))

        let vent = R(12, 27 + 25 * 0.73, 76, 25 * 0.15)
        let ventPath = Path(roundedRect: vent, cornerRadius: vent.height / 2, style: .continuous)
        inside.fill(ventPath, with: vertical(vent, [(Color(white: 0.07), 0), (Color(white: 0.22), 1)]))
        var slats = inside
        slats.clip(to: ventPath)
        var lines = Path()
        for i in 1..<18 {
            let x = 12 + 76 * CGFloat(i) / 18
            lines.move(to: P(x, 44))
            lines.addLine(to: P(x - 0.8, 49))
        }
        slats.stroke(lines, with: .color(.white.opacity(0.09)), lineWidth: u(0.35))
        if on {
            slats.fill(ventPath, with: .color(accent.opacity(0.2)))
        } else {
            inside.fill(Path(roundedRect: vent.insetBy(dx: -u(0.5), dy: -u(0.3)), cornerRadius: vent.height / 2, style: .continuous),
                        with: vertical(vent, [(Color(white: 0.9), 0), (Color(white: 0.76), 1)]))
        }

        // The hidden display glows through the panel.
        if on {
            let text = Text("24").font(.system(size: u(5.4), weight: .semibold, design: .rounded))
            inside.layer(blur: u(1.4)) { $0.draw(text.foregroundColor(glow), at: P(81, 36)) }
            inside.draw(text.foregroundColor(glow.vivid(0.8, brightness: 0.85)), at: P(81, 36))
        }

        var edge = Path()
        edge.move(to: P(10, 27.4))
        edge.addLine(to: P(90, 27.4))
        ctx.stroke(edge, with: .color(.white), lineWidth: u(0.5))

        if on {
            // The louver, swung open.
            var blade = Path()
            let hinge: CGFloat = 27 + 25 * 0.88 - 0.3
            let drop: CGFloat = 5.5
            blade.move(to: P(13, hinge))
            blade.addLine(to: P(87, hinge))
            blade.addQuadCurve(to: P(85, hinge + drop), control: P(86.6, hinge + drop * 0.6))
            blade.addLine(to: P(15, hinge + drop))
            blade.addQuadCurve(to: P(13, hinge), control: P(13.4, hinge + drop * 0.6))
            blade.closeSubpath()
            ctx.layer(blur: u(1.2)) { $0.fill(blade.offsetBy(dx: 0, dy: u(1)), with: .color(.black.opacity(0.35))) }
            ctx.fill(blade, with: .linearGradient(Gradient(colors: [Color(white: 0.97), Color(white: 0.8)]),
                                                  startPoint: P(50, hinge), endPoint: P(50, hinge + drop)))
            var lip = Path()
            lip.move(to: P(15, hinge + drop))
            lip.addLine(to: P(85, hinge + drop))
            ctx.stroke(lip, with: .color(.white.opacity(0.9)), lineWidth: u(0.4))
        }
    }

    /// A still frame of the falling air: a luminous sheet and a few currents.
    private func conditionedAir(_ ctx: GraphicsContext, top: CGFloat) {
        let color = accent
        ctx.layer(blur: u(5), additive: true) {
            $0.fill(Path(roundedRect: R(14, top - 1, 72, 26), cornerRadius: u(12)),
                    with: .linearGradient(Gradient(colors: [color.opacity(0.32), color.opacity(0)]),
                                          startPoint: P(50, top), endPoint: P(50, top + 26)))
        }
        ctx.layer(blur: u(0.5), additive: true) {
            for i in 0..<7 {
                let x0 = 18 + 64 * CGFloat(i) / 6
                let side = (x0 - 50) / 32
                var path = Path()
                for s in 0...16 {
                    let p = CGFloat(s) / 16
                    let y = top + 30 * p
                    let x = x0 + side * 9 * p + sin(p * 4.5 + CGFloat(i) * 1.9) * (0.4 + 1.6 * p)
                    s == 0 ? path.move(to: P(x, y)) : path.addLine(to: P(x, y))
                }
                $0.stroke(path, with: .linearGradient(Gradient(colors: [color.opacity(0.6), color.opacity(0)]),
                                                      startPoint: P(x0, top), endPoint: P(x0, top + 28)),
                          style: StrokeStyle(lineWidth: u(0.55), lineCap: .round, dash: [u(9), u(5)], dashPhase: u(CGFloat(i) * 3.7)))
            }
        }
    }

    // MARK: Fridge

    private func fridge(_ ctx: GraphicsContext) {
        ground(ctx, 51, 93, w: 58, h: 6)
        // The side, turning away into shade.
        var side = Path()
        side.move(to: P(71, 6.5))
        side.addLine(to: P(77, 9))
        side.addLine(to: P(77, 89.5))
        side.addLine(to: P(71, 92))
        side.closeSubpath()
        ctx.fill(side, with: vertical(R(71, 6, 6, 86), [(Color(white: 0.6), 0), (Color(white: 0.36), 1)]))

        let r = R(25, 6, 47, 86)
        let shape = Path(roundedRect: r, cornerRadius: u(5), style: .continuous)
        ctx.fill(shape, with: vertical(r, [(Color(white: 0.95), 0), (Color(white: 0.86), 0.45), (Color(white: 0.72), 1)]))
        var inside = ctx
        inside.clip(to: shape)
        inside.fill(Path(r), with: horizontal(r, [(.white.opacity(0.2), 0), (.clear, 0.3), (.black.opacity(0.06), 0.75), (.black.opacity(0.16), 1)]))
        var brush = Path()
        for i in 0..<40 {
            let x = 25 + 47 * (CGFloat(i) + 0.5) / 40
            brush.move(to: P(x, 6))
            brush.addLine(to: P(x, 92))
        }
        inside.stroke(brush, with: .color(.white.opacity(0.06)), lineWidth: u(0.25))
        // A long vertical reflection down the doors.
        inside.layer(blur: u(2.5)) { $0.fill(Path(R(32, 4, 6, 90)), with: .color(.white.opacity(0.35))) }
        rim(ctx, shape, r, 0.9, reach: 0.05)

        // The gap between the freezer and fridge doors.
        let gapY: CGFloat = 37
        inside.fill(Path(R(25, gapY - 0.5, 47, 1.1)), with: .color(Color(white: 0.2)))
        inside.fill(Path(R(25, gapY + 0.6, 47, 0.5)), with: .color(.white.opacity(0.85)))
        inside.layer(blur: u(1)) { $0.fill(Path(R(25, gapY - 2.2, 47, 1.6)), with: .color(.black.opacity(0.18))) }

        // Bar handles, standing off the doors.
        for (y, h) in [(18, 15), (44, 26)] as [(CGFloat, CGFloat)] {
            let hr = R(63.5, y, 2.8, h)
            let handle = Path(roundedRect: hr, cornerRadius: u(1.4), style: .continuous)
            ctx.layer(blur: u(1)) { $0.fill(handle.offsetBy(dx: u(1.4), dy: u(1)), with: .color(.black.opacity(0.35))) }
            ctx.fill(handle, with: horizontal(hr, [(Color(white: 0.55), 0), (Color(white: 1), 0.35), (Color(white: 0.7), 0.7), (Color(white: 0.45), 1)]))
        }

        // The display, dark glass that lights up.
        let dr = R(34, 16, 14, 8)
        let display = Path(roundedRect: dr, cornerRadius: u(1.8), style: .continuous)
        ctx.stroke(display.offsetBy(dx: 0, dy: u(0.4)), with: .color(.white.opacity(0.7)), lineWidth: u(0.5))
        blackGlass(ctx, display, dr, sheen: 0.18)
        if on {
            let text = Text("4°").font(.system(size: u(4.8), weight: .medium, design: .rounded))
            ctx.layer(blur: u(0.9), additive: true) { $0.draw(text.foregroundColor(glow), at: P(41, 20)) }
            ctx.draw(text.foregroundColor(accent), at: P(41, 20))
        }

        // Feet.
        ctx.fill(Path(roundedRect: R(28, 91.5, 6, 2.2), cornerRadius: u(1)), with: .color(Color(white: 0.15)))
        ctx.fill(Path(roundedRect: R(63, 91.5, 6, 2.2), cornerRadius: u(1)), with: .color(Color(white: 0.15)))
    }

    // MARK: TV

    private func tv(_ ctx: GraphicsContext) {
        ground(ctx, 50, 81.5, w: 46, h: 5)
        if on {
            // Light from the picture spilling behind and below.
            ctx.layer(blur: u(10), additive: true) {
                $0.fill(Path(roundedRect: R(10, 22, 80, 46), cornerRadius: u(8)), with: .color(glow.opacity(0.22)))
            }
        }
        // The stand: a slim neck and a low foot.
        let neck = R(46.5, 66, 7, 11)
        ctx.fill(Path(neck), with: horizontal(neck, [(Color(white: 0.25), 0), (Color(white: 0.55), 0.4), (Color(white: 0.2), 1)]))
        let footRect = R(31, 76.5, 38, 4.5)
        let foot = Path(roundedRect: footRect, cornerRadius: u(2.25), style: .continuous)
        ctx.fill(foot, with: vertical(footRect, [(Color(white: 0.55), 0), (Color(white: 0.22), 0.5), (Color(white: 0.12), 1)]))
        rim(ctx, foot, footRect, 0.7)

        let r = R(5, 17, 90, 52)
        let frame = Path(roundedRect: r, cornerRadius: u(2.4), style: .continuous)
        ctx.fill(frame, with: vertical(r, [(Color(white: 0.28), 0), (Color(white: 0.12), 1)]))
        let sr = r.insetBy(dx: u(1.2), dy: u(1.2))
        let screen = Path(roundedRect: sr, cornerRadius: u(1.4), style: .continuous)
        if on {
            ctx.fill(screen, with: vertical(sr, [(Color(red: 0.05, green: 0.07, blue: 0.16), 0), (Color(red: 0.02, green: 0.025, blue: 0.06), 1)]))
            var picture = ctx
            picture.clip(to: screen)
            picture.blendMode = .plusLighter
            picture.addFilter(.blur(radius: u(5)))
            picture.fill(oval(30, 58, 30, 14), with: .color(glow.opacity(0.75)))
            picture.fill(oval(68, 46, 24, 16), with: .color(Theme.air("auto").vivid(0.55).opacity(0.55)))
            picture.fill(oval(56, 64, 22, 8), with: .color(Theme.air("heat").opacity(0.5)))
            picture.fill(oval(24, 30, 18, 8), with: .color(Theme.air("dry").vivid(0.5).opacity(0.25)))
        } else {
            ctx.fill(screen, with: vertical(sr, [(Color(white: 0.07), 0), (Color(white: 0.025), 1)]))
        }
        // A diagonal reflection across the glass.
        var sheen = ctx
        sheen.clip(to: screen)
        var band = Path()
        band.move(to: P(8, 18))
        band.addLine(to: P(40, 18))
        band.addLine(to: P(18, 68))
        band.addLine(to: P(8, 68))
        band.closeSubpath()
        sheen.fill(band, with: .linearGradient(Gradient(colors: [.white.opacity(0.1), .white.opacity(0.0)]),
                                               startPoint: P(10, 18), endPoint: P(30, 60)))
        ctx.stroke(frame, with: vertical(r, [(.white.opacity(0.5), 0), (.white.opacity(0.06), 0.3), (.white.opacity(0.12), 1)]),
                   lineWidth: u(0.5))
        led(ctx, 50, 68.4, 0.45, on ? Color.white : Color(white: 0.3), lit: on)
    }

    // MARK: Router

    private func router(_ ctx: GraphicsContext) {
        ground(ctx, 50, 79, w: 74, h: 6)
        // Antennas, standing behind the body.
        for (x, angle, len) in [(26, -14, 44), (50, 0, 48), (74, 14, 44)] as [(CGFloat, Double, CGFloat)] {
            let ar = R(x - 2.6, 58 - len, 5.2, len)
            let antenna = Path(roundedRect: ar, cornerRadius: u(2.6), style: .continuous)
            let pivot = P(x, 58)
            let turn = CGAffineTransform(translationX: pivot.x, y: pivot.y).rotated(by: angle * .pi / 180)
                .translatedBy(x: -pivot.x, y: -pivot.y)
            let shaped = antenna.applying(turn)
            ctx.fill(shaped, with: .linearGradient(Gradient(stops: [
                .init(color: Color(white: 0.55), location: 0), .init(color: Color(white: 0.96), location: 0.4),
                .init(color: Color(white: 0.75), location: 0.75), .init(color: Color(white: 0.5), location: 1),
            ]), startPoint: CGPoint(x: ar.minX, y: ar.midY).applying(turn), endPoint: CGPoint(x: ar.maxX, y: ar.midY).applying(turn)))
            // A hinge collar at the bottom.
            ctx.fill(Path(roundedRect: R(x - 3.2, 55, 6.4, 4), cornerRadius: u(1.4)).applying(turn), with: .color(Color(white: 0.4)))
        }

        let r = R(14, 55, 72, 22)
        let shape = Path(roundedRect: r, cornerRadius: u(7.5), style: .continuous)
        satin(ctx, shape, r, light: 1, dark: 0.64, turn: 0.1, gloss: 0.75)
        rim(ctx, shape, r, 0.95, reach: 0.18)
        var inside = ctx
        inside.clip(to: shape)
        // The top surface catches the light; the front sits in a little shade below a soft crease.
        inside.fill(Path(R(14, 62.5, 72, 15)), with: .linearGradient(Gradient(colors: [.black.opacity(0.07), .black.opacity(0.0)]),
                                                                    startPoint: P(50, 62.5), endPoint: P(50, 68)))
        inside.stroke(Path(R(14, 62.2, 72, 0)), with: .color(.white.opacity(0.8)), lineWidth: u(0.4))
        // Ventilation grooves on top.
        var grooves = Path()
        for i in 0..<11 {
            let x = 30 + CGFloat(i) * 4
            grooves.move(to: P(x, 57.4))
            grooves.addLine(to: P(x + 1.2, 60.6))
        }
        inside.stroke(grooves, with: .color(.black.opacity(0.18)), style: StrokeStyle(lineWidth: u(0.6), lineCap: .round))
        // Status lights along the front.
        let colors: [Color] = [Theme.ok, glow, glow, glow, glow]
        for (i, color) in colors.enumerated() {
            led(ctx, 34 + CGFloat(i) * 8, 70, 0.9, color, lit: on)
        }
    }

    // MARK: Phone

    private func phone(_ ctx: GraphicsContext) {
        let r = R(31, 6, 38, 88)
        let shape = Path(roundedRect: r, cornerRadius: u(9.5), style: .continuous)
        ctx.layer(blur: u(5)) { $0.fill(shape.offsetBy(dx: u(1.5), dy: u(4)), with: .color(.black.opacity(0.8))) }
        // Side buttons.
        for br in [R(30, 22, 1.6, 6), R(30, 31, 1.6, 10), R(68.4, 27, 1.6, 13)] {
            ctx.fill(Path(roundedRect: br, cornerRadius: u(0.8)), with: horizontal(br, [(Color(white: 0.35), 0), (Color(white: 0.75), 1)]))
        }
        // A brushed metal frame.
        ctx.fill(shape, with: horizontal(r, [(Color(white: 0.35), 0), (Color(white: 0.8), 0.04), (Color(white: 0.5), 0.1),
                                            (Color(white: 0.45), 0.9), (Color(white: 0.75), 0.96), (Color(white: 0.3), 1)]))
        let gr = r.insetBy(dx: u(1.4), dy: u(1.4))
        let glass = Path(roundedRect: gr, cornerRadius: u(8.2), style: .continuous)
        ctx.fill(glass, with: .color(Color(white: 0.02)))
        let sr = gr.insetBy(dx: u(1.3), dy: u(1.3))
        let screen = Path(roundedRect: sr, cornerRadius: u(7), style: .continuous)
        if on {
            ctx.fill(screen, with: vertical(sr, [(Color(red: 0.04, green: 0.05, blue: 0.12), 0), (Color(red: 0.06, green: 0.08, blue: 0.2), 1)]))
            var wall = ctx
            wall.clip(to: screen)
            wall.layer(blur: u(6), additive: true) {
                $0.fill(oval(40, 84, 20, 16), with: .color(glow.opacity(0.85)))
                $0.fill(oval(64, 70, 14, 14), with: .color(Theme.air("auto").vivid(0.55).opacity(0.6)))
                $0.fill(oval(50, 96, 20, 8), with: .color(Theme.air("heat").opacity(0.5)))
            }
            let time = Text("10:24").font(.system(size: u(9), weight: .light, design: .rounded))
            wall.draw(time.foregroundColor(.white.opacity(0.92)), at: P(50, 24))
            let date = Text("TUESDAY").font(.system(size: u(2.4), weight: .semibold))
            wall.draw(date.foregroundColor(.white.opacity(0.6)), at: P(50, 17.5))
            for (x, w) in [(36, 12), (52, 12)] as [(CGFloat, CGFloat)] {
                let wr = R(x, 33, w, 12)
                wall.fill(Path(roundedRect: wr, cornerRadius: u(3), style: .continuous), with: .color(.white.opacity(0.12)))
                wall.stroke(Path(roundedRect: wr, cornerRadius: u(3), style: .continuous), with: .color(.white.opacity(0.14)), lineWidth: u(0.3))
            }
            wall.fill(Path(roundedRect: R(43, 89, 14, 0.9), cornerRadius: u(0.45)), with: .color(.white.opacity(0.7)))
        } else {
            ctx.fill(screen, with: vertical(sr, [(Color(white: 0.08), 0), (Color(white: 0.03), 1)]))
        }
        // Reflection across the glass.
        var sheen = ctx
        sheen.clip(to: glass)
        var band = Path()
        band.move(to: P(31, 6))
        band.addLine(to: P(58, 6))
        band.addLine(to: P(31, 60))
        band.closeSubpath()
        sheen.fill(band, with: .linearGradient(Gradient(colors: [.white.opacity(0.12), .white.opacity(0)]),
                                               startPoint: P(36, 8), endPoint: P(46, 40)))
        // Front camera.
        ctx.fill(disc(50, 11.4, 1.3), with: .color(Color(white: 0.01)))
        ctx.fill(disc(49.6, 11.0, 0.4), with: .color(Color(red: 0.4, green: 0.45, blue: 0.8).opacity(0.6)))
        rim(ctx, shape, r, 0.7, reach: 0.06)
    }

    // MARK: Generic

    /// A small smart module: a satin tile with a concave button and a status ring.
    private func generic(_ ctx: GraphicsContext) {
        ground(ctx, 50, 84, w: 56, h: 7)
        let r = R(24, 20, 52, 62)
        let shape = Path(roundedRect: r, cornerRadius: u(15), style: .continuous)
        satin(ctx, shape, r, light: 1, dark: 0.66, turn: 0.18, gloss: 0.7)
        rim(ctx, shape, r, 0.9, reach: 0.12)
        ctx.fill(disc(50, 50, 13.5), with: .linearGradient(Gradient(colors: [.black.opacity(0.22), .white.opacity(0.75)]),
                                                            startPoint: P(50, 36.5), endPoint: P(50, 63.5)))
        let ring = disc(50, 50, 12.4)
        if on {
            ctx.fill(ring, with: .radialGradient(Gradient(stops: [
                .init(color: glow, location: 0.8), .init(color: .white, location: 0.92), .init(color: glow, location: 1),
            ]), center: P(50, 50), startRadius: 0, endRadius: u(12.4)))
            ctx.layer(blur: u(3), additive: true) { $0.stroke(disc(50, 50, 11.5), with: .color(glow.opacity(0.7)), lineWidth: u(3)) }
        } else {
            ctx.fill(ring, with: .color(Color(white: 0.6)))
        }
        let button = disc(50, 50, 10)
        ctx.fill(button, with: .linearGradient(Gradient(colors: [Color(white: 0.78), Color(white: 0.98)]),
                                               startPoint: P(46, 41), endPoint: P(54, 60)))
        ctx.stroke(button, with: .linearGradient(Gradient(colors: [.black.opacity(0.25), .white]),
                                                 startPoint: P(50, 40), endPoint: P(50, 60)), lineWidth: u(0.6))
        led(ctx, 50, 74, 0.9, glow, lit: on)
    }
}

// MARK: Helpers

/// A weave of tiny holes across the front of a unit sphere, spaced evenly over its surface
/// and foreshortened toward the edge. Built once and scaled to each speaker.
private enum Fabric {
    static let holes: Path = {
        var path = Path()
        let step = 0.068
        var lat = -1.42
        var row = 0
        while lat < 1.42 {
            let along = step / max(cos(lat), 0.25)
            var lon = -1.5 + (row.isMultiple(of: 2) ? 0 : along / 2)
            while lon < 1.5 {
                let facing = cos(lon) * cos(lat)
                if facing > 0.1 {
                    let x = sin(lon) * cos(lat), y = sin(lat)
                    let d = 0.017
                    path.addEllipse(in: CGRect(x: x - d * cos(lon), y: y - d * cos(lat), width: 2 * d * cos(lon), height: 2 * d * cos(lat)))
                }
                lon += along
            }
            lat += step
            row += 1
        }
        return path
    }()
}

private extension GraphicsContext {
    /// Draws into a copy of the context, through a blur and blend of its own.
    func layer(blur: CGFloat = 0, additive: Bool = false, opacity: Double = 1, _ draw: (inout GraphicsContext) -> Void) {
        var c = self
        if blur > 0 { c.addFilter(.blur(radius: blur)) }
        if additive { c.blendMode = .plusLighter }
        c.opacity = opacity
        draw(&c)
    }
}

extension Color {
    /// The same hue with more colour in it, for the core of a light rather than a tint.
    func vivid(_ saturation: CGFloat = 0.72, brightness: CGFloat = 1) -> Color {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return self }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: h, saturation: max(s, saturation), brightness: max(b, brightness), opacity: a)
    }
}
