import AppKit
import SwiftUI

// MARK: Recognising vehicles

extension DeviceKind {
    /// Things that move or charge: the Vehicles page.
    static let vehicles: [DeviceKind] = [.electricCar, .evCharger, .robotVacuum, .lawnMower, .aircraft, .robot]

    var vehicleTitle: String {
        switch self {
        case .electricCar: "Electric car"
        case .evCharger: "Car charger"
        case .robotVacuum: "Robot vacuum"
        case .lawnMower: "Robot mower"
        case .aircraft: "Aircraft"
        case .robot: "Robot"
        default: title
        }
    }

    /// Car makers whose Home Assistant integrations report the car as a device.
    private static let carMakers = ["tesla", "bmw", "mini", "renault", "nissan", "kia", "hyundai", "volkswagen", "vw",
                                    "polestar", "rivian", "byd", "mercedes", "audi", "porsche", "skoda", "cupra", "volvo",
                                    "ford", "lucid", "jaguar", "smart", "mg motor", "toyota", "lexus", "peugeot", "opel",
                                    "citroen", "fiat", "zeekr", "xpeng", "nio"]
    /// Chargers that report charging for whichever car is plugged in.
    private static let chargerMakers = ["wallbox", "easee", "zaptec", "chargepoint", "ohme", "myenergi", "go-e", "pod point",
                                        "hypervolt", "juicebox", "enphase ev", "openevse", "alfen", "keba"]

    /// The vehicle a Home Assistant device is, if it is one. Vacuums and mowers are known by their
    /// entity domain; cars by maker plus something only a car has (a location, a lock, a model name).
    static func vehicle(maker: String, model m: String, name n: String, domains: Set<String>) -> DeviceKind? {
        let text = m + " " + n
        func says(_ words: String...) -> Bool { words.contains { text.contains($0) } }

        if domains.contains("vacuum") { return .robotVacuum }
        if domains.contains("lawn_mower") || says("automower", "robot mower", "lawn mower") { return .lawnMower }

        // A Tesla account also lists Powerwalls and Wall Connectors, so a car needs to look like one.
        if chargerMakers.contains(where: { maker.hasPrefix($0) }) || says("wall connector", "wallbox", "ev charger", "charge point", "chargepoint") {
            return .evCharger
        }
        let carModel = says("model 3", "model y", "model s", "model x", "cybertruck", "ioniq", "ev6", "ev9", "leaf", "zoe",
                            "id.3", "id.4", "id.7", "i3", "i4", "ix", "eqa", "eqb", "eqe", "eqs", "e-tron", "taycan",
                            "polestar", "r1t", "r1s", "atto", "dolphin", "seal", "han", "tang", "megane", "enyaq", "mach-e")
        // Whole words only, so "kia" never matches Nokia.
        let words = Set(maker.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        let carMaker = carMakers.contains { words.contains($0) || ($0.contains(" ") && maker.hasPrefix($0)) }
        if carMaker, carModel || domains.contains("device_tracker") || domains.contains("lock") {
            return .electricCar
        }
        if carModel && (domains.contains("device_tracker") || domains.contains("lock")) { return .electricCar }

        let padded = " " + text + " "
        if maker.contains("dji") || says("aircraft", "airplane", "aeroplane", "evtol", "drone", "quadcopter")
            || padded.contains(" jet ") || padded.contains(" plane ") {
            return .aircraft
        }
        if says("robot") { return .robot }
        return nil
    }
}

// MARK: Drawing

/// Cars, chargers and robots, drawn the same way as `DeviceArt`: on a 100 by 100 grid, lit
/// from above, with soft cast shadows and lights that glow when the device is on.
struct VehicleArt {
    let kind: DeviceKind
    let size: CGFloat
    let on: Bool
    let accent: Color

    private var k: CGFloat { size / 100 }
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

    func draw(_ ctx: GraphicsContext) {
        switch kind {
        case .electricCar: car(ctx)
        case .evCharger: charger(ctx)
        case .robotVacuum: vacuum(ctx)
        case .lawnMower: mower(ctx)
        case .aircraft: aircraft(ctx)
        default: robot(ctx)
        }
    }

    // MARK: Materials

