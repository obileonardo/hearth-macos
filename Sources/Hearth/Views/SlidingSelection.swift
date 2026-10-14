import SwiftUI

private struct SelectionFrames: PreferenceKey {
    static var defaultValue: [Int: Anchor<CGRect>] = [:]
    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func selectionFrame(_ index: Int) -> some View {
        anchorPreference(key: SelectionFrames.self, value: .bounds) { [index: $0] }
    }

    /// Exactly one key moves within the track. Keeping one surface alive avoids
    /// crossfading two keys and their shadows during a selection change.
    func slidingSelection(_ selected: Int?, radius: CGFloat, glow: Color = .clear) -> some View {
        modifier(SlidingSelection(selected: selected, radius: radius, glow: glow))
    }
}

private struct SlidingSelection: ViewModifier {
    let selected: Int?
    let radius: CGFloat
    let glow: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.backgroundPreferenceValue(SelectionFrames.self) { frames in
            GeometryReader { geometry in
                if let selected, let anchor = frames[selected] {
                    let frame = geometry[anchor]
                    Key(shape: RoundedRectangle(cornerRadius: radius, style: .continuous), glow: glow)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .transition(.identity)
                        .animation(reduceMotion ? nil : .selectionSlide, value: frame)
                }
            }
            .allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}
