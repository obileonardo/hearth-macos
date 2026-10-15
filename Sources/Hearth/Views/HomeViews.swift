import SwiftUI

/// The heading every page shares: a tiny eyebrow and a title.
struct PageHeader<Trailing: View>: View {
    let eyebrow: String
    let title: String
    var pinnedIllustrations: [DeviceKind] = []
    var pinnedCount: Int? = nil
    var pinnedSymbols: [String] = []
    @ViewBuilder var trailing: Trailing
    /// Set when the page sits inside the Devices tab: a way back to the grid, and the demo switch.
    @Environment(\.sectionChrome) private var chrome

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let chrome {
                Button(action: chrome.back) {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Theme.fg.opacity(0.06)).overlay(Circle().strokeBorder(Theme.hairline)))
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Back to Assets")
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(eyebrow.uppercased()).eyebrow()
                Text(title).font(.system(size: 22, weight: .semibold)).tracking(-0.4)
            }
            Spacer()
            if let chrome, chrome.hasDemo {
                Button(action: chrome.toggleDemo) {
                    HStack(spacing: 5) {
                        Image(systemName: chrome.demoOn ? "stop.fill" : "play.fill").font(.system(size: 9.5, weight: .bold))
                        Text("Demo").font(.system(size: 12.5, weight: .semibold))
                    }
                    .foregroundStyle(chrome.demoOn ? Theme.onBrand : Theme.ink)
                    .padding(.horizontal, 11).frame(height: 30)
                    .background(Capsule().fill(chrome.demoOn ? AnyShapeStyle(Theme.brandFill) : AnyShapeStyle(Theme.fg.opacity(0.06)))
                        .overlay(Capsule().strokeBorder(Theme.hairline)))
                }
                .buttonStyle(PressStyle())
                .help(chrome.demoOn ? "Exit the demo" : "See how this works with sample devices")
                .accessibilityLabel(chrome.demoOn ? "Exit demo" : "Try the demo")
            }
            trailing
        }
        .collapsesInto(eyebrow: eyebrow, title: title, back: chrome?.back,
                       illustrations: pinnedIllustrations, count: pinnedCount, symbols: pinnedSymbols)
    }
}

// MARK: Pinned title

/// The compact card replaces its original heading as that heading reaches the top edge.
struct PinnedTitle {
    var eyebrow: String
    var title: String
    var back: (() -> Void)?
    var illustrations: [DeviceKind] = []
    var count: Int? = nil
    var symbols: [String] = []
    var top: CGFloat
    var bottom: CGFloat
}

struct PinnedTitleKey: PreferenceKey {
    static var defaultValue: PinnedTitle?
    static func reduce(value: inout PinnedTitle?, nextValue: () -> PinnedTitle?) { value = value ?? nextValue() }
}

extension View {
    func collapsesInto(eyebrow: String, title: String, back: (() -> Void)? = nil,
                       illustrations: [DeviceKind] = [], count: Int? = nil, symbols: [String] = []) -> some View {
        modifier(CollapsingPageHeading(eyebrow: eyebrow, title: title, back: back,
                                      illustrations: illustrations, count: count, symbols: symbols))
    }
}

private struct CollapsingPageHeading: ViewModifier {
    let eyebrow: String
    let title: String
    let back: (() -> Void)?
    let illustrations: [DeviceKind]
    let count: Int?
    let symbols: [String]
    @State private var pinnedVisible = false

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { proxy in
                let rect = proxy.frame(in: .named(PinnedTitleBar.space))
                let visible = PinnedTitleBar.progress(headerTop: rect.minY) >= 0.5
                Color.clear.preference(key: PinnedTitleKey.self,
                    value: PinnedTitle(eyebrow: eyebrow, title: title, back: back,
                                       illustrations: illustrations, count: count, symbols: symbols, top: rect.minY, bottom: rect.maxY))
                    // Only the accessibility handoff changes state; continuous
                    // scrolling is handled by the visual effect below.
                    .onChange(of: visible, initial: true) { _, value in pinnedVisible = value }
            })
            .visualEffect { effect, proxy in
                effect.opacity(Double(1 - PinnedTitleBar.progress(headerTop: proxy.frame(in: .named(PinnedTitleBar.space)).minY)))
            }
            .accessibilityHidden(pinnedVisible)
            .allowsHitTesting(!pinnedVisible)
    }
}

