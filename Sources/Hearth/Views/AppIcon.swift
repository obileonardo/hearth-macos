import SwiftUI

/// The app icon: a house drawn in air. A roof of light over three currents that run from
/// cool to warm, with a live light under the ridge, on a dark glass tile in the macOS
/// icon grid (an 824 point squircle centred on a 1024 point canvas).
struct AppIconArt: View {
    var size: CGFloat = 1024

    var body: some View {
        Canvas { ctx, _ in
            let s = size / 1024
            ctx.scaleBy(x: s, y: s)
            IconPainter().draw(&ctx)
        }
        .frame(width: size, height: size)
    }
}

/// The emblem as a single-colour template for the menu bar: the roof and two currents.
struct MenuBarGlyph: View {
    var size: CGFloat = 18

    var body: some View {
        let k = size / 18
        ZStack {
            GlyphStrokes()
                .stroke(.primary, style: StrokeStyle(lineWidth: 1.6 * k, lineCap: .round, lineJoin: .round))
            Circle()
                .fill(.primary)
                .frame(width: 2.6 * k, height: 2.6 * k)
                .position(x: 9 * k, y: 7.3 * k)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Hearth")
    }
}

/// The glyph's lines on an 18 point grid.
private struct GlyphStrokes: Shape {
    func path(in rect: CGRect) -> Path {
        let k = rect.width / 18
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * k, y: rect.minY + y * k) }
        var path = Path()
        path.move(to: p(1.8, 8.4))
        path.addLine(to: p(9, 2.4))
        path.addLine(to: p(16.2, 8.4))

        path.move(to: p(3.8, 11.7))
        path.addCurve(to: p(14.2, 11.7), control1: p(7.2, 10.2), control2: p(10.8, 13.2))
        path.move(to: p(3.8, 15.3))
        path.addCurve(to: p(11.4, 15.3), control1: p(6.3, 14.1), control2: p(8.9, 16.5))
        return path
    }
}

/// Paints the icon on a 1024 grid.
private struct IconPainter {
    private let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    private var tilePath: Path { Path(roundedRect: tile, cornerRadius: 185, style: .continuous) }

    private let cool = Theme.air("cool").vivid(0.5)
    private let mint = Theme.air("dry").vivid(0.45)
    private let lilac = Theme.air("auto").vivid(0.45)
    private let warm = Theme.air("heat").vivid(0.55)

    func draw(_ ctx: inout GraphicsContext) {
        // The tile sits above the desktop on a soft shadow.
        ctx.layer(blur: 22) { $0.fill(tilePath.offsetBy(dx: 0, dy: 14), with: .color(.black.opacity(0.42))) }
        ctx.layer(blur: 3) { $0.fill(tilePath.offsetBy(dx: 0, dy: 2), with: .color(.black.opacity(0.3))) }

        // Dark glass, lit from within.
        ctx.fill(tilePath, with: .linearGradient(Gradient(stops: [
            .init(color: Color(red: 0.09, green: 0.11, blue: 0.19), location: 0),
            .init(color: Color(red: 0.04, green: 0.05, blue: 0.09), location: 0.55),
            .init(color: Color(red: 0.027, green: 0.027, blue: 0.034), location: 1),
        ]), startPoint: CGPoint(x: 512, y: 100), endPoint: CGPoint(x: 512, y: 924)))

        var inside = ctx
        inside.clip(to: tilePath)
        // A dome of cool light behind the house.
        inside.fill(Path(tile), with: .radialGradient(Gradient(stops: [
            .init(color: Color(red: 0.2, green: 0.32, blue: 0.55).opacity(0.62), location: 0),
            .init(color: Color(red: 0.12, green: 0.18, blue: 0.34).opacity(0.3), location: 0.45),
            .init(color: .clear, location: 1),
        ]), center: CGPoint(x: 512, y: 560), startRadius: 0, endRadius: 470))
        // Light pooling on the floor below the currents.
        inside.layer(blur: 40, additive: true) {
            $0.fill(Path(ellipseIn: CGRect(x: 230, y: 760, width: 564, height: 90)), with: .color(cool.opacity(0.28)))
        }

        emblem(inside)

        // Fine grain, so the glass is a material and not a gradient.
        inside.opacity = 0.05
        inside.fill(Path(tile), with: .tiledImage(Image(nsImage: Grain.image), sourceRect: CGRect(x: 0, y: 0, width: 1, height: 1), scale: 1.6))

        // The glass edge: bright along the top, a whisper elsewhere.
        var edge = ctx
        edge.clip(to: tilePath)
        edge.stroke(tilePath, with: .linearGradient(Gradient(stops: [
            .init(color: .white.opacity(0.38), location: 0),
            .init(color: .white.opacity(0.06), location: 0.25),
            .init(color: .white.opacity(0.03), location: 0.8),
            .init(color: .white.opacity(0.1), location: 1),
        ]), startPoint: CGPoint(x: 512, y: 100), endPoint: CGPoint(x: 512, y: 924)), lineWidth: 5)
        edge.layer(blur: 30) {
            $0.fill(Path(ellipseIn: CGRect(x: 180, y: 60, width: 664, height: 150)), with: .color(.white.opacity(0.07)))
        }
    }