    private func ground(_ ctx: GraphicsContext, _ cx: CGFloat, _ y: CGFloat, w: CGFloat, h: CGFloat, opacity: Double = 0.85) {
        ctx.vlayer(blur: u(h * 0.55)) { $0.fill(oval(cx, y, w / 2, h / 2), with: .color(.black.opacity(opacity))) }
        ctx.vlayer(blur: u(max(h * 0.14, 0.6))) {
            $0.fill(oval(cx, y - h * 0.08, w * 0.4, h * 0.16), with: .color(.black.opacity(opacity)))
        }
    }

    private func vertical(_ r: CGRect, _ stops: [(Color, CGFloat)]) -> GraphicsContext.Shading {
        .linearGradient(Gradient(stops: stops.map { .init(color: $0.0, location: $0.1) }),
                        startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY))
    }

    private func horizontal(_ r: CGRect, _ stops: [(Color, CGFloat)]) -> GraphicsContext.Shading {
        .linearGradient(Gradient(stops: stops.map { .init(color: $0.0, location: $0.1) }),
                        startPoint: CGPoint(x: r.minX, y: r.midY), endPoint: CGPoint(x: r.maxX, y: r.midY))
    }

    /// Dark tinted glass with a sky reflection along its top.
    private func glass(_ ctx: GraphicsContext, _ shape: Path, _ r: CGRect, sheen: Double = 0.32) {
        ctx.fill(shape, with: vertical(r, [(Color(red: 0.2, green: 0.23, blue: 0.3), 0), (Color(white: 0.05), 0.55),
                                          (Color(white: 0.02), 1)]))
        var inside = ctx
        inside.clip(to: shape)
        inside.vlayer(blur: min(r.width, r.height) * 0.1) {
            $0.fill(Path(ellipseIn: CGRect(x: r.minX + r.width * 0.1, y: r.minY - r.height * 0.35,
                                           width: r.width * 0.8, height: r.height * 0.75)),
                    with: .color(.white.opacity(sheen)))
        }
        inside.stroke(shape, with: .color(.white.opacity(0.14)), lineWidth: u(0.6))
    }

    /// A fine highlight along the upper edge of a shape, drawn just inside it.
    private func rim(_ ctx: GraphicsContext, _ shape: Path, _ r: CGRect, _ strength: Double = 0.85, reach: CGFloat = 0.3) {
        var c = ctx
        c.clip(to: shape)
        c.stroke(shape, with: vertical(r, [(.white.opacity(strength), 0), (.white.opacity(0), reach)]), lineWidth: u(1.2))
    }

    private func led(_ ctx: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ color: Color, lit: Bool) {
        if lit {
            ctx.vlayer(blur: u(r * 1.6), additive: true) { $0.fill(disc(cx, cy, r * 2.6), with: .color(color.opacity(0.75))) }
            ctx.fill(disc(cx, cy, r), with: .radialGradient(Gradient(colors: [.white, color, color.opacity(0.9)]),
                                                            center: P(cx, cy), startRadius: 0, endRadius: u(r)))
        } else {
            ctx.fill(disc(cx, cy, r), with: .color(Color(white: 0.2)))
        }
    }

    /// A tyre, an aero rim and its hub, seen from the side.
    private func wheel(_ ctx: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
        ctx.fill(disc(cx, cy, r), with: .radialGradient(Gradient(colors: [Color(white: 0.16), Color(white: 0.06), Color(white: 0.02)]),
                                                        center: P(cx, cy - r * 0.3), startRadius: 0, endRadius: u(r)))
        ctx.stroke(disc(cx, cy, r - 0.4), with: vertical(R(cx - r, cy - r, r * 2, r * 2),
                                                          [(.white.opacity(0.22), 0), (.clear, 0.45)]), lineWidth: u(0.6))
        let rimR = r * 0.66
        ctx.fill(disc(cx, cy, rimR), with: .linearGradient(Gradient(colors: [Color(white: 0.9), Color(white: 0.5), Color(white: 0.22)]),
                                                           startPoint: P(cx - rimR, cy - rimR), endPoint: P(cx + rimR, cy + rimR)))
        // Aero spokes: five soft dark slots.
        var spokes = Path()
        for i in 0..<5 {
            let a = Double(i) / 5 * 2 * .pi - .pi / 2
            spokes.addEllipse(in: R(cx + cos(a) * rimR * 0.55 - rimR * 0.17, cy + sin(a) * rimR * 0.55 - rimR * 0.17,
                                    rimR * 0.34, rimR * 0.34))
        }
        ctx.fill(spokes, with: .color(Color(white: 0.12).opacity(0.85)))
        ctx.fill(disc(cx, cy, rimR * 0.22), with: .color(Color(white: 0.75)))
        ctx.stroke(disc(cx, cy, rimR), with: .color(.black.opacity(0.35)), lineWidth: u(0.4))
    }

