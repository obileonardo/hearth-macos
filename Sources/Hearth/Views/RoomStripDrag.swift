import AppKit
import SwiftUI

/// Apply to the content HStack INSIDE the horizontal ScrollView. The SwiftUI
/// gesture takes priority over tile buttons only after genuine drag movement.
extension View {
    func roomStripMouseDrag() -> some View { modifier(RoomStripMouseDragModifier()) }
}

private struct RoomStripMouseDragModifier: ViewModifier {
    @StateObject private var drag = RoomStripDragCoordinator()
    @GestureState private var isDragging = false

    func body(content: Content) -> some View {
        content
            .background(RoomStripDragProbe(drag: drag).accessibilityHidden(true))
            .highPriorityGesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .global)
                    .updating($isDragging) { _, active, _ in active = true }
                    .onChanged { drag.move(translation: $0.translation) }
                    .onEnded { _ in drag.end() }
            )
            .onChange(of: isDragging) { _, active in
                // GestureState also resets when a drag is interrupted, not just
                // on a normal mouse-up. Never carry a prior drag into the next.
                if !active { drag.end() }
            }
    }
}

/// Pure intent and bounds rules keep malformed geometry away from AppKit.
enum RoomStripDragGeometry {
    static func isHorizontalStrip(document: CGSize, viewport: CGSize) -> Bool {
        guard document.width.isFinite, document.height.isFinite,
              viewport.width.isFinite, viewport.height.isFinite,
              viewport.width > 0, viewport.height > 0 else { return false }
        // Never fall back to horizontally moving the tall vertical parent.
        // A small height tolerance accommodates fractional AppKit layout/insets.
        return document.width > viewport.width + 1 && document.height <= viewport.height + 8
    }

    static func isHorizontal(_ translation: CGPoint) -> Bool {
        guard translation.x.isFinite, translation.y.isFinite else { return false }
        return abs(translation.x) >= 4 && abs(translation.x) > abs(translation.y) * 1.2
    }

    static func origin(start: CGFloat, translation: CGFloat, documentMinX: CGFloat,
                       documentWidth: CGFloat, viewportWidth: CGFloat) -> CGFloat? {
        guard start.isFinite, translation.isFinite, documentMinX.isFinite,
              documentWidth.isFinite, documentWidth >= 0,
              viewportWidth.isFinite, viewportWidth > 0 else { return nil }
        let upper = max(documentMinX, documentMinX + documentWidth - viewportWidth)
        let proposed = start - translation
        guard upper.isFinite, proposed.isFinite else { return nil }
        return min(max(proposed, documentMinX), upper)
    }
}

@MainActor
final class RoomStripDragCoordinator: ObservableObject {
    private enum Axis { case horizontal, vertical }
    private(set) weak var scrollView: NSScrollView?
    private var startOrigin: CGFloat?
    private var axis: Axis?
    private var reportedUnavailable = false
    #if DEBUG
    private static let tracing = ProcessInfo.processInfo.environment["HEARTH_ROOM_STRIP_TRACE"] == "1"
    #endif

    func attach(to next: NSScrollView?) {
        guard scrollView !== next else { return }
        end()
        scrollView = next
        if let next {
            trace("attached: viewport=\(next.contentView.bounds.size), document=\(next.documentView?.frame.size ?? .zero)")
        } else {
            trace("detached")
        }
    }

    func move(translation: CGSize) {
        guard let scrollView, !scrollView.isHiddenOrHasHiddenAncestor,
              let document = scrollView.documentView,
              RoomStripDragGeometry.isHorizontalStrip(document: document.frame.size, viewport: scrollView.contentView.bounds.size) else {
            if !reportedUnavailable {
                trace("drag has no overflowing horizontal strip: viewport=\(scrollView?.contentView.bounds.size ?? .zero), document=\(scrollView?.documentView?.frame.size ?? .zero)")
                reportedUnavailable = true
            }
            return
        }
        let clip = scrollView.contentView
        if axis == nil {
            let horizontal = RoomStripDragGeometry.isHorizontal(CGPoint(x: translation.width, y: translation.height))
            axis = horizontal ? .horizontal : .vertical
            startOrigin = clip.bounds.origin.x
            trace(horizontal ? "horizontal drag began" : "vertical drag ignored")
        }
        guard axis == .horizontal, let startOrigin,
              let x = RoomStripDragGeometry.origin(start: startOrigin,
                translation: translation.width, documentMinX: document.frame.minX,
                documentWidth: document.frame.width, viewportWidth: clip.bounds.width) else { return }
        var proposed = clip.bounds
        proposed.origin.x = x
        let constrained = clip.constrainBoundsRect(proposed)
        // Only X is owned here. Wheel/trackpad and vertical parent scrolling are
        // still handled by the existing native ScrollViews.
        clip.scroll(to: NSPoint(x: constrained.origin.x, y: clip.bounds.origin.y))
        scrollView.reflectScrolledClipView(clip)
        trace("horizontal offset=\(clip.bounds.origin.x)")
    }

    func end() {
        startOrigin = nil
        axis = nil
        reportedUnavailable = false
    }

    /// Explicitly opt in for an offline DEBUG review; never logs room/device
    /// names, identifiers, events, credentials, or user configuration.
    func trace(_ message: @autoclosure () -> String) {
        #if DEBUG
        guard Self.tracing else { return }
        FileHandle.standardError.write(Data(("[Hearth room strip] " + message() + "\n").utf8))
        #endif
    }
}

private struct RoomStripDragProbe: NSViewRepresentable {
    let drag: RoomStripDragCoordinator
    func makeNSView(context: Context) -> RoomStripDragProbeView { RoomStripDragProbeView(drag: drag) }
    func updateNSView(_ view: RoomStripDragProbeView, context: Context) { view.resolve() }
    static func dismantleNSView(_ view: RoomStripDragProbeView, coordinator: ()) { view.retire() }
}

@MainActor
final class RoomStripDragProbeView: NSView {
    private let drag: RoomStripDragCoordinator
    private var retired = false
    private var reportedMissingScroll = false
    private var reportedHierarchy = false

    init(drag: RoomStripDragCoordinator) {
        self.drag = drag
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { return nil }

    /// A background probe never replaces the tile's native hit target.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    static func nearestScrollView(from view: NSView) -> NSScrollView? {
        var ancestor = view.superview
        while let candidate = ancestor {
            if let scroll = candidate as? NSScrollView { return scroll }
            ancestor = candidate.superview
        }
        return nil
    }

    override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); resolve() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); resolve() }
    override func layout() { super.layout(); resolve() }

    func resolve() {
        guard !retired, window != nil else { drag.attach(to: nil); return }
        let scroll = Self.nearestScrollView(from: self)
        if !reportedHierarchy {
            var classes: [String] = []
            var ancestor = superview
            while let view = ancestor, classes.count < 12 {
                classes.append(String(NSStringFromClass(type(of: view)).prefix(160)))
                ancestor = view.superview
            }
            drag.trace("probe ancestors: " + classes.joined(separator: " > "))
            reportedHierarchy = true
        }
        if scroll == nil, !reportedMissingScroll {
            drag.trace("no enclosing native scroll view")
            reportedMissingScroll = true
        }
        if scroll != nil { reportedMissingScroll = false }
        drag.attach(to: scroll)
    }

    func retire() {
        retired = true
        drag.attach(to: nil)
    }
}
