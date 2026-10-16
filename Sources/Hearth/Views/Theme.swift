import AppKit
import SwiftUI

/// Ethereal glass: near-black in the dark, soft paper in the light. Light comes from the
/// devices themselves. Every colour here follows the appearance (Settings: System, Light or
/// Dark) and the system's Increase Contrast setting, live.
enum Theme {
    static let panelSize = CGSize(width: 448, height: 696)

    /// The panel itself.
    static let base = Color.adaptive(dark: .rgb(0.027, 0.027, 0.034), light: .rgb(0.957, 0.957, 0.965))
    /// The foreground everything else is mixed from: white in the dark, near-black in the light.
    /// Fills, lines and quiet marks are this at a low opacity, so nesting reads the same way in
    /// both appearances: each layer a little further from the background.
    static let fg = Color.adaptive(dark: .white, light: .rgb(0.07, 0.07, 0.09))
    static let ink = Color.adaptive(dark: .white.withAlphaComponent(0.95), light: .rgb(0.07, 0.07, 0.09))
    static let muted = Color.adaptive(dark: .white.withAlphaComponent(0.68), light: .rgb(0.33, 0.33, 0.36),
                                      darkHC: .white.withAlphaComponent(0.84), lightHC: .rgb(0.2, 0.2, 0.23))
    static let faint = Color.adaptive(dark: .white.withAlphaComponent(0.5), light: .rgb(0.42, 0.42, 0.45),
                                      darkHC: .white.withAlphaComponent(0.7), lightHC: .rgb(0.28, 0.28, 0.31))
    static let hairline = Color.adaptive(dark: .white.withAlphaComponent(0.075), light: .black.withAlphaComponent(0.1),
                                         darkHC: .white.withAlphaComponent(0.42), lightHC: .black.withAlphaComponent(0.48))
    /// Soft depth under cards in the light; none in the dark, where light does that job.
    static let shadow = Color.adaptive(dark: .clear, light: .black.withAlphaComponent(0.07))
    /// Text and marks drawn over a photo or live video, which sits on a dark scrim in either appearance.
    static let onMedia = Color.white
    /// The main button: a white pill in the dark, an ink pill on paper, and the text on it.
    static let cta = Color.adaptive(dark: .white, light: .rgb(0.09, 0.09, 0.11))
    static let onCTA = Color.adaptive(dark: .black, light: .white)
    /// Text on an accent fill (a blue DEMO badge, a lit button): dark on the pale dark-mode
    /// accents, white on the deeper light-mode ones.
    static let onAccent = Color.adaptive(dark: .black.withAlphaComponent(0.88), light: .white)
    /// A raised, opaque disc or tile, like the plates behind device icons.
    static let raised = Color.adaptive(dark: .rgb(0.1, 0.1, 0.115), light: .white)
    /// Inside a text field, and its edge. On paper the field is white like the card it sits on,
    /// so its edge carries it (3:1 or more, as WCAG asks of an input's boundary).
    static let field = Color.adaptive(dark: .black.withAlphaComponent(0.32), light: .white)
    static let fieldEdge = Color.adaptive(dark: .white.withAlphaComponent(0.16), light: .black.withAlphaComponent(0.44),
                                          darkHC: .white.withAlphaComponent(0.42), lightHC: .black.withAlphaComponent(0.6))
    /// The lower edge of a white key's gradient (the selected segment, a lit button).
    static let keyEnd = Color.adaptive(dark: NSColor(white: 0.84, alpha: 1), light: NSColor(white: 0.975, alpha: 1))
    /// Text and marks on a selected key.
    static let onKey = Color.adaptive(dark: .black.withAlphaComponent(0.86), light: .rgb(0.07, 0.07, 0.09))
    /// The recessed track a key slides in: a little darker than the card in the light, so the
    /// white key stands proud of it; a faint lift in the dark.
    static let tray = Color.adaptive(dark: .white.withAlphaComponent(0.045), light: .rgb(0.906, 0.906, 0.92),
                                     darkHC: .white.withAlphaComponent(0.1), lightHC: .rgb(0.86, 0.86, 0.875))
    static let trayEdge = Color.adaptive(dark: .white.withAlphaComponent(0.06), light: .black.withAlphaComponent(0.05),
                                         darkHC: .white.withAlphaComponent(0.3), lightHC: .black.withAlphaComponent(0.3))
    /// A card's own edge on paper: just enough to stop white melting into white.
    static let cardEdge = Color.adaptive(dark: .white.withAlphaComponent(0.1), light: .black.withAlphaComponent(0.075),
                                         darkHC: .white.withAlphaComponent(0.42), lightHC: .black.withAlphaComponent(0.42))
    /// A hover wash on rows and quiet buttons.
    static let hover = Color.adaptive(dark: .white.withAlphaComponent(0.05), light: .black.withAlphaComponent(0.04))