    // MARK: Electric car

    /// A sleek fastback EV in pearl white, side on: flush handles, a light bar front and back,
    /// and a charge port that glows when the car is on.
    private func car(_ ctx: GraphicsContext) {
        ground(ctx, 50, 72.5, w: 94, h: 6)
        let body = carBody()
        let bodyRect = R(4.5, 37, 91, 28)

        // Paint: pearl white over a cooler lower body that turns away from the light.
        ctx.fill(body, with: vertical(bodyRect, [(Color(white: 0.99), 0), (Color(white: 0.93), 0.42), (Color(white: 0.8), 0.62),
                                                (Color(white: 0.6), 0.85), (Color(white: 0.42), 1)]))
        var paint = ctx
        paint.clip(to: body)
        paint.fill(Path(bodyRect), with: horizontal(bodyRect, [(.black.opacity(0.18), 0), (.clear, 0.12), (.clear, 0.88),
                                                             (.black.opacity(0.22), 1)]))
        // The shoulder crease catching the light, and the reflection of the ground below it.
        var crease = Path()
        crease.move(to: P(10, 53.4))
        crease.addCurve(to: P(91, 51.6), control1: P(36, 51.8), control2: P(66, 51))
        paint.stroke(crease, with: .color(.white.opacity(0.95)), lineWidth: u(0.8))
        paint.stroke(crease.offsetBy(dx: 0, dy: u(1)), with: .color(.black.opacity(0.08)), lineWidth: u(0.6))
        paint.vlayer(blur: u(2.6)) { $0.fill(oval(30, 49.4, 20, 2.2), with: .color(.white.opacity(0.9))) }
        // A dark sill and lower valance.
        paint.fill(Path(R(4, 61.8, 92, 5)), with: vertical(R(4, 61.8, 92, 5), [(Color(white: 0.16), 0), (Color(white: 0.06), 1)]))

        // Wheel arches, cut into the paint.
        for x in [24, 76] as [CGFloat] {
            paint.fill(disc(x, 63.2, 10.4), with: .color(Color(white: 0.05)))
            paint.stroke(disc(x, 63.2, 10.4), with: vertical(R(x - 10.4, 52.8, 20.8, 20.8), [(.black.opacity(0.4), 0), (.clear, 0.5)]),
                         lineWidth: u(0.8))
        }

        // The glasshouse: one dark sweep from the windscreen to the tail.
        let glassShape = cabin()
        glass(ctx, glassShape, R(39, 38.8, 48, 9))
        // B-pillar, hidden in the glass.
        ctx.fill(Path(R(59.2, 39, 1.2, 8.6)), with: .color(Color(white: 0.03)))
        // The glass roof catching the sky.
        var roof = ctx
        roof.clip(to: glassShape)
        roof.vlayer(blur: u(1)) { $0.fill(oval(60, 39.6, 10, 0.9), with: .color(.white.opacity(0.5))) }

        // Door shut lines and flush handles.
        var seams = Path()
        seams.move(to: P(40.6, 48.2)); seams.addLine(to: P(41.6, 61.6))
        seams.move(to: P(60, 48)); seams.addLine(to: P(60.3, 61.6))
        ctx.stroke(seams, with: .color(.black.opacity(0.22)), lineWidth: u(0.45))
        for x in [48, 65] as [CGFloat] {
            ctx.fill(Path(roundedRect: R(x, 50.4, 5.6, 1), cornerRadius: u(0.5)), with: .color(Color(white: 0.6)))
        }
        // Mirror.
        ctx.fill(Path(roundedRect: R(37.6, 45.6, 4, 2.2), cornerRadius: u(1.1)), with: .color(Color(white: 0.12)))

        // Lights: a thin white bar at the front, a red bar across the tail.
        let head = Path(roundedRect: R(5.6, 52, 10, 1.3), cornerRadius: u(0.65))
        let tail = Path(roundedRect: R(88, 48.4, 7.2, 1.3), cornerRadius: u(0.65))
        let red = Color(red: 1, green: 0.22, blue: 0.2)
        if on {
            ctx.vlayer(blur: u(2.4), additive: true) { $0.fill(head, with: .color(.white.opacity(0.8))) }
            ctx.vlayer(blur: u(2.2), additive: true) { $0.fill(tail, with: .color(red.opacity(0.8))) }
        }
        ctx.fill(head, with: .color(on ? .white : Color(white: 0.45)))
        ctx.fill(tail, with: .color(on ? red : Color(red: 0.35, green: 0.1, blue: 0.1)))

        // The charge port on the rear quarter.
        ctx.fill(Path(roundedRect: R(83.4, 51.6, 3.4, 2.4), cornerRadius: u(0.9)), with: .color(Color(white: 0.2)))
        led(ctx, 85.1, 52.8, 0.8, glow, lit: on)

        wheel(ctx, 24, 63.2, 8.6)
        wheel(ctx, 76, 63.2, 8.6)
        rim(ctx, body, bodyRect, 0.9, reach: 0.22)
    }

