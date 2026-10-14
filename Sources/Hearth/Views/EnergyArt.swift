import SwiftUI

/// The home energy kit, drawn the same way as `DeviceArt`: a wall-mounted hybrid inverter,
/// a lithium battery and a solar panel. Generic archetypes, never a particular brand.
/// All geometry is laid out on a 100 by 100 grid and scaled to the view.
struct EnergyArt {
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
    private func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
        Path(roundedRect: R(x, y, w, h), cornerRadius: u(r), style: .continuous)
    }

    func draw(_ ctx: GraphicsContext) {
        switch kind {
        case .inverter: inverter(ctx)
        case .battery: battery(ctx)
        case .solarPanel: solarPanel(ctx)
        default: break
        }
    }

    // MARK: Materials

    private func vertical(_ r: CGRect, _ stops: [(Color, CGFloat)]) -> GraphicsContext.Shading {
        .linearGradient(Gradient(stops: stops.map { .init(color: $0.0, location: $0.1) }),
                        startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY))
    }

    private func horizontal(_ r: CGRect, _ stops: [(Color, CGFloat)]) -> GraphicsContext.Shading {
        .linearGradient(Gradient(stops: stops.map { .init(color: $0.0, location: $0.1) }),
                        startPoint: CGPoint(x: r.minX, y: r.midY), endPoint: CGPoint(x: r.maxX, y: r.midY))
    }

    /// A soft cast shadow under something standing on a surface.
    private func ground(_ ctx: GraphicsContext, _ cx: CGFloat, _ y: CGFloat, w: CGFloat, h: CGFloat, opacity: Double = 0.85) {
        ctx.energyLayer(blur: u(h * 0.55)) { $0.fill(oval(cx, y, w / 2, h / 2), with: .color(.black.opacity(opacity))) }
        ctx.energyLayer(blur: u(max(h * 0.14, 0.6))) {
            $0.fill(oval(cx, y - h * 0.08, w * 0.36, h * 0.16), with: .color(.black.opacity(opacity)))
        }
    }

    /// The soft shadow a box hung on a wall throws behind and below itself.
    private func wallShadow(_ ctx: GraphicsContext, _ shape: Path) {
        ctx.energyLayer(blur: u(4)) { $0.fill(shape.offsetBy(dx: u(1.2), dy: u(3.2)), with: .color(.black.opacity(0.75))) }
        ctx.energyLayer(blur: u(1)) { $0.fill(shape.offsetBy(dx: 0, dy: u(0.9)), with: .color(.black.opacity(0.6))) }
    }

    /// Satin plastic lit from above, its sides turning away from the light, with a broad
    /// soft reflection along the top.
    private func satin(_ ctx: GraphicsContext, _ shape: Path, _ r: CGRect, light: Double, dark: Double,
                       turn: CGFloat = 0.12, gloss: Double = 0.6) {
        ctx.fill(shape, with: vertical(r, [(Color(white: light), 0), (Color(white: light - 0.03), 0.4),
                                          (Color(white: dark + (light - dark) * 0.45), 0.8), (Color(white: dark), 1)]))
        var inside = ctx
        inside.clip(to: shape)
        inside.fill(Path(r), with: horizontal(r, [(.black.opacity(0.18), 0), (.clear, turn), (.clear, 1 - turn),
                                                  (.black.opacity(0.24), 1)]))
        if gloss > 0 {
            inside.energyLayer(blur: min(r.width, r.height) * 0.1) {
                $0.fill(Path(ellipseIn: CGRect(x: r.minX + r.width * 0.12, y: r.minY - r.height * 0.07,
                                               width: r.width * 0.76, height: r.height * 0.26)),
                        with: .color(.white.opacity(gloss)))
            }
        }
    }

    /// A fine highlight along the upper edge of a shape, drawn just inside it.
    private func rim(_ ctx: GraphicsContext, _ shape: Path, _ r: CGRect, _ strength: Double = 0.85, reach: CGFloat = 0.3) {
        var c = ctx
        c.clip(to: shape)
        c.stroke(shape, with: vertical(r, [(.white.opacity(strength), 0), (.white.opacity(0), reach)]), lineWidth: u(1.2))
    }

    /// An indicator: a hot core and a halo when lit, a dark bead when not.
    private func led(_ ctx: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ color: Color, lit: Bool) {
        if lit {
            ctx.energyLayer(blur: u(r * 1.5), additive: true) { $0.fill(disc(cx, cy, r * 2.4), with: .color(color.opacity(0.7))) }
            ctx.fill(disc(cx, cy, r), with: .radialGradient(Gradient(colors: [.white, color, color.opacity(0.9)]),
                                                            center: P(cx, cy), startRadius: 0, endRadius: u(r)))
        } else {
            ctx.fill(disc(cx, cy, r), with: .color(Color(white: 0.22)))
            ctx.fill(disc(cx - r * 0.3, cy - r * 0.3, r * 0.35), with: .color(.white.opacity(0.22)))
        }
    }

    // MARK: Inverter

    /// A wall-mounted hybrid inverter: a pale satin case with a dark glass display that
    /// shows the power flowing, a row of status lights, and cable glands underneath.
    private func inverter(_ ctx: GraphicsContext) {
        let x: CGFloat = 23, y: CGFloat = 10, w: CGFloat = 54, h: CGFloat = 74
        let body = rounded(x, y, w, h, 7)
        let bodyRect = R(x, y, w, h)
        wallShadow(ctx, body)

        // Heat sink fins showing past the right edge, in the case's shadow.
        for i in 0..<6 {
            let fy = y + 10 + CGFloat(i) * 9.5
            ctx.fill(rounded(x + w - 1.2, fy, 3.2, 6.2, 1.2), with: .color(Color(white: 0.34)))
            ctx.fill(rounded(x + w - 1.2, fy, 3.2, 1.2, 0.6), with: .color(Color(white: 0.55)))
        }

        satin(ctx, body, bodyRect, light: 0.95, dark: 0.74, gloss: 0.55)
        rim(ctx, body, bodyRect)

        // A slightly recessed front panel, so the case reads as a lid on a box.
        let panel = rounded(x + 4, y + 5, w - 8, h - 17, 4.5)
        let panelRect = R(x + 4, y + 5, w - 8, h - 17)
        ctx.fill(panel, with: vertical(panelRect, [(Color(white: 0.9), 0), (Color(white: 0.86), 1)]))
        ctx.stroke(panel, with: vertical(panelRect, [(.black.opacity(0.18), 0), (.white.opacity(0.6), 1)]), lineWidth: u(0.5))

        // The display: dark glass with a small live readout.
        let screenRect = R(x + 10, y + 12, w - 20, 21)
        let screen = Path(roundedRect: screenRect, cornerRadius: u(2.6), style: .continuous)
        ctx.fill(screen, with: vertical(screenRect, [(Color(white: 0.16), 0), (Color(white: 0.04), 0.5), (Color(white: 0.08), 1)]))
        var lcd = ctx
        lcd.clip(to: screen)
        if on {
            let c = glow
            lcd.energyLayer(blur: u(3), additive: true) {
                $0.fill(Path(screenRect.insetBy(dx: u(2), dy: u(2))), with: .color(c.opacity(0.18)))
            }
            // A sun, an arrow and a bar for the battery: the power flow, in a few strokes.
            lcd.stroke(disc(x + 16, y + 19.5, 2.2), with: .color(c), lineWidth: u(0.8))
            for a in stride(from: 0.0, to: 360.0, by: 60.0) {
                let r = a * .pi / 180
                var ray = Path()
                ray.move(to: P(x + 16 + 3.3 * CGFloat(cos(r)), y + 19.5 + 3.3 * CGFloat(sin(r))))
                ray.addLine(to: P(x + 16 + 4.4 * CGFloat(cos(r)), y + 19.5 + 4.4 * CGFloat(sin(r))))
                lcd.stroke(ray, with: .color(c.opacity(0.9)), lineWidth: u(0.6))
            }
            var arrow = Path()
            arrow.move(to: P(x + 22.5, y + 19.5))
            arrow.addLine(to: P(x + 29.5, y + 19.5))
            arrow.move(to: P(x + 27.5, y + 17.8))
            arrow.addLine(to: P(x + 29.5, y + 19.5))
            arrow.addLine(to: P(x + 27.5, y + 21.2))
            lcd.stroke(arrow, with: .color(c.opacity(0.85)), style: StrokeStyle(lineWidth: u(0.7), lineCap: .round, lineJoin: .round))
            lcd.stroke(rounded(x + 32, y + 16.6, 8.5, 5.8, 1), with: .color(c), lineWidth: u(0.7))
            lcd.fill(rounded(x + 33.2, y + 17.8, 5, 3.4, 0.5), with: .color(c.opacity(0.9)))
            // Two lines of figures.
            lcd.fill(rounded(x + 13, y + 26.4, 14, 1.6, 0.8), with: .color(c.opacity(0.75)))
            lcd.fill(rounded(x + 29, y + 26.4, 8, 1.6, 0.8), with: .color(c.opacity(0.45)))
        }
        lcd.energyLayer(blur: u(1.5)) {
            $0.fill(Path(ellipseIn: CGRect(x: screenRect.minX - u(4), y: screenRect.minY - u(9),
                                           width: screenRect.width * 0.8, height: u(14))),
                    with: .color(.white.opacity(0.16)))
        }
        ctx.stroke(screen, with: vertical(screenRect, [(.black.opacity(0.5), 0), (.white.opacity(0.35), 1)]), lineWidth: u(0.5))

        // Status lights: grid, solar, battery, fault.
        let lights: [(Color, Bool)] = [(Color(red: 0.45, green: 0.95, blue: 0.6), on), (Color(red: 1, green: 0.8, blue: 0.35), on),
                                       (Color(red: 0.45, green: 0.95, blue: 0.6), on), (Color(red: 1, green: 0.35, blue: 0.3), false)]
        for (i, light) in lights.enumerated() {
            led(ctx, x + 17 + CGFloat(i) * 6.7, y + 41, 1.1, light.0, lit: light.1)
        }
        // A single soft key, and the vent slots of the lower panel.
        ctx.fill(rounded(x + 19, y + 48, 16, 2.2, 1.1), with: .color(Color(white: 0.78)))
        for i in 0..<3 {
            ctx.fill(rounded(x + 12, y + 53.6 + CGFloat(i) * 2.4, w - 24, 0.9, 0.45), with: .color(Color(white: 0.7)))
        }

        // The underside: a darker band with cable glands and their cables dropping away.
        let base = rounded(x + 3, y + h - 9, w - 6, 6.5, 3)
        ctx.fill(base, with: vertical(R(x, y + h - 9, w, 6.5), [(Color(white: 0.58), 0), (Color(white: 0.4), 1)]))
        // Glands only: short stubs that fade, so the cables never read as legs.
        for i in 0..<4 {
            let gx = x + 14 + CGFloat(i) * 8.7
            ctx.fill(rounded(gx - 2, y + h - 3, 4, 3.6, 1.1), with: .color(Color(white: 0.14)))
            ctx.fill(rounded(gx - 1.2, y + h + 0.4, 2.4, 3.4, 1.2),
                     with: vertical(R(gx - 1.2, y + h + 0.4, 2.4, 3.4), [(Color(white: 0.2), 0), (Color(white: 0.1).opacity(0), 1)]))
        }
    }

    // MARK: Battery

    /// A floor-standing lithium battery: a graphite case with a brushed front, carry slots
    /// in the top, and a column of charge lights.
    private func battery(_ ctx: GraphicsContext) {
        let x: CGFloat = 27, y: CGFloat = 13, w: CGFloat = 46, h: CGFloat = 74
        ground(ctx, 50, y + h - 0.5, w: w + 12, h: 7, opacity: 0.9)
        let body = rounded(x, y, w, h, 6)
        let bodyRect = R(x, y, w, h)
        satin(ctx, body, bodyRect, light: 0.34, dark: 0.13, turn: 0.1, gloss: 0.32)
        rim(ctx, body, bodyRect, 0.55)

        // The front plate, a shade lighter, with a brushed grain.
        let front = rounded(x + 3.5, y + 9, w - 7, h - 13, 3.5)
        let frontRect = R(x + 3.5, y + 9, w - 7, h - 13)
        ctx.fill(front, with: vertical(frontRect, [(Color(white: 0.27), 0), (Color(white: 0.19), 1)]))
        var plate = ctx
        plate.clip(to: front)
        for i in 0..<18 {
            let ly = y + 10 + CGFloat(i) * 3.6
            plate.fill(Path(R(x + 3.5, ly, w - 7, 0.35)), with: .color(.white.opacity(0.025)))
        }
        plate.energyLayer(blur: u(3)) {
            $0.fill(Path(ellipseIn: R(x + 2, y + 4, w * 0.6, 14)), with: .color(.white.opacity(0.1)))
        }
        ctx.stroke(front, with: vertical(frontRect, [(.black.opacity(0.5), 0), (.white.opacity(0.14), 1)]), lineWidth: u(0.5))

        // Carry slots in the top.
        for sx in [x + 9, x + w - 19] as [CGFloat] {
            ctx.fill(rounded(sx, y + 3, 10, 2.6, 1.3), with: .color(Color(white: 0.04)))
            ctx.stroke(rounded(sx, y + 3.5, 10, 2.6, 1.3), with: .color(.white.opacity(0.14)), lineWidth: u(0.3))
        }

        // Charge lights: five segments, four lit when on.
        let barX = x + w - 13
        let level = on ? 4 : 0
        for i in 0..<5 {
            let segY = y + 50 - CGFloat(i) * 7
            let seg = rounded(barX, segY, 4.2, 5, 1.4)
            if i < level {
                let c = glow
                ctx.energyLayer(blur: u(2.4), additive: true) { $0.fill(seg, with: .color(c.opacity(0.65))) }
                ctx.fill(seg, with: vertical(R(barX, segY, 4.2, 5), [(.white, 0), (c, 0.55), (c.opacity(0.9), 1)]))
            } else {
                ctx.fill(seg, with: .color(Color(white: 0.1)))
                ctx.stroke(seg, with: .color(.white.opacity(0.08)), lineWidth: u(0.3))
            }
        }

        // A lightning mark and the power button.
        var bolt = Path()
        bolt.move(to: P(x + 15.5, y + 26))
        bolt.addLine(to: P(x + 11.5, y + 34))
        bolt.addLine(to: P(x + 14.5, y + 34))
        bolt.addLine(to: P(x + 12.5, y + 41))
        bolt.addLine(to: P(x + 18.5, y + 31.5))
        bolt.addLine(to: P(x + 15.2, y + 31.5))
        bolt.closeSubpath()
        ctx.fill(bolt, with: .color(Color(white: on ? 0.82 : 0.5)))
        let button = disc(x + 15, y + 60, 3.6)
        ctx.fill(button, with: .radialGradient(Gradient(colors: [Color(white: 0.3), Color(white: 0.12)]),
                                               center: P(x + 14, y + 58.8), startRadius: 0, endRadius: u(4)))
        ctx.stroke(disc(x + 15, y + 60, 3.6), with: .color(.white.opacity(0.18)), lineWidth: u(0.35))
        if on {
            let c = glow
            ctx.energyLayer(blur: u(1.2), additive: true) {
                $0.stroke(disc(x + 15, y + 60, 2.3), with: .color(c.opacity(0.8)), lineWidth: u(0.8))
            }
        }
        ctx.stroke(disc(x + 15, y + 60, 2.3), with: .color(on ? .white.opacity(0.9) : Color(white: 0.45)), lineWidth: u(0.45))

        // Two terminals on a lower bar.
        ctx.fill(rounded(x + 6, y + h - 6.5, w - 12, 3, 1.5), with: .color(Color(white: 0.08)))
        ctx.fill(disc(x + 14, y + h - 5, 1), with: .color(Color(red: 0.8, green: 0.22, blue: 0.2)))
        ctx.fill(disc(x + w - 14, y + h - 5, 1), with: .color(Color(white: 0.5)))
    }

    // MARK: Solar panel

    /// A solar panel tilted towards the sky on a ground frame: deep blue cells in a fine
    /// grid behind glass, an aluminium frame, and the sky caught across the glass.
    private func solarPanel(_ ctx: GraphicsContext) {
        // Corners of the panel's top face, seen from a little above and to the side.
        let tl = CGPoint(x: 19, y: 18), tr = CGPoint(x: 88, y: 26)
        let br = CGPoint(x: 82, y: 64), bl = CGPoint(x: 10, y: 56)
        func at(_ s: CGFloat, _ t: CGFloat) -> CGPoint {
            // Bilinear: s across, t down.
            let top = CGPoint(x: tl.x + (tr.x - tl.x) * s, y: tl.y + (tr.y - tl.y) * s)
            let bottom = CGPoint(x: bl.x + (br.x - bl.x) * s, y: bl.y + (br.y - bl.y) * s)
            return P(top.x + (bottom.x - top.x) * t, top.y + (bottom.y - top.y) * t)
        }
        func quad(_ s0: CGFloat, _ t0: CGFloat, _ s1: CGFloat, _ t1: CGFloat) -> Path {
            var p = Path()
            p.move(to: at(s0, t0))
            p.addLine(to: at(s1, t0))
            p.addLine(to: at(s1, t1))
            p.addLine(to: at(s0, t1))
            p.closeSubpath()
            return p
        }

        ground(ctx, 50, 78, w: 80, h: 8, opacity: 0.85)

        // A low ground frame: rear struts mostly hidden behind the panel, short front feet,
        // and a rail along the ground tying them together.
        let leg = Color(white: 0.66)
        var rail = Path()
        rail.move(to: P(14, 75.5))
        rail.addLine(to: P(84, 77))
        ctx.stroke(rail, with: .color(Color(white: 0.2)), style: StrokeStyle(lineWidth: u(3.4), lineCap: .round))
        ctx.stroke(rail, with: .color(Color(white: 0.5)), style: StrokeStyle(lineWidth: u(2), lineCap: .round))
        for (top, foot) in [(at(0.16, 0.4), P(22, 76)), (at(0.88, 0.45), P(80, 77)),
                            (at(0.07, 0.98), P(13, 75.5)), (at(0.85, 0.98), P(76, 77))] {
            var l = Path()
            l.move(to: top)
            l.addLine(to: foot)
            ctx.stroke(l, with: .color(Color(white: 0.18)), style: StrokeStyle(lineWidth: u(3.6), lineCap: .round))
            ctx.stroke(l, with: .color(leg), style: StrokeStyle(lineWidth: u(2.2), lineCap: .round))
        }
        // The panel's edge thickness, below the glass.
        var edge = Path()
        edge.move(to: at(0, 1))
        edge.addLine(to: at(1, 1))
        edge.addLine(to: CGPoint(x: at(1, 1).x, y: at(1, 1).y + u(3)))
        edge.addLine(to: CGPoint(x: at(0, 1).x, y: at(0, 1).y + u(3)))
        edge.closeSubpath()
        ctx.fill(edge, with: .color(Color(white: 0.4)))

        // The aluminium frame, then the cell field inside it.
        let frame = quad(0, 0, 1, 1)
        let bounds = frame.boundingRect
        ctx.fill(frame, with: .linearGradient(Gradient(colors: [Color(white: 0.92), Color(white: 0.66), Color(white: 0.8)]),
                                              startPoint: CGPoint(x: bounds.minX, y: bounds.minY),
                                              endPoint: CGPoint(x: bounds.maxX, y: bounds.maxY)))
        let inset: CGFloat = 0.03
        let field = quad(inset, inset * 1.3, 1 - inset, 1 - inset * 1.3)
        ctx.fill(field, with: .linearGradient(Gradient(stops: [
            .init(color: Color(red: 0.13, green: 0.2, blue: 0.42), location: 0),
            .init(color: Color(red: 0.05, green: 0.08, blue: 0.2), location: 0.55),
            .init(color: Color(red: 0.03, green: 0.05, blue: 0.13), location: 1),
        ]), startPoint: at(0.2, 0), endPoint: at(0.8, 1)))

        var cells = ctx
        cells.clip(to: field)
        // Cell gaps: 6 across, 4 down, plus a fine half-cut line through each row.
        let cols = 6, rows = 4
        for i in 1..<cols {
            let s = inset + (1 - 2 * inset) * CGFloat(i) / CGFloat(cols)
            var l = Path()
            l.move(to: at(s, 0))
            l.addLine(to: at(s, 1))
            cells.stroke(l, with: .color(Color(white: 0.75).opacity(0.55)), lineWidth: u(0.55))
        }
        for j in 1..<rows {
            let t = inset * 1.3 + (1 - 2.6 * inset) * CGFloat(j) / CGFloat(rows)
            var l = Path()
            l.move(to: at(0, t))
            l.addLine(to: at(1, t))
            cells.stroke(l, with: .color(Color(white: 0.75).opacity(0.55)), lineWidth: u(0.55))
        }
        for j in 0..<rows {
            let t = inset * 1.3 + (1 - 2.6 * inset) * (CGFloat(j) + 0.5) / CGFloat(rows)
            var l = Path()
            l.move(to: at(0, t))
            l.addLine(to: at(1, t))
            cells.stroke(l, with: .color(Color(white: 0.7).opacity(0.18)), lineWidth: u(0.3))
        }
        // The sky across the glass: a broad diagonal sheen, warmer when the sun is on it.
        let sheen = on ? Color(red: 1, green: 0.93, blue: 0.78) : Color(white: 0.8)
        cells.energyLayer(blur: u(5)) {
            var band = Path()
            band.move(to: at(0.05, 0))
            band.addLine(to: at(0.42, 0))
            band.addLine(to: at(0.2, 1))
            band.addLine(to: at(-0.1, 1))
            band.closeSubpath()
            $0.fill(band, with: .color(sheen.opacity(on ? 0.34 : 0.16)))
        }
        if on {
            let c = glow
            cells.energyLayer(blur: u(3.5), additive: true) {
                $0.fill(Path(ellipseIn: CGRect(x: at(0.78, 0.12).x - u(7), y: at(0.78, 0.12).y - u(4), width: u(14), height: u(8))),
                        with: .color(c.opacity(0.45)))
            }
        }
        // The frame's lit top edge.
        var top = Path()
        top.move(to: at(0, 0))
        top.addLine(to: at(1, 0))
        ctx.stroke(top, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: u(0.8), lineCap: .round))
        ctx.stroke(frame, with: .color(.black.opacity(0.35)), lineWidth: u(0.4))
    }
}

private extension GraphicsContext {
    /// Draws into a copy of the context, through a blur and blend of its own.
    func energyLayer(blur: CGFloat = 0, additive: Bool = false, _ draw: (inout GraphicsContext) -> Void) {
        var c = self
        if blur > 0 { c.addFilter(.blur(radius: blur)) }
        if additive { c.blendMode = .plusLighter }
        draw(&c)
    }
}
