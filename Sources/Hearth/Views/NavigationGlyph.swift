import SwiftUI

/// Dock activation wraps the same quiet semantic drawings used in Settings.
struct NavigationGlyph: View {
    let page: Page
    let fallback: String
    let selected: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch page {
            case .security, .rooms, .devices:
                animatedMark {
                    StaticSemanticNavigationGlyph(page: page, fallback: fallback, selected: selected)
                }
            default:
                if reduceMotion {
                    symbol
                } else {
                    symbol.symbolEffect(.bounce.down, options: .speed(1.4), value: selected)
                }
            }
        }
        .foregroundStyle(selected ? Theme.sand : Theme.muted)
        .animation(reduceMotion ? nil : .snap, value: selected)
        .accessibilityHidden(true)
    }

    private var symbol: some View {
        Image(systemName: fallback)
            .symbolVariant(selected ? .fill : .none)
            .font(.system(size: 15, weight: selected ? .semibold : .regular))
            .frame(width: 17, height: 17)
    }

    /// Custom marks receive the same brief activation movement as the native symbols.
    /// Motion only changes their drawing transform, never the dock's layout or hit area.
    @ViewBuilder
    private func animatedMark<Mark: View>(@ViewBuilder _ mark: () -> Mark) -> some View {
        if reduceMotion {
            mark()
        } else {
            mark().phaseAnimator([false, true, false], trigger: selected) { content, lifted in
                content
                    .offset(y: lifted && selected ? 1.4 : 0)
                    .scaleEffect(lifted && selected ? 1.07 : 1)
            } animation: { lifted in
                .spring(response: lifted ? 0.2 : 0.32, dampingFraction: 0.85)
            }
        }
    }
}

/// A static, colour-inheriting icon for section rows and other non-navigation uses.
/// All custom marks share a 17pt drawing box and a 1.25pt rounded stroke. Selection
/// adds fill rather than changing stroke weight; the dock owns motion and colour.
struct StaticSemanticNavigationGlyph: View {
    let page: Page
    let fallback: String
    var selected = false

    private let line = StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round)

    var body: some View {
        Group {
            switch page {
            case .security:
                ZStack {
                    SecurityCameraFillGlyph().fill(style: FillStyle(eoFill: true)).opacity(selected ? 1 : 0)
                    SecurityCameraGlyph().stroke(style: line)
                }
            case .rooms:
                ZStack {
                    RoomFillGlyph(leftWall: true).fill().opacity(selected ? 0.45 : 0)
                    RoomFillGlyph(leftWall: false).fill(style: FillStyle(eoFill: true)).opacity(selected ? 0.9 : 0)
                    RoomGlyph().stroke(style: line)
                }
            case .devices:
                ZStack {
                    DeviceCollectionFillGlyph().fill(style: FillStyle(eoFill: true)).opacity(selected ? 1 : 0)
                    DeviceCollectionGlyph().stroke(style: line)
                }
            default:
                Image(systemName: fallback)
                    .symbolVariant(selected ? .fill : .none)
                    .font(.system(size: 15, weight: selected ? .semibold : .regular))
            }
        }
        .frame(width: 17, height: 17)
        .accessibilityHidden(true)
    }
}

private struct SecurityCameraFillGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let t = GlyphCoordinates(rect)
        var p = Path()
        p.move(to: t(3.5, 4.5)); p.addLine(to: t(15.5, 6.5))
        p.addLine(to: t(18.5, 11)); p.addLine(to: t(15.6, 14.4))
        p.addLine(to: t(3.5, 11.1)); p.closeSubpath()
        p.addEllipse(in: t.rect(x: 15.1, y: 9.4, width: 2.1, height: 2.5))
        return p
    }
}

private struct RoomFillGlyph: Shape {
    let leftWall: Bool
    func path(in rect: CGRect) -> Path {
        let t = GlyphCoordinates(rect)
        var p = Path()
        if leftWall {
            p.move(to: t(3, 6)); p.addLine(to: t(12, 3)); p.addLine(to: t(12, 14))
            p.addLine(to: t(3, 17.5)); p.closeSubpath()
        } else {
            p.move(to: t(12, 3)); p.addLine(to: t(21, 6)); p.addLine(to: t(21, 17.5))
            p.addLine(to: t(12, 14)); p.closeSubpath()
            p.move(to: t(15.3, 15.3)); p.addLine(to: t(15.3, 8))
            p.addLine(to: t(18.5, 9.1)); p.addLine(to: t(18.5, 16.5)); p.closeSubpath()
        }
        return p
    }
}

