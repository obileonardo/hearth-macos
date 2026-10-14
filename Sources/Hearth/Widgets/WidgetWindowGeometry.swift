import Foundation
import CoreGraphics

/// Gesture translations are always applied to the original frame, preserving
/// the top-left anchor during resize and avoiding accumulated drag deltas.
enum WidgetWindowGeometry {
    static func frame(start: CGRect, translation: CGSize, resizing: Bool,
                      minimum: CGSize, overview: Bool, screen: CGRect) -> CGRect {
        var result = start
        if resizing {
            result.size.width = max(minimum.width, min(1100, screen.maxX - start.minX, start.width + translation.width))
            let height = overview && result.width < 620 ? max(280, minimum.height) : minimum.height
            result.size.height = max(height, min(700, start.maxY - screen.minY, start.height + translation.height))
            result.origin.y = start.maxY - result.height
        } else {
            result.origin.x += translation.width
            result.origin.y -= translation.height
        }
        return result
    }
    static func constrainedSize(_ proposed: CGSize, minimum: CGSize, overview: Bool) -> CGSize {
        let width = max(minimum.width, proposed.width)
        return CGSize(width: width, height: max(overview && width < 620 ? max(280, minimum.height) : minimum.height, proposed.height))
    }
}