/// Inset glass follows the navigation opacity while keeping the heading fully legible.
struct PinnedTitleBar: View {
    nonisolated static let space = "page-scroll"
    static let height: CGFloat = 84
    static let edgeInset: CGFloat = 16
    static let cornerRadius: CGFloat = 18
    let info: PinnedTitle?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private var progress: CGFloat { Self.progress(headerTop: info?.top) }

    nonisolated static func progress(headerTop: CGFloat?) -> CGFloat {
        guard let top = headerTop, top.isFinite else { return 0 }
        return min(max(-top / 18, 0), 1)
    }

    private var page: Page? {
        switch info?.title.lowercased() {
        case "security": .security
        case "rooms": .rooms
        case "assets", "devices": .devices
        case "3d map", "map": .map
        case "activity", "notifications": .activity
        default: nil
        }
    }

    private var symbol: String {
        switch page {
        case .security: "web.camera"
        case .rooms: "door.left.hand.open"
        case .devices: "desktopcomputer"
        case .map: "cube.transparent"
        case .activity: "bell"
        default:
            switch info?.title.lowercased() {
            case "settings": "gearshape"
            case "now playing", "speakers": "speaker.wave.2"
            default: "house"
            }
        }
    }

    var body: some View {
        let p = progress
        let eased = p * p * (3 - 2 * p)
        Group {
            if let info, p > 0 {
                HStack(alignment: .center, spacing: 12) {
                    if let back = info.back {
                        Button(action: back) {
                            Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                                .frame(width: 28, height: 36).contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("Back")
                        .accessibilityHidden(p < 0.5)
                    } else {
                        Group {
                            if let page { StaticSemanticNavigationGlyph(page: page, fallback: symbol) }
                            else { Image(systemName: symbol).font(.system(size: 17, weight: .medium)) }
                        }
                        .foregroundStyle(Theme.ink)
                        .frame(width: 32, height: 36).accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(info.title).font(.system(size: 16, weight: .semibold)).tracking(-0.25).lineLimit(1)
                            .accessibilityAddTraits(.isHeader)
                        Text(info.eyebrow).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.muted)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(info.title), \(info.eyebrow)")
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityHidden(p < 0.5)
                    if !info.illustrations.isEmpty || !info.symbols.isEmpty {
                        illustrationStack(info)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: Self.height)
                .modifier(PinnedHeadingGlassSurface())
                .compositingGroup()
                .shadow(color: .black.opacity(contrast == .increased ? 0 : 0.14), radius: 5, y: 2)
                .opacity(eased)
                .offset(y: reduceMotion ? 0 : (1 - eased) * -2)
                .allowsHitTesting(p >= 0.5)
                // Replace the complete visual subtree so native accessibility
                // cannot retain an invisible heading or decorative descendants.
                .accessibilityRepresentation {
                    if p >= 0.5 {
                        HStack {
                            if let back = info.back {
                                Button("Back", action: back)
                            }
                            Text("\(info.title), \(info.eyebrow)")
                                .accessibilityAddTraits(.isHeader)
                        }
                        .accessibilityElement(children: .contain)
                    }
                }
            }
        }
        // The overlay spans the full panel viewport; these are direct panel margins.
        .padding(.horizontal, Self.edgeInset)
        .padding(.top, Self.edgeInset)
    }

    private func illustrationStack(_ info: PinnedTitle) -> some View {
        let shown = Array(info.illustrations.prefix(3))
        let symbols = shown.isEmpty ? Array(info.symbols.prefix(3)) : []
        let total = info.count ?? (shown.isEmpty ? info.symbols.count : info.illustrations.count)
        let remaining = max(0, total - shown.count - symbols.count)
        return HStack(spacing: -9.5) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, kind in
                DeviceArtView(kind: kind, active: false, size: 26.25)
                    .frame(width: 35, height: 35)
                    .background(Circle().fill(Theme.base))
                    .overlay(Circle().strokeBorder(Theme.raised, lineWidth: 2))
            }
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                Image(systemName: symbol).font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.brand).frame(width: 35, height: 35)
                    .background(Circle().fill(Theme.base))
                    .overlay(Circle().strokeBorder(Theme.raised, lineWidth: 2))
            }
            if remaining > 0 {
                Text("+\(remaining)").font(.system(size: 10, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Theme.ink).frame(width: 35, height: 35)
                    .background(Circle().fill(Theme.base))
                    .overlay(Circle().strokeBorder(Theme.raised, lineWidth: 2))
            }
        }
        // DeviceArtView has its own semantic labels. This stack is decorative,
        // so replace those descendants with an empty accessibility representation.
        .accessibilityRepresentation { EmptyView() }
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(true)
    }
}