    // MARK: Emblem

    private var roof: Path {
        var p = Path()
        p.move(to: CGPoint(x: 252, y: 482))
        p.addLine(to: CGPoint(x: 512, y: 262))
        p.addLine(to: CGPoint(x: 772, y: 482))
        return p
    }

    /// Three currents of air, shorter as they fall, each with a slow wave.
    private var currents: [(Path, CGFloat, CGFloat)] {
        func wave(_ y: CGFloat, _ x0: CGFloat, _ x1: CGFloat, _ lift: CGFloat) -> Path {
            var p = Path()
            let w = x1 - x0
            p.move(to: CGPoint(x: x0, y: y))
            p.addCurve(to: CGPoint(x: x1, y: y), control1: CGPoint(x: x0 + w * 0.34, y: y - lift),
                       control2: CGPoint(x: x0 + w * 0.66, y: y + lift))
            return p
        }
        return [
            (wave(572, 316, 708, 46), 316, 708),
            (wave(668, 316, 640, 38), 316, 640),
            (wave(764, 316, 560, 30), 316, 560),
        ]
    }

    private func emblem(_ ctx: GraphicsContext) {
        let roofShade = GraphicsContext.Shading.linearGradient(Gradient(colors: [mint, cool, lilac]),
                                                                startPoint: CGPoint(x: 252, y: 0), endPoint: CGPoint(x: 772, y: 0))
        ribbon(ctx, roof, shade: roofShade, bloom: cool, width: 62)

        let palettes: [[Color]] = [[mint, cool], [cool, lilac], [lilac, warm]]
        for (i, (path, x0, x1)) in currents.enumerated() {
            let shade = GraphicsContext.Shading.linearGradient(Gradient(colors: palettes[i]),
                                                               startPoint: CGPoint(x: x0, y: 0), endPoint: CGPoint(x: x1, y: 0))
            ribbon(ctx, path, shade: shade, bloom: palettes[i][1], width: 50 - CGFloat(i) * 4)
        }

        // The live light under the ridge.
        let live = Theme.live
        let c = CGPoint(x: 512, y: 410)
        ctx.layer(blur: 34, additive: true) { $0.fill(Path(ellipseIn: CGRect(x: c.x - 70, y: c.y - 70, width: 140, height: 140)), with: .color(live.opacity(0.55))) }
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 27, y: c.y - 27, width: 54, height: 54)), with: .radialGradient(
            Gradient(colors: [.white, Color(red: 1, green: 0.62, blue: 0.56), live]),
            center: CGPoint(x: c.x - 6, y: c.y - 8), startRadius: 0, endRadius: 30))
        // Ripples, like the panel's live dots.
        for (radius, alpha) in [(46, 0.4), (68, 0.16)] as [(CGFloat, Double)] {
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)),
                       with: .color(live.opacity(alpha)), lineWidth: 4)
        }
    }

    /// A stroke of light with body: a wide bloom, a coloured tube, a darker underside and a
    /// bright specular core along its upper edge.
    private func ribbon(_ ctx: GraphicsContext, _ path: Path, shade: GraphicsContext.Shading, bloom: Color, width: CGFloat) {
        let round = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        ctx.layer(blur: width * 0.9, additive: true) {
            $0.stroke(path, with: .color(bloom.opacity(0.55)), style: StrokeStyle(lineWidth: width * 2.2, lineCap: .round, lineJoin: .round))
        }
        ctx.layer(blur: 10) {
            $0.stroke(path.offsetBy(dx: 0, dy: width * 0.3), with: .color(.black.opacity(0.45)), style: round)
        }
        ctx.stroke(path, with: shade, style: round)
        ctx.layer(blur: width * 0.12) {
            $0.stroke(path.offsetBy(dx: 0, dy: width * 0.2), with: .color(.black.opacity(0.22)),
                      style: StrokeStyle(lineWidth: width * 0.5, lineCap: .round, lineJoin: .round))
        }
        ctx.layer(blur: width * 0.08, additive: true) {
            $0.stroke(path.offsetBy(dx: 0, dy: -width * 0.16), with: .color(.white.opacity(0.7)),
                      style: StrokeStyle(lineWidth: width * 0.26, lineCap: .round, lineJoin: .round))
        }
    }
}

private extension GraphicsContext {
    func layer(blur: CGFloat = 0, additive: Bool = false, _ draw: (inout GraphicsContext) -> Void) {
        var c = self
        if blur > 0 { c.addFilter(.blur(radius: blur)) }
        if additive { c.blendMode = .plusLighter }
        draw(&c)
    }
}
