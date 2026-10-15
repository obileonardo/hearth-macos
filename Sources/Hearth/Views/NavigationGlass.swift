import SwiftUI

/// Changes only the navigation surface; labels and icons always keep full opacity.
enum NavigationGlassPreference {
    static let key = "navigation.glassOpacity"
    static let defaultValue = 0.55

    static func normalized(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : defaultValue
    }

    static func effective(_ value: Double, reduceTransparency: Bool, increasedContrast: Bool) -> Double {
        reduceTransparency || increasedContrast ? 1 : normalized(value)
    }
}

struct NavigationGlassSurface: ViewModifier {
    @AppStorage(NavigationGlassPreference.key) private var opacity = NavigationGlassPreference.defaultValue
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.hearthDocumentationPreview) private var documentationPreview

    private var solid: Bool { reduceTransparency || contrast == .increased || documentationPreview }
    private var surfaceOpacity: Double {
        NavigationGlassPreference.effective(opacity, reduceTransparency: solid, increasedContrast: false)
    }

    func body(content: Content) -> some View {
        if solid {
            content.background(Capsule().fill(Theme.raised))
                .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        } else if #available(macOS 26.0, *) {
            content
                .background(Capsule().fill(Theme.raised.opacity(surfaceOpacity)))
                .glassEffect(.clear, in: Capsule())
                .overlay(Capsule().strokeBorder(rim, lineWidth: 0.75))
        } else {
            content
                .background {
                    ZStack {
                        Capsule().fill(.ultraThinMaterial)
                        Capsule().fill(Theme.raised.opacity(surfaceOpacity))
                    }
                }
                .overlay(Capsule().strokeBorder(rim, lineWidth: 0.75))
        }
    }

    private var rim: LinearGradient {
        LinearGradient(colors: [Theme.fg.opacity(0.24), Theme.fg.opacity(0.06)], startPoint: .top, endPoint: .bottom)
    }
}

struct NavigationGlassSettings: View {
    @AppStorage(NavigationGlassPreference.key) private var opacity = NavigationGlassPreference.defaultValue
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.hearthDocumentationPreview) private var documentationPreview

    private var overridden: Bool { reduceTransparency || contrast == .increased }
    private var displayedValue: Double {
        NavigationGlassPreference.effective(opacity, reduceTransparency: reduceTransparency, increasedContrast: contrast == .increased)
    }
    private var value: Binding<Double> {
        Binding(get: { displayedValue }, set: { opacity = NavigationGlassPreference.normalized($0) })
    }

    var body: some View {
        Bezel(radius: 18, inset: 3) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Glass opacity").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text(displayedValue, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(Theme.muted)
                }
                if documentationPreview {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.fg.opacity(0.12)).frame(height: 3)
                            Circle().fill(Theme.ink).frame(width: 12, height: 12)
                                .offset(x: max(0, proxy.size.width - 12) * displayedValue)
                        }.frame(maxHeight: .infinity)
                    }.frame(height: 18).accessibilityHidden(true)
                } else {
                    Slider(value: value, in: 0...1) { Text("Navigation glass opacity") }
                        .labelsHidden().tint(Theme.brand)
                        .disabled(overridden)
                        .accessibilityLabel("Navigation glass opacity")
                        .accessibilityValue(displayedValue.formatted(.percent.precision(.fractionLength(0))))
                        .accessibilityHint("Changes the floating bar's surface without fading its icons")
                }
                HStack {
                    Text("Clearer")
                    Spacer()
                    Text("More opaque")
                }.font(.system(size: 11)).foregroundStyle(Theme.muted)
                if overridden {
                    Text("Your Mac’s accessibility settings keep the bar opaque.")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
        }
    }
}
