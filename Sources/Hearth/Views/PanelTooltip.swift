import SwiftUI

/// Geometry belongs to the app viewport, rather than macOS's cursor-positioned
/// help window. Center on the source, shift inward at edges, and flip vertically.
enum PanelTooltipPlacement {
    static func frame(anchor: CGRect, viewport: CGSize, bubble: CGSize,
                      margin: CGFloat = 12, gap: CGFloat = 8) -> CGRect? {
        let values = [anchor.minX, anchor.minY, anchor.width, anchor.height,
                      viewport.width, viewport.height, bubble.width, bubble.height, margin, gap]
        guard values.allSatisfy(\.isFinite), viewport.width > 0, viewport.height > 0,
              bubble.width > 0, bubble.height > 0, anchor.width >= 0, anchor.height >= 0,
              margin >= 0, gap >= 0 else { return nil }
        let inset = min(margin, min(viewport.width, viewport.height) / 4)
        let bounds = CGRect(origin: .zero, size: viewport).insetBy(dx: inset, dy: inset)
        let size = CGSize(width: min(bubble.width, bounds.width), height: min(bubble.height, bounds.height))
        let x = min(max(anchor.midX - size.width / 2, bounds.minX), bounds.maxX - size.width)
        let below = anchor.maxY + gap
        let above = anchor.minY - gap - size.height
        let preferredY = below + size.height <= bounds.maxY ? below : above
        let y = min(max(preferredY, bounds.minY), bounds.maxY - size.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}

private struct PanelTooltipRequest {
    let message: String
    let anchor: Anchor<CGRect>
    let requestedAt: TimeInterval
}

private struct PanelTooltipKey: PreferenceKey {
    static var defaultValue: [PanelTooltipRequest] { [] }
    static func reduce(value: inout [PanelTooltipRequest], nextValue: () -> [PanelTooltipRequest]) {
        value.append(contentsOf: nextValue())
    }
}

private struct PanelTooltipSource: ViewModifier {
    let message: String
    let presented: Bool
    @State private var hovering = false
    @State private var ready = false
    @State private var requestedAt = 0.0

    func body(content: Content) -> some View {
        content
            .anchorPreference(key: PanelTooltipKey.self, value: .bounds) { anchor in
                ready || presented ? [PanelTooltipRequest(message: message, anchor: anchor, requestedAt: requestedAt)] : []
            }
            .onHover { inside in
                hovering = inside
                if inside { requestedAt = Date.timeIntervalSinceReferenceDate }
                else { ready = false }
            }
            .task(id: hovering) {
                guard hovering else { return }
                do { try await Task.sleep(for: .milliseconds(280)) } catch { return }
                guard hovering, !Task.isCancelled else { return }
                ready = true
            }
            .onChange(of: presented) { _, now in
                if now { requestedAt = Date.timeIntervalSinceReferenceDate }
            }
            .onReceive(NotificationCenter.default.publisher(for: HearthNavigation.panelVisibilityChanged)) { note in
                if note.object as? Bool == false { hovering = false; ready = false }
            }
            .accessibilityHint(message)
    }
}

/// Shared by normal camera controls and keyboard-accessible information buttons.
extension View {
    func panelTooltip(_ message: String, presented: Bool = false) -> some View {
        modifier(PanelTooltipSource(message: message, presented: presented))
    }

    func panelTooltipHost() -> some View {
        overlayPreferenceValue(PanelTooltipKey.self) { requests in
            GeometryReader { proxy in
                if let request = requests.max(by: { $0.requestedAt < $1.requestedAt }) {
                    let anchor = proxy[request.anchor]
                    if anchor.intersects(CGRect(origin: .zero, size: proxy.size)) {
                        PanelTooltipLayout(anchor: anchor, viewport: proxy.size) {
                            PanelTooltipBubble(message: request.message)
                        }
                    }
                }
            }
            // Hover help never intercepts a card, scroll gesture or dock control.
            .allowsHitTesting(false)
        }
    }
}

private struct PanelTooltipLayout: Layout {
    let anchor: CGRect
    let viewport: CGSize

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { viewport }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let content = subviews.first else { return }
        let width = max(1, min(280, viewport.width - 24))
        let size = content.sizeThatFits(ProposedViewSize(width: width, height: nil))
        guard let frame = PanelTooltipPlacement.frame(anchor: anchor, viewport: viewport,
                                                      bubble: CGSize(width: width, height: size.height)) else { return }
        content.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                      anchor: .topLeading, proposal: ProposedViewSize(frame.size))
    }
}

private struct PanelTooltipBubble: View {
    let message: String
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Text(message)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.leading)
            .lineLimit(10)
            .truncationMode(.tail)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                if reduceTransparency || contrast == .increased { shape.fill(Theme.raised) }
                else { shape.fill(.regularMaterial) }
            }
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.16), radius: 6, y: 2)
            .accessibilityHidden(true) // Full help is already attached to its source control.
    }
}

struct PanelInfoButton: View {
    let message: String
    @State private var presented = false
    @FocusState private var focused: Bool

    var body: some View {
        Button { presented.toggle() } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(.black.opacity(0.55)))
        }
        .buttonStyle(.plain)
        .focused($focused)
        .onChange(of: focused) { _, now in if !now { presented = false } }
        .accessibilityLabel("Camera information")
        .panelTooltip(message, presented: presented)
        .onHover { if !$0 { presented = false } }
        .onReceive(NotificationCenter.default.publisher(for: HearthNavigation.panelVisibilityChanged)) { note in
            if note.object as? Bool == false { presented = false }
        }
        .onKeyPress(.escape) {
            guard presented else { return .ignored }
            presented = false
            return .handled
        }
    }
}