    /// Accents retain their hue in both appearances and read against the panel and cards.
    static let live = Color.adaptive(dark: .rgb(1.0, 0.36, 0.32), light: .rgb(0.78, 0.13, 0.11))
    static let ok = Color.adaptive(dark: .rgb(0.5, 0.9, 0.62), light: .rgb(0.09, 0.47, 0.24))
    static let brand = Color.adaptive(dark: .rgb(0.26, 0.61, 0.99), light: .rgb(0.07, 0.30, 0.65),
                                      darkHC: .rgb(0.48, 0.75, 1.0), lightHC: .rgb(0.04, 0.24, 0.53))
    static let brandEnd = Color.adaptive(dark: .rgb(0.22, 0.55, 0.94), light: .rgb(0.06, 0.24, 0.54),
                                         darkHC: .rgb(0.42, 0.70, 0.99), lightHC: .rgb(0.03, 0.18, 0.44))
    static let brandGradient = LinearGradient(colors: [brand, brandEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
    /// Compatibility name for existing artwork and view accents.
    static let sand = brand
    /// Solid blue fills use white text; luminous brand remains for marks on dark surfaces.
    static let brandFill = Color.adaptive(dark: .rgb(0.10, 0.36, 0.72), light: .rgb(0.07, 0.30, 0.65),
                                          darkHC: .rgb(0.06, 0.28, 0.60), lightHC: .rgb(0.04, 0.24, 0.53))
    static let onBrand = Color.white

    /// Home consumption uses green; solar, grid, battery, warnings and AC modes keep
    /// their own semantic colours. Endpoints also support text on an accent fill.
    static let homeEnergy = Color.adaptive(dark: .rgb(0.27, 0.82, 0.56), light: .rgb(0.04, 0.42, 0.25),
                                           darkHC: .rgb(0.46, 0.92, 0.69), lightHC: .rgb(0.02, 0.32, 0.18))
    static let homeEnergyEnd = Color.adaptive(dark: .rgb(0.21, 0.72, 0.46), light: .rgb(0.03, 0.33, 0.19),
                                              darkHC: .rgb(0.38, 0.84, 0.60), lightHC: .rgb(0.01, 0.25, 0.13))
    static let homeEnergyGradient = LinearGradient(colors: [homeEnergy, homeEnergyEnd], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// The colour of the air for each mode: pale and luminous in the dark, the same hue deep
    /// enough to see against paper in the light.
    static func air(_ mode: String) -> Color {
        switch mode {
        case "heat": .adaptive(dark: .rgb(1.0, 0.74, 0.5), light: .rgb(0.68, 0.31, 0.02))
        case "dry": .adaptive(dark: .rgb(0.62, 0.94, 0.88), light: .rgb(0.0, 0.47, 0.42))
        case "fan_only": .adaptive(dark: .rgb(0.9, 0.92, 0.96), light: .rgb(0.33, 0.37, 0.45))
        case "auto", "heat_cool": .adaptive(dark: .rgb(0.8, 0.78, 1.0), light: .rgb(0.38, 0.3, 0.78))
        case "off": .adaptive(dark: .white.withAlphaComponent(0.5), light: .rgb(0.42, 0.42, 0.45))
        default: .adaptive(dark: .rgb(0.7, 0.85, 1.0), light: .rgb(0.07, 0.4, 0.78))
        }
    }

    static func modeSymbol(_ mode: String) -> String {
        switch mode {
        case "cool": "snowflake"
        case "heat": "sun.max"
        case "dry": "drop"
        case "fan_only": "fan"
        case "auto", "heat_cool": "circle.lefthalf.filled"
        case "off": "power"
        default: "thermometer.medium"
        }
    }

    static func modeName(_ mode: String) -> String {
        switch mode {
        case "fan_only": "Fan"
        case "heat_cool": "Auto"
        case "dry": "Dry"
        default: mode.pretty
        }
    }
}

/// Springs with real mass. Nothing in the panel moves on a plain ease curve.
extension Animation {
    static let glide = Animation.spring(response: 0.52, dampingFraction: 0.86)
    static let snap = Animation.spring(response: 0.3, dampingFraction: 0.78)
    /// For things arriving or leaving: firm, with no overshoot to read as a bounce.
    static let settle = Animation.spring(response: 0.42, dampingFraction: 1)
    static let selectionSlide = Animation.spring(response: 0.42, dampingFraction: 1)
}

// MARK: Surfaces

/// The double bezel. In the dark: a faint outer tray with a hairline holding an inner core with
/// its own top highlight and a concentric radius, so controls read as machined hardware. On
/// paper the tray would read as a thick grey ring, so there the core stands alone: a white card
/// with a whisper of an edge, lifted by a two-layer shadow. A lit card carries its colour as a
/// faint wash from the top and a tinted edge rather than a coloured card.
struct Bezel<Content: View>: View {
    var radius: CGFloat = 22
    var inset: CGFloat = 4
    var lit = false
    var tint: Color = .white
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let inner = max(radius - inset, 4)
        let core = RoundedRectangle(cornerRadius: inner, style: .continuous)
        if scheme == .light {
            content
                .background {
                    core.fill(Color.white)
                        .overlay {
                            if lit {
                                core.fill(LinearGradient(stops: [.init(color: tint.opacity(0.075), location: 0),
                                                                 .init(color: tint.opacity(0.0), location: 0.65)],
                                                         startPoint: .top, endPoint: .bottom))
                            }
                        }
                        .overlay(core.strokeBorder(lit ? tint.opacity(0.32) : Theme.cardEdge, lineWidth: lit ? 0.75 : 0.5))
                        .cardShadow()
                }
                .padding(inset)
        } else {
            content
                .background {
                    // An unlit card is neutral glass whatever its tint; only a lit one takes the colour.
                    core.fill(LinearGradient(colors: [(lit ? tint : .white).opacity(lit ? 0.16 : 0.07),
                                                      (lit ? tint : .white).opacity(lit ? 0.09 : 0.035)],
                                             startPoint: .top, endPoint: .bottom))
                        .overlay {
                            core.strokeBorder(LinearGradient(colors: [Theme.fg.opacity(lit ? 0.22 : 0.12), Theme.fg.opacity(0.02)],
                                                             startPoint: .top, endPoint: .bottom), lineWidth: 0.75)
                        }
                }
                .padding(inset)
                .background {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Theme.fg.opacity(0.025))
                        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.75))
                }
        }
    }
}

