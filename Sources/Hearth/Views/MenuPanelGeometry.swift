import Foundation
import CoreGraphics

/// Center a readable panel below its presentation anchor and keep it on screen.
enum MenuPanelGeometry {
    static func frame(anchor: CGRect, visibleFrame: CGRect, panelSize: CGSize, gap: CGFloat = 8) -> CGRect {
        let margin: CGFloat = 8
        let width = min(max(1, panelSize.width), max(1, visibleFrame.width - 2 * margin))
        let height = min(max(1, panelSize.height), max(1, visibleFrame.height - 2 * margin))
        let x = min(max(anchor.midX - width / 2, visibleFrame.minX + margin), visibleFrame.maxX - margin - width)
        let y = min(max(anchor.minY - gap - height, visibleFrame.minY + margin), visibleFrame.maxY - margin - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

/// A presentation keeps its opening anchor while status text rotates. A real
/// display move starts a new anchor; visible-frame changes still clamp the panel.
struct MenuPanelAnchorSession {
    private var openingAnchor: CGRect?
    private var screenFrame: CGRect?

    mutating func resolve(liveAnchor: CGRect, screenFrame: CGRect) -> CGRect {
        if openingAnchor == nil || self.screenFrame != screenFrame {
            openingAnchor = liveAnchor
            self.screenFrame = screenFrame
        }
        return openingAnchor ?? liveAnchor
    }

    mutating func reset() {
        openingAnchor = nil
        screenFrame = nil
    }
}

enum MenuStatusSlotGeometry {
    /// Leave room for other menu extras. Only the open presentation reserves
    /// this envelope; closed status items retain their normal dynamic width.
    static func width(imageWidths: [CGFloat], screenWidth: CGFloat) -> CGFloat {
        let limit = max(80, min(320, screenWidth / 3))
        return min(limit, max(1, imageWidths.filter { $0.isFinite }.max() ?? 1))
    }
}