    private func carBody() -> Path {
        var p = Path()
        p.move(to: P(9, 65))
        p.addCurve(to: P(4.6, 56), control1: P(5.6, 64), control2: P(4.4, 59.6))
        p.addCurve(to: P(14, 50.4), control1: P(4.8, 52.6), control2: P(8, 50.8))
        p.addCurve(to: P(38, 47.2), control1: P(22, 49.6), control2: P(32, 48.4))
        p.addCurve(to: P(55, 37.6), control1: P(43, 43.4), control2: P(48.6, 38.2))
        p.addCurve(to: P(69, 38.4), control1: P(60, 37.1), control2: P(65, 37.4))
        p.addCurve(to: P(92, 46.6), control1: P(77, 40.4), control2: P(86, 43.6))
        p.addCurve(to: P(95.4, 53), control1: P(94.4, 47.8), control2: P(95.4, 50))
        p.addCurve(to: P(92, 65), control1: P(95.4, 57.6), control2: P(94.4, 63.6))
        p.closeSubpath()
        return p
    }

    private func cabin() -> Path {
        var p = Path()
        p.move(to: P(39.6, 47.6))
        p.addCurve(to: P(55.4, 39.3), control1: P(44.6, 43.8), control2: P(49.6, 39.8))
        p.addCurve(to: P(68.6, 40), control1: P(60.2, 38.9), control2: P(65, 39.1))
        p.addCurve(to: P(86.6, 46.6), control1: P(75, 41.6), control2: P(81.6, 44.2))
        p.addCurve(to: P(39.6, 47.6), control1: P(70, 47.4), control2: P(52, 47.8))
        p.closeSubpath()
        return p
    }

    // MARK: Car charger

