import SwiftUI

/// Mount the destination immediately. SwiftUI retains the actual departing view
/// for its transition, preserving heavy scene state instead of rebuilding a copy.
struct ScreenFlow<Route: Equatable, Content: View>: View {
    let route: Route
    var depth = 0
    @ViewBuilder let content: (Route) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayed: Route
    @State private var displayedDepth: Int
    @State private var direction = 1.0
    @State private var generation = 0

    init(route: Route, depth: Int = 0, @ViewBuilder content: @escaping (Route) -> Content) {
        self.route = route
        self.depth = depth
        self.content = content
        _displayed = State(initialValue: route)
        _displayedDepth = State(initialValue: depth)
    }

    private var transition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(insertion: .opacity.combined(with: .offset(x: 6 * direction)),
                           removal: .opacity.combined(with: .offset(x: -4 * direction)))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            content(displayed)
                .id(generation)
                .transition(transition)
                .allowsHitTesting(displayed == route)
                .accessibilityHidden(displayed != route)
        }
        .animation(.timingCurve(0.2, 0, 0.15, 1, duration: reduceMotion ? 0.1 : 0.2), value: generation)
        // The local route transition owns motion; parent springs must not
        // interpolate the intrinsic sizes of every card in the destination.
        .transaction { $0.animation = nil }
        .onChange(of: route) { _, next in
            direction = depth < displayedDepth ? -1 : 1
            displayed = next
            displayedDepth = depth
            generation += 1
        }
        .onDisappear {
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) {
                displayed = route
                displayedDepth = depth
            }
        }
    }
}
