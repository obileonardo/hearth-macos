import SwiftUI

/// The pages along the bottom: equal-width icons on a strip of glass, with a lens of glass
/// that slides under the one you're on. Nothing changes width, so the lens has a fixed
/// target and glides there in one movement. The page's name is already at the top.
struct Dock: View {
    let pages: [Page]
    let selected: Page?
    var badge: (Page) -> Int = { _ in 0 }
    let label: (Page) -> (symbol: String, title: String)
    /// Settings lives at the end of the pill, after a hairline; the lens slides onto it too.
    var settingsOn = false
    var status: (color: Color, text: String)? = nil
    var onSettings: () -> Void = {}
    let onSelect: (Page) -> Void
    /// The lens stretches along its path while it travels, then settles, like a drop of liquid.
    @State private var stretch: CGFloat = 1
    @State private var settling: Task<Void, Never>?
    /// Reduce Motion: the lens moves straight to the tab, without the stretch or the bounce.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let tab = CGSize(width: 44, height: 34)
    /// A little give at the end, like something with weight settling into place.
    static let slide = Animation.spring(response: 0.38, dampingFraction: 0.94)

    private var index: Int? { settingsOn ? pages.count : selected.flatMap { pages.firstIndex(of: $0) } }
    /// The hairline between the pages and settings.
    private static let gap: CGFloat = 9

    /// Seven tabs fit at full width. Beyond that (say, three air conditioners) they narrow, so the
    /// dock never grows wider than the panel and pushes the page out with it.
    private var tabWidth: CGFloat { pages.count <= 7 ? Self.tab.width : max(30, 316 / CGFloat(pages.count)) }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(pages, id: \.self) { page in
                tab(page)
            }
            if !pages.isEmpty {
                Capsule().fill(Theme.hairline).frame(width: 1, height: 18)
                    .frame(width: Self.gap)
            }
            settingsTab
        }
        // One lens for the whole dock. It never leaves; it only moves, so there is nothing to fade.
        .background(alignment: .leading) {
            if let index {
                Lens()
                    .frame(width: tabWidth, height: Self.tab.height)
                    .scaleEffect(x: stretch, y: 2 - stretch, anchor: .center)
                    .offset(x: CGFloat(index) * tabWidth + (index >= pages.count && !pages.isEmpty ? Self.gap : 0))
                    .animation(reduceMotion ? .easeOut(duration: 0.15) : Self.slide, value: index)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .padding(4)
        .modifier(NavigationGlassSurface())
        .onChange(of: index) { old, new in
            settling?.cancel()
            guard !reduceMotion, let old, let new, old != new else {
                stretch = 1
                return
            }
            let distance = CGFloat(abs(new - old))
            withAnimation(.spring(response: 0.14, dampingFraction: 0.95)) {
                stretch = 1 + min(distance, 3) * 0.018
            }
            settling = Task { @MainActor in
                do { try await Task.sleep(for: .milliseconds(140)) } catch { return }
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.94)) { stretch = 1 }
            }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced { settling?.cancel(); stretch = 1 }
        }
        .onDisappear { settling?.cancel(); settling = nil; stretch = 1 }

    }

    private var settingsTab: some View {
        Button(action: onSettings) {
            Image(systemName: "gearshape")
                .symbolVariant(settingsOn ? .fill : .none)
                .font(.system(size: 15, weight: settingsOn ? .semibold : .regular))
                .frame(width: 17, height: 17)
                .foregroundStyle(settingsOn ? Theme.sand : Theme.muted)
                .rotationEffect(.degrees(settingsOn && !reduceMotion ? 60 : 0))
                .animation(.settle, value: settingsOn)
                .frame(width: tabWidth, height: Self.tab.height)
                .overlay(alignment: .topTrailing) {
                    if let status {
                        Circle().fill(status.color).frame(width: 6, height: 6)
                            .overlay(Circle().strokeBorder(Theme.base, lineWidth: 1.5))
                            .glow(color: status.color.opacity(0.45), radius: 1.5)
                            .offset(x: -9, y: 7)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .help(status.map { "Settings · \($0.text)" } ?? "Settings")
        .accessibilityLabel(settingsOn ? "Close settings" : "Settings")
        .accessibilityValue(status?.text ?? "")
        .accessibilityAddTraits(settingsOn ? .isSelected : [])
    }

    private func tab(_ page: Page) -> some View {
        let on = page == selected
        let l = label(page)
        return Button { onSelect(page) } label: {
            NavigationGlyph(page: page, fallback: l.symbol, selected: on)
                .frame(width: tabWidth, height: Self.tab.height)
                .overlay(alignment: .topTrailing) {
                    let count = badge(page)
                    if count > 0, !on {
                        Text(count > 9 ? "9+" : "\(count)")
                            .font(.system(size: 9.5, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 4).frame(minWidth: 15, minHeight: 15)
                            .background(Capsule().fill(Theme.live).glow(color: Theme.live.opacity(0.5), radius: 4))
                            .offset(x: -3, y: 1)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .help(l.title)
        .accessibilityLabel(l.title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The selected tab's lens: a bead of clearer, brighter glass with light caught on its rim.
private struct Lens: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.hearthDocumentationPreview) private var documentationPreview
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        if reduceTransparency || contrast == .increased {
            Capsule().fill(Theme.raised)
                .overlay(Capsule().strokeBorder(Theme.brand, lineWidth: 1))
        } else if #available(macOS 26.0, *), !documentationPreview {
            Capsule().fill(.clear)
                .glassEffect(.clear, in: Capsule())
                .overlay(Capsule().strokeBorder(LinearGradient(colors: [Theme.fg.opacity(0.22), Theme.fg.opacity(0.03)],
                                                               startPoint: .top, endPoint: .bottom), lineWidth: 0.75))
        } else {
            Capsule()
                .fill(LinearGradient(colors: [Theme.fg.opacity(0.13), Theme.fg.opacity(0.08)], startPoint: .top, endPoint: .bottom))
                .overlay(Capsule().strokeBorder(LinearGradient(colors: [Theme.fg.opacity(0.22), Theme.fg.opacity(0.03)],
                                                               startPoint: .top, endPoint: .bottom), lineWidth: 0.75))
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        }
    }
}

extension View {
    /// Apple's Liquid Glass on macOS 26 and later; frosted material with a lit rim before that;
    /// a solid surface with a clear edge when Reduce Transparency is on.
    func liquidGlass<S: Shape>(in shape: S) -> some View {
        modifier(LiquidGlass(shape: shape))
    }
}

private struct LiquidGlass<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.hearthDocumentationPreview) private var documentationPreview
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased || documentationPreview {
            content
                .background(shape.fill(Theme.raised))
                .overlay(shape.stroke(Theme.hairline, lineWidth: 1))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(shape.fill(.ultraThinMaterial))
                .overlay(shape.stroke(LinearGradient(colors: [Theme.fg.opacity(0.22), Theme.fg.opacity(0.04)],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 0.75))
        }
    }
}