    /// A wall box: a satin body with a dark glass face and a light strip, its cable looping
    /// down to a holster.
    private func charger(_ ctx: GraphicsContext) {
        // The wall it hangs on, as a soft contact shadow.
        ctx.vlayer(blur: u(4)) {
            $0.fill(Path(roundedRect: R(29, 20, 40, 52), cornerRadius: u(10)), with: .color(.black.opacity(0.7)))
        }
        // The cable: from under the box, down and around into the holster.
        var cable = Path()
        cable.move(to: P(48, 70))
        cable.addCurve(to: P(78, 70), control1: P(48, 92), control2: P(76, 92))
        cable.addLine(to: P(78, 58))
        ctx.stroke(cable, with: .color(Color(white: 0.06)), style: StrokeStyle(lineWidth: u(3.4), lineCap: .round))
        ctx.stroke(cable.offsetBy(dx: -u(0.5), dy: -u(0.6)), with: .color(.white.opacity(0.12)),
                   style: StrokeStyle(lineWidth: u(0.8), lineCap: .round))
        // Holster and plug.
        let holster = Path(roundedRect: R(74.5, 44, 7, 15), cornerRadius: u(3))
        ctx.fill(holster, with: horizontal(R(74.5, 44, 7, 15), [(Color(white: 0.7), 0), (Color(white: 0.95), 0.4), (Color(white: 0.55), 1)]))

        let r = R(27, 16, 42, 56)
        let body = Path(roundedRect: r, cornerRadius: u(11), style: .continuous)
        ctx.fill(body, with: vertical(r, [(Color(white: 0.99), 0), (Color(white: 0.9), 0.5), (Color(white: 0.72), 1)]))
        var inside = ctx
        inside.clip(to: body)
        inside.fill(Path(r), with: horizontal(r, [(.black.opacity(0.16), 0), (.clear, 0.16), (.clear, 0.84), (.black.opacity(0.2), 1)]))
        inside.vlayer(blur: u(3)) { $0.fill(oval(44, 20, 14, 4), with: .color(.white.opacity(0.85))) }
        rim(ctx, body, r, 0.95, reach: 0.15)

        // The glass face and its light strip.
        let faceRect = R(33, 24, 30, 36)
        let face = Path(roundedRect: faceRect, cornerRadius: u(7), style: .continuous)
        glass(ctx, face, faceRect, sheen: 0.22)
        let strip = Path(roundedRect: R(46.6, 31, 2.8, 22), cornerRadius: u(1.4))
        if on {
            ctx.vlayer(blur: u(3.4), additive: true) { $0.fill(strip, with: .color(glow.opacity(0.9))) }
            ctx.fill(strip, with: vertical(R(46.6, 31, 2.8, 22), [(.white, 0), (glow, 0.5), (.white, 1)]))
        } else {
            ctx.fill(strip, with: .color(Color(white: 0.25)))
        }
    }

    // MARK: Robot vacuum

    /// A round robot vacuum seen from a little above: a gloss top, a raised lidar turret,
    /// a front bumper and a status light.
    private func vacuum(_ ctx: GraphicsContext) {
        ground(ctx, 50, 72, w: 86, h: 10)
        let cx: CGFloat = 50, rx: CGFloat = 41, ry: CGFloat = 19, top: CGFloat = 50, depth: CGFloat = 9

        // The side wall: the lower ellipse joined to the top one.
        var side = Path(ellipseIn: R(cx - rx, top + depth - ry, rx * 2, ry * 2))
        side.addRect(R(cx - rx, top, rx * 2, depth))
        let sideRect = R(cx - rx, top, rx * 2, depth + ry)
        ctx.fill(side, with: horizontal(sideRect, [(Color(white: 0.08), 0), (Color(white: 0.28), 0.3), (Color(white: 0.34), 0.5),
                                                 (Color(white: 0.2), 0.8), (Color(white: 0.06), 1)]))
        // The bumper: a lighter band around the front.
        var bumper = ctx
        bumper.clip(to: side)
        bumper.fill(Path(R(cx - rx, top + 3, rx * 2, 3)), with: .color(.white.opacity(0.08)))

        // The top: deep gloss, with a broad reflection.
        let topShape = oval(cx, top, rx, ry)
        let topRect = R(cx - rx, top - ry, rx * 2, ry * 2)
        ctx.fill(topShape, with: vertical(topRect, [(Color(white: 0.36), 0), (Color(white: 0.16), 0.5), (Color(white: 0.08), 1)]))
        var surface = ctx
        surface.clip(to: topShape)
        surface.vlayer(blur: u(4)) { $0.fill(oval(40, 37, 24, 5), with: .color(.white.opacity(0.42))) }
        surface.stroke(oval(cx, top, rx - 6, ry - 3), with: .color(.white.opacity(0.06)), lineWidth: u(0.5))
        ctx.stroke(topShape, with: vertical(topRect, [(.white.opacity(0.45), 0), (.white.opacity(0.05), 0.5), (.white.opacity(0.12), 1)]),
                   lineWidth: u(0.7))

        // The lidar turret, towards the back.
        let tx: CGFloat = 50, ty: CGFloat = 41, trx: CGFloat = 9, tr: CGFloat = 3.6, th: CGFloat = 4.4
        var turret = Path(ellipseIn: R(tx - trx, ty + th - tr, trx * 2, tr * 2))
        turret.addRect(R(tx - trx, ty, trx * 2, th))
        ctx.fill(turret, with: horizontal(R(tx - trx, ty, trx * 2, th), [(Color(white: 0.55), 0), (Color(white: 0.92), 0.4),
                                                                       (Color(white: 0.5), 1)]))
        ctx.fill(oval(tx, ty, trx, tr), with: vertical(R(tx - trx, ty - tr, trx * 2, tr * 2), [(.white, 0), (Color(white: 0.8), 1)]))
        // The lidar window.
        ctx.fill(Path(R(tx - 5, ty + 1.6, 10, 1.6)), with: .color(Color(white: 0.08)))

        // A control button and the status light at the front.
        ctx.fill(oval(50, 56, 4.6, 2), with: .color(Color(white: 0.16)))
        ctx.stroke(oval(50, 56, 4.6, 2), with: .color(.white.opacity(0.2)), lineWidth: u(0.4))
        led(ctx, 50, 56, 0.9, glow, lit: on)
    }

