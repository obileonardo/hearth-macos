import SwiftUI

/// Small, purpose-drawn navigation marks. The room and camera silhouettes describe the
/// destination instead of borrowing a generic grid or a video-call symbol.
struct NavigationGlyph: View {
    let page: Page
    let fallback: String
    let selected: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch page {
            case .security:
                SecurityCameraGlyph().stroke(style: line)
                    .frame(width: 19, height: 19)
            case .rooms:
                RoomGlyph().stroke(style: line)
                    .frame(width: 18, height: 18)
            case .devices:
                DeviceCollectionGlyph().stroke(style: line)
                    .frame(width: 19, height: 19)
            default:
                Image(systemName: fallback)
                    .symbolVariant(selected ? .fill : .none)
                    .font(.system(size: 15, weight: selected ? .semibold : .regular))
                    .symbolEffect(.bounce.down, options: .speed(1.4), value: selected)
            }
        }
        .foregroundStyle(selected ? Theme.ink : Theme.muted)
        .animation(reduceMotion ? nil : .snap, value: selected)
        .accessibilityHidden(true)
    }

    private var line: StrokeStyle {
        StrokeStyle(lineWidth: selected ? 1.45 : 1.25, lineCap: .round, lineJoin: .round)
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

/// A screen and a handheld device, with enough separation to read at dock scale.
private struct DeviceCollectionGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let t = GlyphCoordinates(rect)
        p.addRoundedRect(in: t.rect(x: 2.5, y: 4.0, width: 12.0, height: 10.5),
                         cornerSize: CGSize(width: t.scale, height: t.scale))
        p.move(to: t(9.0, 14.5))
        p.addLine(to: t(9.0, 18.7))
        p.move(to: t(5.4, 18.7))
        p.addLine(to: t(12.6, 18.7))
        p.addRoundedRect(in: t.rect(x: 16.0, y: 8.0, width: 6.0, height: 13.0),
                         cornerSize: CGSize(width: t.scale, height: t.scale))
        p.move(to: t(18.3, 18.7))
        p.addLine(to: t(19.7, 18.7))
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