private struct DeviceCollectionFillGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let t = GlyphCoordinates(rect)
        var p = Path()
        for points in [
            [(2.5, 5.4), (14.5, 3.4), (14.5, 14.3), (2.5, 16.2)],
            [(4.1, 6.7), (12.9, 5.3), (12.9, 12.9), (4.1, 14.3)],
            [(17.0, 8.0), (22.0, 7.4), (22.0, 20.3), (17.0, 21.0)],
            [(18.2, 9.4), (20.8, 9.1), (20.8, 17.7), (18.2, 18.1)]
        ] as [[(CGFloat, CGFloat)]] {
            p.move(to: t(points[0].0, points[0].1))
            for point in points.dropFirst() { p.addLine(to: t(point.0, point.1)) }
            p.closeSubpath()
        }
        return p
    }
}

/// A tilted camera hood, visible lens and elbow bracket against its wall mount.
private struct SecurityCameraGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let t = GlyphCoordinates(rect)
        p.move(to: t(3.5, 4.5))
        p.addLine(to: t(15.5, 6.5))
        p.addLine(to: t(18.5, 11.0))
        p.addLine(to: t(15.6, 14.4))
        p.addLine(to: t(3.5, 11.1))
        p.closeSubpath()
        p.move(to: t(15.5, 6.5))
        p.addLine(to: t(12.7, 10.1))
        p.addLine(to: t(15.6, 14.4))
        p.move(to: t(8.3, 12.5))
        p.addLine(to: t(8.3, 17.8))
        p.addLine(to: t(19.8, 17.8))
        p.move(to: t(20.3, 14.0))
        p.addLine(to: t(20.3, 21.0))
        p.addEllipse(in: t.rect(x: 15.1, y: 9.4, width: 2.1, height: 2.5))
        return p
    }
}

/// A room seen through its open front: two walls, the floor and a recessed doorway.
private struct RoomGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let t = GlyphCoordinates(rect)
        p.move(to: t(3.0, 6.0))
        p.addLine(to: t(12.0, 3.0))
        p.addLine(to: t(21.0, 6.0))
        p.addLine(to: t(21.0, 17.5))
        p.addLine(to: t(12.0, 21.0))
        p.addLine(to: t(3.0, 17.5))
        p.closeSubpath()
        p.move(to: t(12.0, 3.0))
        p.addLine(to: t(12.0, 14.0))
        p.move(to: t(3.0, 17.5))
        p.addLine(to: t(12.0, 14.0))
        p.addLine(to: t(21.0, 17.5))
        p.move(to: t(15.3, 15.3))
        p.addLine(to: t(15.3, 8.0))
        p.addLine(to: t(18.5, 9.1))
        p.addLine(to: t(18.5, 16.5))
        return p
    }
}

/// A screen and a handheld device, in the same shallow oblique view as the room
/// and camera. Their separation remains readable in the smallest section rows.
private struct DeviceCollectionGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let t = GlyphCoordinates(rect)
        p.move(to: t(2.5, 5.4)); p.addLine(to: t(14.5, 3.4))
        p.addLine(to: t(14.5, 14.3)); p.addLine(to: t(2.5, 16.2)); p.closeSubpath()
        p.move(to: t(9, 15.2)); p.addLine(to: t(9, 20))
        p.move(to: t(5.4, 20.6)); p.addLine(to: t(12.6, 19.4))
        p.move(to: t(17, 8)); p.addLine(to: t(22, 7.4))
        p.addLine(to: t(22, 20.3)); p.addLine(to: t(17, 21)); p.closeSubpath()
        p.move(to: t(18.8, 19.2)); p.addLine(to: t(20.2, 19.0))
        return p
    }
}

private struct GlyphCoordinates {
    let bounds: CGRect
    var scale: CGFloat { min(bounds.width, bounds.height) / 24 }

    init(_ bounds: CGRect) { self.bounds = bounds }

    func callAsFunction(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: bounds.midX + (x - 12) * scale,
                y: bounds.midY + (y - 12) * scale)
    }

    func rect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(origin: self(x, y), size: CGSize(width: width * scale, height: height * scale))
    }
}
