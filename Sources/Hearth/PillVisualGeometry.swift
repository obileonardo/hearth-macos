import Foundation
import CoreGraphics

/// The status item determines available height. Requested extra breathing room
/// never enlarges its canvas past the real menu bar, including smaller displays.
struct StatusPillGeometry: Equatable {
    let bodyHeight: CGFloat
    let canvasHeight: CGFloat

    init(availableHeight: CGFloat) {
        let safe = availableHeight.isFinite && availableHeight > 0 ? availableHeight : 22
        canvasHeight = min(26, safe.rounded(.down))
        bodyHeight = min(24, canvasHeight)
    }

    /// The drawn capsule inside the status image: the body is centred in a canvas
    /// up to 2 points taller, so measuring from the image would add that margin.
    static func capsule(in imageFrame: CGRect) -> CGRect {
        let inset = max(0, (imageFrame.height - min(24, imageFrame.height)) / 2)
        return imageFrame.insetBy(dx: 0, dy: inset)
    }
}

/// Keep the alert's complete capsule, dismiss badge and shadow inside its clear
/// native window throughout the short drop. Text is never blurred to simulate motion.
enum FlashPillGeometry {
    static let bodyHeight: CGFloat = 68
    static let panelHeight: CGFloat = 154
    static let visibleOffset: CGFloat = 14
    static let hiddenOffset: CGFloat = 8
    static let topPadding: CGFloat = 22
    static let dismissOverhang: CGFloat = 4
    static let dismissSize: CGFloat = 20
    static let interactionHeight = bodyHeight + dismissOverhang

    static func interactionWidth(bodyWidth: CGFloat) -> CGFloat { bodyWidth + dismissOverhang }
    static func bodyRect(bodyWidth: CGFloat) -> CGRect {
        CGRect(x: dismissOverhang, y: dismissOverhang, width: bodyWidth, height: bodyHeight)
    }
    static var dismissRect: CGRect { CGRect(x: 0, y: 0, width: dismissSize, height: dismissSize) }
    static let shadowRadius: CGFloat = 12
    static let shadowOffset: CGFloat = 6

    /// Blur radius is not its full extent. Reserve three radii so the faint
    /// outer gradient fades before a native window edge, including during entry.
    static let shadowBleed: CGFloat = shadowRadius * 3
    static let bodyGap: CGFloat = 16
    static var visibleBodyTop: CGFloat { visibleOffset + topPadding }

    static func frame(anchor: CGRect, visibleFrame: CGRect, screenFrame: CGRect,
                      panelWidth: CGFloat) -> CGRect {
        let width = min(panelWidth, max(1, visibleFrame.width - 16))
        let height = min(panelHeight, max(1, screenFrame.height))
        let x = min(max(anchor.midX - width / 2, visibleFrame.minX + 8), visibleFrame.maxX - width - 8)
        // The clear shadow canvas reaches into the menu bar; the actual capsule
        // starts 16 points below the drawn status capsule when screen space permits.
        let requestedY = anchor.minY - bodyGap + visibleBodyTop - height
        let y = min(max(requestedY, visibleFrame.minY + 8), screenFrame.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func offset(shown: Bool, reduceMotion: Bool) -> CGFloat {
        shown || reduceMotion ? visibleOffset : hiddenOffset
    }
}
