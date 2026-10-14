import SwiftUI

/// A wall-mounted split unit, rendered in layers of light rather than pictured: a soft
/// cast shadow on the wall, a satin body with a cylindrical sheen, an embossed panel seam,
/// a vent with its slats, a louver that swings open on power, and a hidden display that
/// glows through the front. Below it, conditioned air falls as luminous mist.
///
/// `power` animates between 0 and 1, so the louver opens and the air fades in smoothly.
struct ACUnitView: View, Animatable {
    var power: Double
    var mode: String
    var intensity: Double = 0.6
    var swing = false
    var width: CGFloat = 240
    var display: String?
    /// How far the air falls, as a fraction of the width.
    var reach: CGFloat = 0.62
    /// Fixed time is used only by the offline illustration renderer.
    var previewTime: Double?
    /// Reduce Motion: the air drifts at a third of the pace.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    var animatableData: Double {
        get { power }
        set { power = newValue }
    }

    private var h: CGFloat { width * 0.265 }
    private var canvasSize: CGSize { CGSize(width: width * 1.36, height: 16 + h + width * reach) }
    private var o: CGPoint { CGPoint(x: (canvasSize.width - width) / 2, y: 12) }

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 / 20 : 1 / 30,
                                paused: power < 0.001 || previewTime != nil)) { timeline in
            let t = (previewTime ?? timeline.date.timeIntervalSinceReferenceDate) * (reduceMotion ? 0.33 : 1)
            Canvas { ctx, _ in
                drawWallShadow(&ctx)
                if power > 0.001 { drawAir(&ctx, t: t) }
                drawBody(&ctx, t: t)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .accessibilityLabel(power > 0.5 ? "Air conditioner running" : "Air conditioner off")
    }

    // MARK: Body

    private var bodyRect: CGRect { CGRect(x: o.x, y: o.y, width: width, height: h) }

    private func bodyPath() -> Path {
        UnevenRoundedRectangle(topLeadingRadius: h * 0.17, bottomLeadingRadius: h * 0.34,
                               bottomTrailingRadius: h * 0.34, topTrailingRadius: h * 0.17, style: .continuous)
            .path(in: bodyRect)
    }

    private func drawWallShadow(_ ctx: inout GraphicsContext) {
        let r = bodyRect
        var far = ctx
        far.addFilter(.blur(radius: width * 0.07))
        far.fill(Path(roundedRect: CGRect(x: r.minX + width * 0.06, y: r.minY + h * 0.45, width: width * 0.88, height: h * 0.95),
                      cornerRadius: h * 0.4), with: .color(.black.opacity(0.7)))
        var near = ctx
        near.addFilter(.blur(radius: 3))
        near.fill(Path(roundedRect: r.offsetBy(dx: 0, dy: 2.5).insetBy(dx: 4, dy: 1), cornerRadius: h * 0.3),
                  with: .color(.black.opacity(0.45)))
    }

    private func drawBody(_ ctx: inout GraphicsContext, t: Double) {
        let r = bodyRect
        let shape = bodyPath()

        // Satin white, light from above.
        ctx.fill(shape, with: .linearGradient(Gradient(stops: [
            .init(color: Color(white: 1.0), location: 0),
            .init(color: Color(white: 0.965), location: 0.42),
            .init(color: Color(white: 0.88), location: 0.78),
            .init(color: Color(white: 0.74), location: 1),
        ]), startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY)))

        var inside = ctx
        inside.clip(to: shape)

        // The ends turn away from the light, so the front reads as gently curved.
        inside.fill(Path(r), with: .linearGradient(Gradient(stops: [
            .init(color: .black.opacity(0.13), location: 0),
            .init(color: .clear, location: 0.12),
            .init(color: .clear, location: 0.88),
            .init(color: .black.opacity(0.15), location: 1),
        ]), startPoint: CGPoint(x: r.minX, y: r.midY), endPoint: CGPoint(x: r.maxX, y: r.midY)))

        // A broad soft reflection across the top of the front panel.
        var gloss = inside
        gloss.addFilter(.blur(radius: h * 0.12))
        gloss.fill(Path(ellipseIn: CGRect(x: r.minX + width * 0.12, y: r.minY - h * 0.05, width: width * 0.76, height: h * 0.42)),
                   with: .color(.white.opacity(0.85)))

        // Embossed seam between the front panel and the lower housing.
        let seamY = r.minY + h * 0.6
        var seam = Path()
        seam.move(to: CGPoint(x: r.minX + h * 0.18, y: seamY))
        seam.addLine(to: CGPoint(x: r.maxX - h * 0.18, y: seamY))
        inside.stroke(seam, with: .color(.black.opacity(0.12)), lineWidth: 0.7)
        inside.stroke(seam.offsetBy(dx: 0, dy: 0.9), with: .color(.white.opacity(0.75)), lineWidth: 0.7)

        // The lower housing sits in a little shade.
        inside.fill(Path(CGRect(x: r.minX, y: seamY, width: width, height: h * 0.4)),
                    with: .linearGradient(Gradient(colors: [.clear, .black.opacity(0.07)]),
                                          startPoint: CGPoint(x: r.midX, y: seamY), endPoint: CGPoint(x: r.midX, y: r.maxY)))

        // The vent: a dark slot with slats, revealed as the louver opens.
        let vent = CGRect(x: r.minX + width * 0.07, y: r.minY + h * 0.73, width: width * 0.86, height: h * 0.15)
        let ventPath = Path(roundedRect: vent, cornerRadius: vent.height / 2, style: .continuous)
        inside.fill(ventPath, with: .linearGradient(Gradient(colors: [Color(white: 0.07), Color(white: 0.2)]),
                                                    startPoint: CGPoint(x: vent.midX, y: vent.minY),
                                                    endPoint: CGPoint(x: vent.midX, y: vent.maxY)))
        var slats = inside
        slats.clip(to: ventPath)
        let count = 34
        for i in 1..<count {
            let x = vent.minX + vent.width * CGFloat(i) / CGFloat(count)
            var line = Path()
            line.move(to: CGPoint(x: x, y: vent.minY))
            line.addLine(to: CGPoint(x: x - 1.5, y: vent.maxY))
            slats.stroke(line, with: .color(.white.opacity(0.07)), lineWidth: 0.6)
        }
        // A faint glow of the air colour deep in the vent while running.
        slats.fill(ventPath, with: .color(Theme.air(mode).opacity(0.18 * power)))

        // Closed, a flush cover hides the vent.
        drawCover(&inside, vent: vent, opacity: 1 - power)

        // Hidden display: the set temperature glows through the panel.
        if let display, power > 0.01 {
            let center = CGPoint(x: r.maxX - width * 0.12, y: r.minY + h * 0.36)
            let text = Text(display).font(.system(size: h * 0.17, weight: .medium, design: .rounded))
            var glow = inside
            glow.addFilter(.blur(radius: 2.5))
            glow.opacity = power
            glow.draw(text.foregroundColor(Theme.air(mode)), at: center)
            var crisp = inside
            crisp.opacity = power * 0.85
            crisp.draw(text.foregroundColor(Theme.air(mode).opacity(0.75)), at: center)
        }

        // Top edge catches the light.
        var edge = Path()
        edge.move(to: CGPoint(x: r.minX + h * 0.2, y: r.minY + 0.8))
        edge.addLine(to: CGPoint(x: r.maxX - h * 0.2, y: r.minY + 0.8))
        ctx.stroke(edge, with: .color(.white), lineWidth: 1)

        drawLouver(&ctx, vent: vent, t: t)
    }

    private func drawCover(_ ctx: inout GraphicsContext, vent: CGRect, opacity: Double) {
        guard opacity > 0.001 else { return }
        var cover = ctx
        cover.opacity = opacity
        cover.fill(Path(roundedRect: vent.insetBy(dx: -1, dy: -0.5), cornerRadius: vent.height / 2, style: .continuous),
                   with: .linearGradient(Gradient(colors: [Color(white: 0.9), Color(white: 0.78)]),
                                         startPoint: CGPoint(x: vent.midX, y: vent.minY), endPoint: CGPoint(x: vent.midX, y: vent.maxY)))
    }

    private func drawLouver(_ ctx: inout GraphicsContext, vent: CGRect, t: Double) {
        guard power > 0.001 else { return }
        let sway = swing ? sin(t * 0.7) * 0.4 : 0
        let drop = h * 0.26 * power * (1 + sway * 0.35)
        let hingeY = vent.maxY - 0.5
        let inset = width * 0.012
        var blade = Path()
        blade.move(to: CGPoint(x: vent.minX + inset, y: hingeY))
        blade.addLine(to: CGPoint(x: vent.maxX - inset, y: hingeY))
        blade.addQuadCurve(to: CGPoint(x: vent.maxX - inset * 3, y: hingeY + drop),
                           control: CGPoint(x: vent.maxX - inset * 1.2, y: hingeY + drop * 0.6))
        blade.addLine(to: CGPoint(x: vent.minX + inset * 3, y: hingeY + drop))
        blade.addQuadCurve(to: CGPoint(x: vent.minX + inset, y: hingeY),
                           control: CGPoint(x: vent.minX + inset * 1.2, y: hingeY + drop * 0.6))
        blade.closeSubpath()

        var shadow = ctx
        shadow.addFilter(.blur(radius: 3))
        shadow.fill(blade.offsetBy(dx: 0, dy: 2), with: .color(.black.opacity(0.35 * power)))
        ctx.fill(blade, with: .linearGradient(Gradient(colors: [Color(white: 0.97), Color(white: 0.82)]),
                                              startPoint: CGPoint(x: vent.midX, y: hingeY),
                                              endPoint: CGPoint(x: vent.midX, y: hingeY + drop)))
        var lip = Path()
        lip.move(to: CGPoint(x: vent.minX + inset * 3, y: hingeY + drop))
        lip.addLine(to: CGPoint(x: vent.maxX - inset * 3, y: hingeY + drop))
        ctx.stroke(lip, with: .color(.white.opacity(0.9 * power)), lineWidth: 0.8)
    }

    // MARK: Air

    /// Stateless particles: every puff's position is a pure function of time, so the
    /// mist flows continuously with nothing to store. Drawn additively through a blur,
    /// overlapping puffs build into soft luminous volume.
    private func drawAir(_ ctx: inout GraphicsContext, t: Double) {
        let r = bodyRect
        let color = Theme.air(mode)
        // The air pours off the lip of the open louver.
        let top = r.minY + h * 0.88 + h * 0.24 * power
        let fall = width * reach
        let ventMinX = r.minX + width * 0.09
        let ventW = width * 0.82
        let sway = swing ? sin(t * 0.7) * 0.4 : 0
        let strength = min(1, max(0, intensity))
        let pace = 0.5 + strength * 0.8

        // A fine veil: many small, faint puffs that widen and fade as they fall.
        var mist = ctx
        mist.blendMode = scheme == .dark ? .plusLighter : .normal
        mist.addFilter(.blur(radius: width * 0.03))
        let puffs = Int(48 + 36 * strength)
        for i in 0..<puffs {
            let s1 = hash(i, 1), s2 = hash(i, 2), s3 = hash(i, 3), s4 = hash(i, 4)
            let life = (2.8 + s2 * 2.2) / pace
            let age = fract(t / life + s1)
            let x0 = ventMinX + ventW * s3
            let side = (x0 - r.midX) / (ventW / 2)
            let y = top + fall * pow(age, 0.9)
            let drift = (side * 0.3 + sway) * fall * age * 0.7
            let curl = sin(t * 0.8 + s4 * 6.283 + age * 3.6) * (1 + 10 * age)
            let x = x0 + drift + curl
            let size = width * (0.018 + 0.085 * age)
            // Bright as it leaves the vent, thinning to nothing.
            let envelope = pow(min(age * 6, 1), 0.6) * pow(1 - age, 1.8)
            let alpha = envelope * (0.03 + 0.028 * strength) * power
            let puff = CGRect(x: x - size, y: y - size * 0.6, width: size * 2, height: size * 1.2)
            mist.fill(Path(ellipseIn: puff), with: .radialGradient(
                Gradient(colors: [color.opacity(alpha), color.opacity(0)]),
                center: CGPoint(x: puff.midX, y: puff.midY), startRadius: 0, endRadius: size))
        }

        // A sheet of light right under the louver, where the air is densest.
        var sheet = ctx
        sheet.blendMode = scheme == .dark ? .plusLighter : .normal
        sheet.addFilter(.blur(radius: width * 0.035))
        sheet.fill(Path(roundedRect: CGRect(x: ventMinX + ventW * 0.04, y: top - 2, width: ventW * 0.92, height: fall * 0.28),
                        cornerRadius: fall * 0.14),
                   with: .linearGradient(Gradient(colors: [color.opacity(0.16 * power), color.opacity(0)]),
                                         startPoint: CGPoint(x: r.midX, y: top), endPoint: CGPoint(x: r.midX, y: top + fall * 0.28)))

        // Continuous, gently spreading lanes connect the flow to the vent. A
        // brighter pulse travels along each lane and fades before it wraps around.
        // This reads as a stream of air rather than disconnected falling streaks.
        let ribbons = 9
        for i in 0..<ribbons {
            let f = Double(i) / Double(ribbons - 1)
            let x0 = ventMinX + ventW * (0.06 + 0.88 * f)
            let side = (x0 - r.midX) / (ventW / 2)
            func point(_ p: Double) -> CGPoint {
                let y = top + fall * 0.92 * pow(p, 0.95)
                let spread = (side * 0.26 + sway) * fall * p * p * 0.72
                let curl = sin(p * 4.2 + t * 0.7 + side * 0.8) * width * 0.028 * p
                return CGPoint(x: x0 + spread + curl, y: y)
            }
            let head = fract(t * 0.25 * pace + Double(i) * 0.065) * 1.6 - 0.3
            // A gradient along the whole lane avoids hundreds of separately
            // blurred draw calls while still fading the moving pulse at each end.
            var path = Path()
            var stops: [Gradient.Stop] = []
            var coreStops: [Gradient.Stop] = []
            for s in 0...48 {
                let p = Double(s) / 48
                let envelope = pow(1 - p, 1.8)
                let pulse = exp(-pow((p - head) / 0.19, 2))
                let alpha = power * envelope * (0.16 + pulse * (0.33 + strength * 0.21))
                s == 0 ? path.move(to: point(p)) : path.addLine(to: point(p))
                stops.append(.init(color: color.opacity(alpha * 0.5), location: p))
                let core = scheme == .dark ? Color.white : color
                coreStops.append(.init(color: core.opacity(alpha * (scheme == .dark ? 0.7 : 0.85)), location: p))
            }
            let start = CGPoint(x: r.midX, y: top), end = CGPoint(x: r.midX, y: top + fall * 0.92)
            var glow = ctx
            glow.blendMode = scheme == .dark ? .plusLighter : .normal
            glow.addFilter(.blur(radius: width * 0.015))
            glow.stroke(path, with: .linearGradient(Gradient(stops: stops), startPoint: start, endPoint: end),
                        style: StrokeStyle(lineWidth: width * 0.023, lineCap: .round))
            ctx.stroke(path, with: .linearGradient(Gradient(stops: coreStops), startPoint: start, endPoint: end),
                       style: StrokeStyle(lineWidth: max(0.8, width * 0.004), lineCap: .round))
        }
    }

    private func hash(_ i: Int, _ k: Double) -> Double {
        fract(sin(Double(i) * 12.9898 + k * 78.233) * 43758.5453)
    }

    private func fract(_ x: Double) -> Double { x - floor(x) }
}
