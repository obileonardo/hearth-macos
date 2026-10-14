import SwiftUI

/// The heading every page shares: a tiny eyebrow and a title.
struct PageHeader<Trailing: View>: View {
    let eyebrow: String
    let title: String
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
                .accessibilityLabel("Back to Devices")
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
                    .foregroundStyle(chrome.demoOn ? Theme.onAccent : Theme.ink)
                    .padding(.horizontal, 11).frame(height: 30)
                    .background(Capsule().fill(chrome.demoOn ? AnyShapeStyle(Color.accent(0.98, 0.8, 0.42)) : AnyShapeStyle(Theme.fg.opacity(0.06)))
                        .overlay(Capsule().strokeBorder(Theme.hairline)))
                }
                .buttonStyle(PressStyle())
                .help(chrome.demoOn ? "Exit the demo" : "See how this works with sample devices")
                .accessibilityLabel(chrome.demoOn ? "Exit demo" : "Try the demo")
            }
            trailing
        }
        .collapsesInto(eyebrow: eyebrow, title: title, back: chrome?.back)
    }
}

// MARK: Pinned title

/// What the slim bar at the top shows once a page's own header has scrolled away.
struct PinnedTitle {
    var eyebrow: String
    var title: String
    var back: (() -> Void)?
    /// The header's bottom edge, in the scroll view's space; below zero once it's gone.
    var bottom: CGFloat
}

struct PinnedTitleKey: PreferenceKey {
    static var defaultValue: PinnedTitle?
    static func reduce(value: inout PinnedTitle?, nextValue: () -> PinnedTitle?) { value = value ?? nextValue() }
}

extension View {
    /// Reports this header to the page's scroll view, which pins a slim copy once it scrolls away.
    func collapsesInto(eyebrow: String, title: String, back: (() -> Void)? = nil) -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: PinnedTitleKey.self,
                                   value: PinnedTitle(eyebrow: eyebrow, title: title, back: back,
                                                      bottom: g.frame(in: .named(PinnedTitleBar.space)).maxY))
        })
    }
}

/// The page's name and summary, pinned to the top while you scroll, so you always know where you are.
/// It follows the scroll rather than switching: as the page's own header slides away, the bar's
/// frosted glass and title ease in over the same distance.
struct PinnedTitleBar: View {
    static let space = "page-scroll"
    /// How far down the scroll view the bar and its soft edge reach.
    static let height: CGFloat = 40
    let info: PinnedTitle?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// 0 while the page header is in view, 1 once it has gone.
    private var progress: CGFloat {
        guard let bottom = info?.bottom else { return 0 }
        return min(max((26 - bottom) / 34, 0), 1)
    }

    var body: some View {
        let p = progress
        let eased = p * p * (3 - 2 * p)
        ZStack(alignment: .top) {
            // Frosted glass that thins out towards its lower edge, over a little of the panel's colour.
            // With Reduce Transparency it's the panel's own colour, solid.
            Rectangle().fill(reduceTransparency ? AnyShapeStyle(Theme.base) : AnyShapeStyle(.ultraThinMaterial))
                .overlay(Theme.base.opacity(reduceTransparency ? 1 : 0.55))
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.62),
                                            .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                .frame(height: Self.height + 22 + 14)
                .padding(.horizontal, -22)
                .opacity(eased)
                .allowsHitTesting(false)

            if let info {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if let back = info.back {
                        Button(action: back) {
                            Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Theme.fg.opacity(0.08)).overlay(Circle().strokeBorder(Theme.hairline)))
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel("Back")
                        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                    }
                    Text(info.title).font(.system(size: 16, weight: .semibold)).tracking(-0.25).lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 12)
                    Text(info.eyebrow.uppercased()).eyebrow().lineLimit(1).truncationMode(.head)
                }
                .padding(.top, 14)
                .opacity(eased)
                .offset(y: (1 - eased) * 10)
                .blur(radius: (1 - eased) * 3)
                .allowsHitTesting(p > 0.5)
            }
        }
        .padding(.top, -22)
        .accessibilityHidden(p < 0.5)
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