extension View {
    /// Depth on paper: a tight contact shadow plus a soft, wide ambient one, so a card lifts
    /// without a muddy halo. Nothing in the dark, where light does that job.
    func cardShadow() -> some View { modifier(CardShadow()) }

    /// A quiet wash under the pointer, for rows and buttons that are clickable.
    func hoverFill<S: Shape>(_ shape: S) -> some View { modifier(HoverFill(shape: shape)) }
}

private struct CardShadow: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        if scheme == .light {
            content.shadow(color: .black.opacity(0.05), radius: 0.75, y: 0.5)
                .shadow(color: .black.opacity(0.055), radius: 10, y: 4)
        } else {
            content
        }
    }
}

private struct HoverFill<S: Shape>: ViewModifier {
    let shape: S
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .background(shape.fill(Theme.hover).opacity(hovering ? 1 : 0))
            .onHover { inside in withAnimation(.snap) { hovering = inside } }
    }
}

/// The selected key: a white key that sits proud of its tray. In the dark it's lit from above
/// and may glow with the control's colour; on paper it's crisp white with a fine edge and a
/// two-layer shadow, so the choice reads at a glance against the darker tray.
struct Key<S: InsettableShape>: View {
    let shape: S
    var glow: Color = .clear
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if scheme == .light {
            shape.fill(LinearGradient(colors: [.white, Theme.keyEnd], startPoint: .top, endPoint: .bottom))
                .overlay(shape.strokeBorder(Color.black.opacity(0.11), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.1), radius: 0.75, y: 0.75)
                .shadow(color: .black.opacity(0.08), radius: 5, y: 2.5)
        } else {
            shape.fill(LinearGradient(colors: [.white, Theme.keyEnd], startPoint: .top, endPoint: .bottom))
                .glow(color: glow, radius: 10)
        }
    }
}

