import SwiftUI

/// The scroll content owns this coordinate space, so a child's origin does not
/// change when the user scrolls the viewport.
enum PageContentCoordinates {
    static let space = "HearthPageContent"
}

private struct PageViewportHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

private struct PageDockObstructionKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var hearthPageViewportHeight: CGFloat? {
        get { self[PageViewportHeightKey.self] }
        set { self[PageViewportHeightKey.self] = newValue }
    }

    var hearthPageDockObstruction: CGFloat {
        get { self[PageDockObstructionKey.self] }
        set { self[PageDockObstructionKey.self] = newValue }
    }
}

/// Pure geometry shared with tests. Missing or invalid geometry leaves content
/// at its natural height, as it does in standalone views and image snapshots.
enum CenteredEmptyStateLayout {
    static func minimumHeight(viewportHeight: CGFloat?, contentTop: CGFloat?,
                              dockObstruction: CGFloat) -> CGFloat? {
        guard let viewportHeight, let contentTop,
              viewportHeight.isFinite, viewportHeight > 0,
              contentTop.isFinite, contentTop >= 0,
              dockObstruction.isFinite, dockObstruction >= 0 else { return nil }
        let remaining = viewportHeight - contentTop - dockObstruction
        guard remaining.isFinite else { return nil }
        return max(0, remaining)
    }
}

private struct EmptyStateTopKey: PreferenceKey {
    static var defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        if let next = nextValue() { value = next }
    }
}

/// Centers an empty state in the room below its page controls and above the
/// floating dock. A minimum, rather than fixed, height keeps large text and
/// setup actions available in short windows.
struct CenteredPageEmptyState<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.hearthPageViewportHeight) private var viewportHeight
    @Environment(\.hearthPageDockObstruction) private var dockObstruction
    @State private var contentTop: CGFloat?

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .frame(minHeight: CenteredEmptyStateLayout.minimumHeight(
                viewportHeight: viewportHeight, contentTop: contentTop,
                dockObstruction: dockObstruction), alignment: .center)
            .background {
                if viewportHeight != nil {
                    GeometryReader { geometry in
                        Color.clear.preference(key: EmptyStateTopKey.self,
                            value: geometry.frame(in: .named(PageContentCoordinates.space)).minY)
                    }
                }
            }
            .onPreferenceChange(EmptyStateTopKey.self) { top in
                // The measured origin belongs to unscrolled content; expanding
                // this view cannot move its own leading edge or cause reflow.
                if contentTop != top { contentTop = top }
            }
            .animation(nil, value: contentTop)
    }
}