    // MARK: Robot mower

    /// A robot lawn mower side on: a domed, sculpted shell riding low between a big rear
    /// wheel and a small front one, a red stop button on top, standing in the grass it cuts.
    private func mower(_ ctx: GraphicsContext) {
        ground(ctx, 50, 72, w: 80, h: 6)
        let green = Color(red: 0.36, green: 0.62, blue: 0.3)

        // Grass behind.
        blades(ctx, [(10, 10, -2), (16, 7, 1.5), (84, 11, 2), (90, 8, -1.5), (95, 6, 1)], green.opacity(on ? 0.75 : 0.4))

        // Wheels: the big drive wheel at the back, a small caster at the front.
        wheel(ctx, 68, 62, 10.5)
        wheel(ctx, 27, 66, 5.6)

        // The shell: a low dome, lifted at the back over the wheel, a short snout at the front.
        var shell = Path()
        shell.move(to: P(12, 63))
        shell.addCurve(to: P(22, 49), control1: P(11, 57), control2: P(15, 51))
        shell.addCurve(to: P(56, 35), control1: P(30, 42), control2: P(42, 35.4))
        shell.addCurve(to: P(86, 47), control1: P(70, 34.6), control2: P(82, 39))
        shell.addCurve(to: P(88, 60), control1: P(89, 51), control2: P(89.6, 57))
        shell.addCurve(to: P(80, 60.6), control1: P(86, 61.4), control2: P(83, 61.4))
        // The arch over the drive wheel.
        shell.addCurve(to: P(56, 60.6), control1: P(77, 47.6), control2: P(59, 47.6))
        shell.addLine(to: P(16, 64.4))
        shell.addCurve(to: P(12, 63), control1: P(14, 64.6), control2: P(12.4, 64))
        shell.closeSubpath()
        let r = R(11, 35, 79, 30)
        ctx.fill(shell, with: vertical(r, [(Color(white: 0.62), 0), (Color(white: 0.46), 0.35), (Color(white: 0.26), 0.75),
                                          (Color(white: 0.16), 1)]))
        var inside = ctx
        inside.clip(to: shell)
        inside.fill(Path(r), with: horizontal(r, [(.black.opacity(0.28), 0), (.clear, 0.22), (.clear, 0.8), (.black.opacity(0.3), 1)]))
        inside.vlayer(blur: u(3)) { $0.fill(oval(50, 40, 22, 3.4), with: .color(.white.opacity(0.6))) }
        // A dark lower skirt, so the shell reads as a cover over the cutting deck.
        inside.fill(Path(R(10, 57, 80, 10)), with: vertical(R(10, 57, 80, 10), [(Color(white: 0.1), 0), (Color(white: 0.04), 1)]))
        rim(ctx, shell, r, 0.85, reach: 0.22)

        // The control panel and the red stop button on top.
        ctx.fill(Path(roundedRect: R(42, 34.2, 16, 3), cornerRadius: u(1.5)), with: .color(Color(white: 0.07)))
        ctx.fill(oval(62.5, 35.6, 4, 1.7), with: .color(Color(red: 0.88, green: 0.17, blue: 0.14)))
        ctx.fill(oval(62.2, 35.1, 2.6, 0.7), with: .color(.white.opacity(0.35)))
        led(ctx, 46, 35.7, 0.7, glow, lit: on)

        // Grass in front, over the wheels' feet.
        blades(ctx, [(22, 6, 1), (34, 8, -1.5), (40, 5, 1), (52, 7, 1.5), (60, 5, -1), (76, 6, 1), (44, 9, -2)],
               green.opacity(on ? 0.95 : 0.5))
    }

