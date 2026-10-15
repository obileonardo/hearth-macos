import Foundation

/// The map must inherit the current native cursor whenever another view owns
/// the point. In particular, it cannot replace a text editor's I-beam.
enum MapCursorPolicy {
    enum Choice: Equatable { case inherited, arrow, openHand }

    struct Context {
        var active: Bool
        var visible: Bool
        var keyWindow: Bool
        var sameWindow: Bool
        var insideVisibleRect: Bool
        var canvasHit: Bool

        var ownsPoint: Bool { active && visible && keyWindow && sameWindow && insideVisibleRect && canvasHit }
    }

    static func shouldSet(_ choice: Choice, currentMatches: Bool) -> Bool {
        choice != .inherited && !currentMatches
    }

    static func choice(_ context: Context, dragging: Bool, hitHouseOrPin: Bool) -> Choice {
        guard context.ownsPoint, !dragging else { return .inherited }
        return hitHouseOrPin ? .openHand : .arrow
    }
}

/// A map may push one drag cursor and may pop only after it acquired one.
/// End is idempotent so mouse-up, cancellation and detachment cannot double-pop.
struct MapDragCursorLease {
    private(set) var held = false
    mutating func begin() -> Bool {
        guard !held else { return false }
        held = true
        return true
    }
    mutating func end() -> Bool {
        guard held else { return false }
        held = false
        return true
    }
}