/// The recessed track segmented controls sit in: darker than the card on paper, a machined
/// bezel in the dark.
struct Tray<Content: View>: View {
    var radius: CGFloat = 18
    var inset: CGFloat = 3
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if scheme == .light {
            content
                .padding(inset)
                .background {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.tray)
                        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.trayEdge, lineWidth: 0.5))
                }
        } else {
            Bezel(radius: radius, inset: inset) { content }
        }
    }
}

/// Buttons press in like a physical key, and brighten a touch under the pointer so you can
/// tell what's clickable before you click.
enum PressFeedback {
    static func scale(pressed: Bool, reduceMotion: Bool) -> CGFloat {
        pressed && !reduceMotion ? 0.965 : 1
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressBody(configuration: configuration)
    }

    private struct PressBody: View {
        let configuration: ButtonStyle.Configuration
        @State private var hovering = false
        @Environment(\.colorScheme) private var scheme
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .contentShape(Rectangle())
                .scaleEffect(PressFeedback.scale(pressed: configuration.isPressed, reduceMotion: reduceMotion))
                .brightness(configuration.isPressed ? (scheme == .light ? -0.05 : -0.04)
                            : hovering && enabled ? (scheme == .light ? -0.018 : 0.035) : 0)
                .onHover { inside in hovering = inside }
                .animation(reduceMotion ? nil : .snap, value: configuration.isPressed)
                .animation(reduceMotion ? nil : .snap, value: hovering)
        }
    }
}

/// Elements rise into place, out of a soft blur, one after another. The animation is
/// scoped to opacity, blur and offset only, so it can never drag layout along with it.
struct Reveal: ViewModifier {
    let shown: Bool
    let order: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        // With Reduce Motion, things fade in where they are rather than rising.
        content.animation(.glide.delay(Double(order) * (reduceMotion ? 0.02 : 0.045))) {
            $0.opacity(shown ? 1 : 0)
                .blur(radius: shown || reduceMotion ? 0 : 8)
                .offset(y: shown || reduceMotion ? 0 : 14)
        }
    }
}

/// A status dot with a ring that ripples outward, driven by the clock rather than a
/// repeating animation (which SwiftUI would otherwise apply to the surrounding layout).
struct PulseDot: View {
    let color: Color
    var size: CGFloat = 5
    var live = true
    var period = 1.6

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !live)) { timeline in
            let phase = live ? (timeline.date.timeIntervalSinceReferenceDate / period).truncatingRemainder(dividingBy: 1) : 1
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .background(Circle().fill(color.opacity(0.55 * (1 - phase))).scaleEffect(1 + 1.8 * phase))
        }
    }
}