    private func blades(_ ctx: GraphicsContext, _ list: [(CGFloat, CGFloat, CGFloat)], _ color: Color) {
        var grass = Path()
        for (x, h, lean) in list {
            grass.move(to: P(x - 1, 72))
            grass.addQuadCurve(to: P(x + lean, 72 - h), control: P(x - 0.6, 72 - h * 0.6))
            grass.addQuadCurve(to: P(x + 1, 72), control: P(x + 0.4, 72 - h * 0.5))
        }
        ctx.fill(grass, with: .color(color))
    }

    // MARK: Aircraft

    /// A small electric business jet side on: a long white fuselage, a row of windows lit
    /// from inside, engines at the tail and a T-tail fin.
    private func aircraft(_ ctx: GraphicsContext) {
        ground(ctx, 52, 78, w: 70, h: 5, opacity: 0.55)
        // Far wing, behind the fuselage.
        var farWing = Path()
        farWing.move(to: P(42, 52)); farWing.addLine(to: P(60, 44)); farWing.addLine(to: P(66, 44)); farWing.addLine(to: P(58, 52))
        farWing.closeSubpath()
        ctx.fill(farWing, with: .color(Color(white: 0.55)))

        // The fin and its T-tail.
        var fin = Path()
        fin.move(to: P(76, 46)); fin.addLine(to: P(84, 22)); fin.addLine(to: P(91, 22)); fin.addLine(to: P(92, 46)); fin.closeSubpath()
        ctx.fill(fin, with: horizontal(R(76, 22, 16, 24), [(Color(white: 0.78), 0), (Color(white: 0.97), 0.5), (Color(white: 0.8), 1)]))
        ctx.fill(Path(roundedRect: R(80, 20.5, 16, 2.6), cornerRadius: u(1.3)), with: .color(Color(white: 0.85)))

        // Fuselage: a long tapered capsule, nose to the left.
        var hull = Path()
        hull.move(to: P(6, 55))
        hull.addCurve(to: P(22, 46), control1: P(7, 50), control2: P(13, 46.2))
        hull.addLine(to: P(80, 45.4))
        hull.addCurve(to: P(95, 49), control1: P(88, 45.4), control2: P(94, 46.6))
        hull.addCurve(to: P(82, 57.4), control1: P(95, 53), control2: P(90, 57.2))
        hull.addLine(to: P(20, 58.6))
        hull.addCurve(to: P(6, 55), control1: P(12, 58.6), control2: P(7, 57.4))
        hull.closeSubpath()
        let r = R(6, 45, 89, 14)
        ctx.fill(hull, with: vertical(r, [(Color(white: 1), 0), (Color(white: 0.94), 0.4), (Color(white: 0.72), 0.85), (Color(white: 0.55), 1)]))
        var paint = ctx
        paint.clip(to: hull)
        paint.fill(Path(R(6, 54, 89, 1.6)), with: .color(glow.opacity(on ? 0.75 : 0.3)))
        rim(ctx, hull, r, 0.95, reach: 0.25)

        // Cockpit glass and cabin windows.
        var cockpit = Path()
        cockpit.move(to: P(11.5, 49.6)); cockpit.addQuadCurve(to: P(19, 47.2), control: P(14, 47.6))
        cockpit.addLine(to: P(20, 50.4)); cockpit.addLine(to: P(12, 51)); cockpit.closeSubpath()
        ctx.fill(cockpit, with: .color(Color(white: 0.1)))
        for i in 0..<6 {
            let w = Path(roundedRect: R(28 + CGFloat(i) * 6.2, 48.6, 2.6, 2.6), cornerRadius: u(1.3))
            ctx.fill(w, with: .color(on ? Color(red: 1, green: 0.86, blue: 0.62) : Color(white: 0.15)))
            if on { ctx.vlayer(blur: u(0.6), additive: true) { $0.fill(w, with: .color(Color(red: 1, green: 0.78, blue: 0.45).opacity(0.35))) } }
        }

        // Engine pod by the tail, and the near wing.
        let pod = Path(roundedRect: R(66, 41.5, 15, 6), cornerRadius: u(3))
        ctx.fill(pod, with: vertical(R(66, 41.5, 15, 6), [(Color(white: 0.95), 0), (Color(white: 0.6), 1)]))
        ctx.fill(Path(roundedRect: R(65.4, 42.3, 2, 4.4), cornerRadius: u(1)), with: .color(Color(white: 0.12)))
        var wing = Path()
        wing.move(to: P(36, 55.5)); wing.addLine(to: P(56, 55)); wing.addLine(to: P(70, 67)); wing.addLine(to: P(63, 67)); wing.closeSubpath()
        ctx.fill(wing, with: vertical(R(36, 55, 34, 12), [(Color(white: 0.9), 0), (Color(white: 0.62), 1)]))

        // Navigation light at the wing tip.
        led(ctx, 66.5, 66.6, 0.9, Color(red: 0.3, green: 1, blue: 0.5), lit: on)
    }

