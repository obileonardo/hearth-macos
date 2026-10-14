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
                animatedMark {
                    ZStack {
                        SecurityCameraFillGlyph().fill(style: FillStyle(eoFill: true)).opacity(selected ? 1 : 0)
                        SecurityCameraGlyph().stroke(style: line)
                    }
                    .frame(width: 19, height: 19)
                }
            case .rooms:
                animatedMark {
                    ZStack {
                        RoomFillGlyph(leftWall: true).fill().opacity(selected ? 0.45 : 0)
                        RoomFillGlyph(leftWall: false).fill(style: FillStyle(eoFill: true)).opacity(selected ? 0.9 : 0)
                        RoomGlyph().stroke(style: line)
                    }
                    .frame(width: 18, height: 18)
                }
            case .devices:
                animatedMark {
                    ZStack {
                        DeviceCollectionFillGlyph().fill(style: FillStyle(eoFill: true)).opacity(selected ? 1 : 0)
                        DeviceCollectionGlyph().stroke(style: line)
                    }
                    .frame(width: 19, height: 19)
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

    private var line: StrokeStyle {
        StrokeStyle(lineWidth: selected ? 1.45 : 1.25, lineCap: .round, lineJoin: .round)
    }

    private var symbol: some View {
        Image(systemName: fallback)
            .symbolVariant(selected ? .fill : .none)
            .font(.system(size: 15, weight: selected ? .semibold : .regular))
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
        let corner = CGSize(width: t.scale, height: t.scale)
        p.addRoundedRect(in: t.rect(x: 2.5, y: 4, width: 12, height: 10.5), cornerSize: corner)
        p.addRoundedRect(in: t.rect(x: 4.1, y: 5.6, width: 8.8, height: 6.9), cornerSize: corner)
        p.addRoundedRect(in: t.rect(x: 16, y: 8, width: 6, height: 13), cornerSize: corner)
        p.addRoundedRect(in: t.rect(x: 17.2, y: 9.5, width: 3.6, height: 8.3), cornerSize: corner)
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
