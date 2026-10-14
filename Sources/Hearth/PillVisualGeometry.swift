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
}

/// Keep the alert's complete capsule, dismiss badge and shadow inside its clear
/// native window throughout the short drop. Text is never blurred to simulate motion.
enum FlashPillGeometry {
    static let bodyHeight: CGFloat = 68
    static let panelHeight: CGFloat = 132
    static let visibleOffset: CGFloat = 14
    static let hiddenOffset: CGFloat = 8
    static let topPadding: CGFloat = 2
    static let dismissOverhang: CGFloat = 4
    static let dismissSize: CGFloat = 20
    static let interactionHeight = bodyHeight + dismissOverhang

    static func interactionWidth(bodyWidth: CGFloat) -> CGFloat { bodyWidth + dismissOverhang }
    static func bodyRect(bodyWidth: CGFloat) -> CGRect {
        CGRect(x: dismissOverhang, y: dismissOverhang, width: bodyWidth, height: bodyHeight)
    }
    static var dismissRect: CGRect { CGRect(x: 0, y: 0, width: dismissSize, height: dismissSize) }
    static let shadowRadius: CGFloat = 18
    static let shadowOffset: CGFloat = 10

    static func offset(shown: Bool, reduceMotion: Bool) -> CGFloat {
        shown || reduceMotion ? visibleOffset : hiddenOffset
    }
}
