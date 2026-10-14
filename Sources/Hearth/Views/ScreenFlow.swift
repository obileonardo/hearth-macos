import SwiftUI

/// Page navigation animates the surface, never the cards' intrinsic heights.
/// Swap the route while the surface is invisible so a scrolled overview does
/// not accordion into a shorter detail page. Child controls keep their motion.
struct ScreenFlow<Route: Equatable, Content: View>: View {
    let route: Route
    var depth = 0
    @ViewBuilder let content: (Route) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayed: Route
    @State private var displayedDepth: Int
    @State private var opacity = 1.0
    @State private var displacement = 0.0
    @State private var arriving = true
    @State private var generation = 0

    init(route: Route, depth: Int = 0, @ViewBuilder content: @escaping (Route) -> Content) {
        self.route = route
        self.depth = depth
        self.content = content
        _displayed = State(initialValue: route)
        _displayedDepth = State(initialValue: depth)
    }

    var body: some View {
        content(displayed)
            .animation(.timingCurve(0.22, 0, 0.2, 1, duration: arriving ? 0.24 : 0.10)) {
                $0.opacity(opacity).offset(x: reduceMotion ? 0 : displacement)
            }
            // Stop a parent navigation spring from resizing this page's cards.
            .transaction { $0.animation = nil }
            .allowsHitTesting(displayed == route && opacity == 1)
            .accessibilityHidden(displayed != route)
            .onChange(of: route) { _, next in navigate(to: next) }
            .onChange(of: reduceMotion) { _, reduced in
                if reduced { reset() }
            }
            .onDisappear { reset() }
    }

    private func navigate(to next: Route) {
        generation += 1
        let token = generation
        let targetDepth = depth
        let direction = targetDepth < displayedDepth ? -1.0 : 1.0
        arriving = false
        opacity = 0
        displacement = -4 * direction
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) {
            guard generation == token else { return }
            var swap = Transaction()
            swap.disablesAnimations = true
            withTransaction(swap) {
                displayed = next
                displayedDepth = targetDepth
                arriving = true
                displacement = 8 * direction
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) {
                guard generation == token else { return }
                opacity = 1
                displacement = 0
            }
        }
    }

    private func reset() {
        generation += 1
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            displayed = route
            displayedDepth = depth
            opacity = 1
            displacement = 0
            arriving = true
        }
    }
}
