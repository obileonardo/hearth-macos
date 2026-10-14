import Foundation

/// Keep the readable panel centered below the current menu item without
/// resizing content every time a status label changes width.
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