/// Uses the navigation's saved surface opacity, with the same accessibility
/// override. Glass is clipped to this card; text and icons are never faded.
private struct PinnedHeadingGlassSurface: ViewModifier {
    @AppStorage(NavigationGlassPreference.key) private var opacity = NavigationGlassPreference.defaultValue
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.hearthDocumentationPreview) private var documentationPreview

    private var solid: Bool { reduceTransparency || contrast == .increased || documentationPreview }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: PinnedTitleBar.cornerRadius, style: .continuous)
    }
    private var surfaceOpacity: Double {
        NavigationGlassPreference.effective(opacity, reduceTransparency: solid, increasedContrast: false)
    }
    private var rim: LinearGradient {
        LinearGradient(colors: [Theme.fg.opacity(0.24), Theme.fg.opacity(0.06)], startPoint: .top, endPoint: .bottom)
    }

    func body(content: Content) -> some View {
        if solid {
            content.background(shape.fill(Theme.raised))
                .overlay(shape.strokeBorder(Theme.hairline, lineWidth: contrast == .increased ? 1.5 : 0.75))
        } else if #available(macOS 26.0, *) {
            content
                .background(shape.fill(Theme.raised.opacity(surfaceOpacity)))
                .glassEffect(.clear, in: shape)
                .overlay(shape.strokeBorder(rim, lineWidth: 0.75))
        } else {
            content.background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(Theme.raised.opacity(surfaceOpacity))
                }
            }
            .overlay(shape.strokeBorder(rim, lineWidth: 0.75))
        }
    }
}

// MARK: Alarm

/// The security system (an Eufy HomeBase, or any Home Assistant alarm) as Away / Home / Off.
struct AlarmControl: View {
    @EnvironmentObject var store: HomeStore
    let entity: Entity
    /// Inside a hub card the hub already shows its name and state.
    var showsHeader = true
    @State private var askingFor: String?
    @State private var code = ""

    private static let arms: [(key: String, label: String, symbol: String, service: String)] = [
        ("away", "Away", "figure.walk", "alarm_arm_away"),
        ("home", "Home", "house", "alarm_arm_home"),
        ("off", "Off", "shield.slash", "alarm_disarm"),
    ]

    private var current: String? {
        switch entity.state {
        case "armed_away", "armed_vacation": "away"
        case "armed_home", "armed_night", "armed_custom_bypass": "home"
        case "disarmed": "off"
        default: nil
        }
    }

    private var needsCode: Bool {
        entity.attributes["code_format"] is String || entity.attributes["code_arm_required"] as? Bool == true
    }

    var body: some View {
        let tint = entity.state == "triggered" ? Theme.live : current == "off" ? Theme.fg : Theme.ok
        VStack(alignment: .leading, spacing: 8) {
            if showsHeader { HStack(spacing: 6) {
                Image(systemName: current == "off" ? "shield" : "shield.lefthalf.filled")
                    .font(.system(size: 12.5, weight: .light))
                    .foregroundStyle(tint)
                Text(entity.name).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(entity.state == "triggered" ? "Alarm triggered" : entity.state.pretty)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 4) }
            Segmented(options: Self.arms.map(\.key), selected: current, tint: tint, id: "arm-\(entity.id)", compact: true) { key in
                let arm = Self.arms.first { $0.key == key }!
                Image(systemName: arm.symbol).font(.system(size: 13, weight: .light))
                Text(arm.label).font(.system(size: 12, weight: .medium))
            } onSelect: { key in
                guard key != current, let arm = Self.arms.first(where: { $0.key == key }) else { return }
                if needsCode {
                    if let saved = Keychain.get("alarm.\(entity.id)") {
                        store.call("alarm_control_panel", arm.service, entity.id, ["code": saved])
                    } else {
                        withAnimation(.glide) { askingFor = arm.service }
                    }
                } else {
                    store.call("alarm_control_panel", arm.service, entity.id)
                }
            }
            if let service = askingFor {
                HStack(spacing: 8) {
                    HearthField(label: "Alarm code", placeholder: "Alarm code", text: $code, secure: true) { send(service) }
                    Button { send(service) } label: {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Theme.onCTA)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Theme.cta))
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Set alarm")
                }
                .transition(.dissolve)
            }
        }
    }

    /// Remembers the code so it's only asked for once.
    private func send(_ service: String) {
        guard !code.isEmpty else { return }
        Keychain.set(code, for: "alarm.\(entity.id)")
        store.call("alarm_control_panel", service, entity.id, ["code": code])
        code = ""
        withAnimation(.glide) { askingFor = nil }
    }
}