/// A transition that dissolves through a blur, for moving between devices.
struct BlurFade: ViewModifier {
    let amount: Double
    func body(content: Content) -> some View {
        content.blur(radius: amount * 10).opacity(1 - amount)
    }
}

extension AnyTransition {
    static var dissolve: AnyTransition {
        .modifier(active: BlurFade(amount: 1), identity: BlurFade(amount: 0))
            .combined(with: .scale(scale: 0.98))
    }
}

extension View {
    func reveal(_ shown: Bool, _ order: Int) -> some View { modifier(Reveal(shown: shown, order: order)) }

    /// A tiny uppercase label above a heading.
    func eyebrow() -> some View {
        font(.system(size: 11, weight: .semibold)).tracking(1.1).foregroundStyle(Theme.faint)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Fine film grain over the panel, generated once.
enum Grain {
    static let image: NSImage = {
        let size = 160
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                   samplesPerPixel: 2, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceWhite, bytesPerRow: 0, bitsPerPixel: 0)!
        var rng = SystemRandomNumberGenerator()
        for y in 0..<size {
            for x in 0..<size {
                var pixel = [Int.random(in: 0...255, using: &rng), Int.random(in: 0...60, using: &rng)]
                rep.setPixel(&pixel, atX: x, y: y)
            }
        }
        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(rep)
        return image
    }()
}

/// A native pop-up menu at the pointer.
enum PopupMenu {
    private final class Target: NSObject {
        let action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func fire() { action() }
    }

    static func show(_ options: [String], selected: String?, label: (String) -> String = { $0.pretty },
                     onSelect: @escaping (String) -> Void) {
        let menu = NSMenu()
        var targets: [Target] = []
        for option in options {
            let target = Target { onSelect(option) }
            targets.append(target)
            let item = NSMenuItem(title: label(option), action: #selector(Target.fire), keyEquivalent: "")
            item.target = target
            item.state = option == selected ? .on : .off
            menu.addItem(item)
        }
        withExtendedLifetime(targets) {
            _ = menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }
}

/// A light tick on the trackpad as values step.
enum Haptic {
    static func tick() { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
}

// MARK: Text fields

/// A text field that reads clearly on the dark panel: bright text, a placeholder you can
/// actually see, and an outline that lights up while you type. macOS draws its own
/// placeholder too faint on near-black, so this one draws its own.
struct HearthField: View {
    /// What VoiceOver calls the field.
    let label: String
    let placeholder: String
    @Binding var text: String
    var secure = false
    var contentType: NSTextContentType? = nil
    /// False when the field sits inside a pill that already draws the background.
    var chrome = true
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool
    @Environment(\.hearthDocumentationPreview) private var documentationPreview

    var body: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(placeholder).foregroundStyle(Theme.faint).lineLimit(1).allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            Group {
                if documentationPreview {
                    Text(secure ? String(repeating: "•", count: text.count) : text).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                } else if secure { SecureField("", text: $text) } else { TextField("", text: $text) }
            }
            .textFieldStyle(.plain)
            .textContentType(contentType)
            .foregroundStyle(Theme.ink)
            .focused($focused)
            .onSubmit(onSubmit)
            .accessibilityLabel(label)
        }
        .font(.system(size: chrome ? 13.5 : 12.5))
        .padding(.horizontal, chrome ? 14 : 0)
        .frame(height: chrome ? 40 : 26)
        .background {
            if chrome {
                RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Theme.field)
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(focused ? Theme.ink.opacity(0.6) : Theme.fieldEdge, lineWidth: focused ? 1.25 : 0.75))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .animation(.snap, value: focused)
    }
}

/// A field with its name above it.
struct LabeledField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var secure = false
    var contentType: NSTextContentType? = nil
    var onSubmit: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                .accessibilityHidden(true)
            HearthField(label: label, placeholder: placeholder, text: $text, secure: secure,
                        contentType: contentType, onSubmit: onSubmit)
        }
    }
}