    // MARK: Robot

    /// A friendly companion robot: a rounded white head with a dark visor and two glowing
    /// eyes, an antenna, and a small body.
    private func robot(_ ctx: GraphicsContext) {
        ground(ctx, 50, 85, w: 50, h: 6)
        // Body.
        let bodyRect = R(31, 58, 38, 25)
        let body = Path(roundedRect: bodyRect, cornerRadius: u(12), style: .continuous)
        ctx.fill(body, with: vertical(bodyRect, [(Color(white: 0.96), 0), (Color(white: 0.84), 0.5), (Color(white: 0.6), 1)]))
        var b = ctx
        b.clip(to: body)
        b.fill(Path(bodyRect), with: horizontal(bodyRect, [(.black.opacity(0.18), 0), (.clear, 0.2), (.clear, 0.8), (.black.opacity(0.22), 1)]))
        led(ctx, 50, 69, 1.4, glow, lit: on)
        // Neck.
        ctx.fill(Path(R(45, 54, 10, 5)), with: .color(Color(white: 0.3)))

        // Antenna.
        var stalk = Path()
        stalk.move(to: P(50, 22)); stalk.addLine(to: P(50, 15))
        ctx.stroke(stalk, with: .color(Color(white: 0.6)), style: StrokeStyle(lineWidth: u(1.4), lineCap: .round))
        led(ctx, 50, 13.5, 2, glow, lit: on)

        // Head.
        let headRect = R(24, 21, 52, 35)
        let head = Path(roundedRect: headRect, cornerRadius: u(16), style: .continuous)
        ctx.fill(head, with: vertical(headRect, [(Color(white: 1), 0), (Color(white: 0.9), 0.5), (Color(white: 0.7), 1)]))
        var h = ctx
        h.clip(to: head)
        h.fill(Path(headRect), with: horizontal(headRect, [(.black.opacity(0.16), 0), (.clear, 0.18), (.clear, 0.82), (.black.opacity(0.2), 1)]))
        h.vlayer(blur: u(3)) { $0.fill(oval(44, 25, 16, 4), with: .color(.white.opacity(0.9))) }
        rim(ctx, head, headRect, 0.95, reach: 0.18)
        // Ears.
        for x in [21.5, 78.5] as [CGFloat] {
            ctx.fill(Path(roundedRect: R(x - 2.5, 33, 5, 11), cornerRadius: u(2.5)), with: .color(Color(white: 0.55)))
        }

        // Visor and eyes.
        let visorRect = R(30, 29, 40, 19)
        let visor = Path(roundedRect: visorRect, cornerRadius: u(9.5), style: .continuous)
        glass(ctx, visor, visorRect, sheen: 0.25)
        for x in [41, 59] as [CGFloat] {
            let eye = Path(roundedRect: R(x - 3, 34, 6, 8.5), cornerRadius: u(3))
            if on {
                ctx.vlayer(blur: u(2.6), additive: true) { $0.fill(eye, with: .color(glow.opacity(0.9))) }
                ctx.fill(eye, with: vertical(R(x - 3, 34, 6, 8.5), [(.white, 0), (glow, 1)]))
            } else {
                ctx.fill(eye, with: .color(Color(white: 0.22)))
            }
        }
    }
}

private extension GraphicsContext {
    /// Draws into a copy of the context, through a blur and blend of its own.
    func vlayer(blur: CGFloat = 0, additive: Bool = false, _ draw: (inout GraphicsContext) -> Void) {
        var c = self
        if blur > 0 { c.addFilter(.blur(radius: blur)) }
        if additive { c.blendMode = .plusLighter }
        draw(&c)
    }
}
