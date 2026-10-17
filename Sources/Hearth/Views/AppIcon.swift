import SwiftUI

/// The app icon: a silver roof above three blue currents. The quiet navy tile
/// and broad, open strokes keep the house-and-air silhouette legible at small sizes.
/// An 824 point squircle is centred on the standard 1024 point icon canvas.
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

/// Paints the icon on a 1024 grid. Materials share one light source, above left.
private struct IconPainter {
    private let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    private var tilePath: Path { Path(roundedRect: tile, cornerRadius: 185, style: .continuous) }

    // Fixed brand colours keep exported artwork independent of appearance and HVAC mode.
    private let navy = Color(red: 0.055, green: 0.083, blue: 0.14)
    private let graphite = Color(red: 0.025, green: 0.036, blue: 0.060)
    private let blue = Color(red: 0.055, green: 0.36, blue: 0.91)
    private let blueLight = Color(red: 0.32, green: 0.64, blue: 1)
    private let silver = Color(red: 0.79, green: 0.85, blue: 0.93)
    private let silverLight = Color(red: 0.97, green: 0.985, blue: 1)

    func draw(_ ctx: inout GraphicsContext) {
        // A contained desktop shadow; the mark itself has no neon halo.
        ctx.layer(blur: 16) {
            $0.fill(tilePath.offsetBy(dx: 0, dy: 12), with: .color(.black.opacity(0.28)))
        }
        ctx.fill(tilePath, with: .linearGradient(Gradient(colors: [navy, graphite]),
            startPoint: CGPoint(x: 220, y: 100), endPoint: CGPoint(x: 740, y: 924)))

        var inside = ctx
        inside.clip(to: tilePath)
        // A low contrast reflection gives the tile depth without obscuring its outline.
        inside.fill(Path(tile), with: .radialGradient(Gradient(colors: [
            Color(red: 0.23, green: 0.34, blue: 0.51).opacity(0.20), .clear,
        ]), center: CGPoint(x: 300, y: 160), startRadius: 0, endRadius: 720))
        inside.stroke(tilePath, with: .linearGradient(Gradient(stops: [
            .init(color: .white.opacity(0.22), location: 0),
            .init(color: .white.opacity(0.065), location: 0.38),
            .init(color: .black.opacity(0.40), location: 1),
        ]), startPoint: CGPoint(x: 300, y: 100), endPoint: CGPoint(x: 650, y: 924)), lineWidth: 4)

        emblem(inside)
    }

    private var roof: Path {
        var p = Path()
        p.move(to: CGPoint(x: 274, y: 462))
        p.addLine(to: CGPoint(x: 512, y: 264))
        p.addLine(to: CGPoint(x: 750, y: 462))
        return p
    }

    /// One consistent wave shape, with deliberately stepped lengths and generous gaps.
    private var currents: [(Path, CGFloat)] {
        func wave(_ y: CGFloat, _ end: CGFloat, _ lift: CGFloat) -> Path {
            let start: CGFloat = 316
            let width = end - start
            var p = Path()
            p.move(to: CGPoint(x: start, y: y))
            p.addCurve(to: CGPoint(x: end, y: y),
                control1: CGPoint(x: start + width * 0.34, y: y - lift),
                control2: CGPoint(x: start + width * 0.66, y: y + lift))
            return p
        }
        return [(wave(562, 708, 38), 46),
                (wave(658, 638, 31), 42),
                (wave(754, 562, 24), 38)]
    }

    private func emblem(_ ctx: GraphicsContext) {
        let roofShade = GraphicsContext.Shading.linearGradient(Gradient(stops: [
            .init(color: silverLight, location: 0),
            .init(color: silver, location: 0.55),
            .init(color: Color(red: 0.62, green: 0.71, blue: 0.83), location: 1),
        ]), startPoint: CGPoint(x: 320, y: 264), endPoint: CGPoint(x: 700, y: 520))
        relief(ctx, roof, shade: roofShade, width: 52, highlight: silverLight.opacity(0.48))

        // A single blue material across every current, rather than separate spectral colours.
        let airShade = GraphicsContext.Shading.linearGradient(Gradient(stops: [
            .init(color: blueLight, location: 0),
            .init(color: blue, location: 0.64),
            .init(color: Color(red: 0.07, green: 0.25, blue: 0.66), location: 1),
        ]), startPoint: CGPoint(x: 316, y: 510), endPoint: CGPoint(x: 708, y: 800))
        for (path, width) in currents {
            relief(ctx, path, shade: airShade, width: width, highlight: blueLight.opacity(0.62))
        }

        // The centre point echoes the monochrome menu glyph, without a notification badge.
        let point = CGRect(x: 496, y: 404, width: 32, height: 32)
        ctx.fill(Path(ellipseIn: point.offsetBy(dx: 0, dy: 3)), with: .color(.black.opacity(0.35)))
        ctx.fill(Path(ellipseIn: point), with: .linearGradient(Gradient(colors: [silverLight, silver]),
            startPoint: CGPoint(x: 502, y: 404), endPoint: CGPoint(x: 522, y: 436)))
    }

    /// Crisp material edges with a shallow relief, kept inside the silhouette.
    private func relief(_ ctx: GraphicsContext, _ path: Path,
                        shade: GraphicsContext.Shading, width: CGFloat, highlight: Color) {
        let stroke = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        ctx.layer(blur: 5) {
            $0.stroke(path.offsetBy(dx: 0, dy: 6), with: .color(.black.opacity(0.32)), style: stroke)
        }
        ctx.stroke(path, with: shade, style: stroke)

        // Clip the fine upper reflection to the filled stroke; no bright fringe outside it.
        var reflection = ctx
        reflection.clip(to: path.strokedPath(stroke))
        reflection.stroke(path.offsetBy(dx: 0, dy: -width * 0.45), with: .color(highlight),
            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
    }
}

private extension GraphicsContext {
    func layer(blur: CGFloat = 0, _ draw: (inout GraphicsContext) -> Void) {
        var c = self
        if blur > 0 { c.addFilter(.blur(radius: blur)) }
        draw(&c)
    }
}
