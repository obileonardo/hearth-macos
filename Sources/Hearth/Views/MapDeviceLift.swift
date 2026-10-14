import AppKit
import SwiftUI

/// Native drag lifecycle lets the row lift away and return even when a drag is
/// cancelled outside the map. The drag image is the actual card, not a text badge.
struct MapDeviceLift<Content: View>: NSViewRepresentable {
    let payload: String
    var accessibilityLabel: String = "Place device on map"
    let onLift: () -> Void
    let onEnd: () -> Void
    let onSelect: () -> Void
    var onPlace: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> LiftView<Content> {
        LiftView(rootView: content())
    }

    func updateNSView(_ view: LiftView<Content>, context: Context) {
        view.rootView = content()
        view.payload = payload
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel(accessibilityLabel)
        view.setAccessibilityHelp(onPlace == nil ? "Press to inspect. Drag to move." : "Drag to place, or use Place on current floor (Option Return).")
        view.onLift = onLift
        view.onEnd = onEnd
        view.onSelect = onSelect
        view.onPlace = onPlace
        if onPlace != nil {
            view.setAccessibilityCustomActions([NSAccessibilityCustomAction(name: "Place on current floor", handler: { [weak view] in
                guard let action = view?.onPlace else { return false }
                action()
                return true
            })])
        } else { view.setAccessibilityCustomActions(nil) }
    }
}

final class LiftView<Content: View>: NSView, NSDraggingSource {
    private let host: NSHostingView<Content>
    var rootView: Content {
        get { host.rootView }
        set { host.rootView = newValue }
    }
    override var isFlipped: Bool { true }

    init(rootView: Content) {
        host = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        host.autoresizingMask = [.width, .height]
        addSubview(host)
        focusRingType = .exterior
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        host.frame = bounds
    }
    var payload = ""
    var onLift: (() -> Void)?
    var onEnd: (() -> Void)?
    var onSelect: (() -> Void)?
    var onPlace: (() -> Void)?
    private var down: CGPoint?
    private var lifting = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
    }
    override func accessibilityPerformPress() -> Bool {
        onSelect?()
        return true
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 && event.modifierFlags.contains(.option), let onPlace { onPlace() }
        else if event.keyCode == 36 || event.keyCode == 49 { onSelect?() }
        else { super.keyDown(with: event) }
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        down = convert(event.locationInWindow, from: nil)
        lifting = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !lifting, let down else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - down.x, point.y - down.y) > 4 else { return }
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return }
        cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        let item = NSDraggingItem(pasteboardWriter: payload as NSString)
        item.setDraggingFrame(bounds, contents: image)
        lifting = true
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        onLift?()
    }

    override func mouseUp(with event: NSEvent) {
        if !lifting { onSelect?() }
        down = nil
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        lifting = false
        down = nil
        onEnd?()
        NSCursor.arrow.set()
    }
}
