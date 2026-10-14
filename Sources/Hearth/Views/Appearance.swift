import AppKit
import SwiftUI

// MARK: Adaptive colour

extension NSColor {
    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }
}

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastAqua])
            .map { $0 == .darkAqua || $0 == .accessibilityHighContrastDarkAqua } ?? false
    }

    /// The system's Increase Contrast, however it reaches us.
    var isHighContrast: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            || bestMatch(from: [.accessibilityHighContrastDarkAqua, .accessibilityHighContrastAqua, .darkAqua, .aqua])
                .map { $0 == .accessibilityHighContrastDarkAqua || $0 == .accessibilityHighContrastAqua } == true
    }
}

extension Color {
    /// One colour for dark appearances and one for light, each with an optional stronger
    /// version for Increase Contrast. Resolved wherever it's drawn, so it follows live.
    static func adaptive(dark: NSColor, light: NSColor, darkHC: NSColor? = nil, lightHC: NSColor? = nil) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hc = appearance.isHighContrast
            return appearance.isDark ? (hc ? darkHC ?? dark : dark) : (hc ? lightHC ?? light : light)
        })
    }

    /// An accent drawn for the dark: this pale, luminous colour on black, and in the light the
    /// same hue, richer and deep enough to read as text on paper (at least 4.5:1).
    static func accent(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> Color {
        let dark = NSColor.rgb(r, g, b)
        return adaptive(dark: dark, light: dark.deepened(to: 4.6), lightHC: dark.deepened(to: 7))
    }
}

extension NSColor {
    /// WCAG relative luminance.
    var luminance: CGFloat {
        guard let c = usingColorSpace(.sRGB) else { return 0 }
        func lin(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent) + 0.0722 * lin(c.blueComponent)
    }

    func contrast(with other: NSColor) -> CGFloat {
        let a = luminance, b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// The light panel's paper, the darkest light surface text sits on.
    static let lightPaper = NSColor.rgb(0.957, 0.957, 0.965)

    /// The same hue, more saturated and darkened step by step until it reaches `ratio` against paper.
    func deepened(to ratio: CGFloat) -> NSColor {
        guard let c = usingColorSpace(.sRGB) else { return self }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let saturation = s < 0.08 ? s : min(1, s * 1.15 + 0.3)
        var brightness = b
        var out = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        repeat {
            out = NSColor(hue: h, saturation: saturation, brightness: brightness, alpha: 1)
            brightness -= 0.01
        } while out.contrast(with: .lightPaper) < ratio && brightness > 0.05
        return out
    }
}

// MARK: Glow

extension View {
    /// A coloured glow: full strength on black, half on paper, where light doesn't bloom.
    func glow(color: Color, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> some View {
        modifier(Glow(color: color, radius: radius, x: x, y: y))
    }
}

private struct Glow: ViewModifier {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.shadow(color: color.opacity(scheme == .light ? 0.5 : 1), radius: scheme == .light ? radius * 0.75 : radius, x: x, y: y)
    }
}

// MARK: The setting

/// Settings: Appearance. System follows macOS; Light and Dark pin Hearth to one.
enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    static var saved: AppearanceChoice {
        AppearanceChoice(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system
    }

    /// Sets the whole app, the panel and every window, to this appearance.
    @MainActor
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: System accessibility settings

/// Increase Contrast, Reduce Transparency and Reduce Motion as macOS has them now, kept live.
/// Colours read Increase Contrast themselves; this is for the places that change shape or motion.
@MainActor
final class AccessibilityDisplay: ObservableObject {
    static let shared = AccessibilityDisplay()

    @Published private(set) var increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    @Published private(set) var reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    @Published private(set) var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    /// Bumps whenever any of them, or the appearance, changes, so colour caches can be dropped.
    @Published private(set) var revision = 0

    private init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in AccessibilityDisplay.shared.refresh() }
        }
    }

    func refresh() {
        let ws = NSWorkspace.shared
        increaseContrast = ws.accessibilityDisplayShouldIncreaseContrast
        reduceTransparency = ws.accessibilityDisplayShouldReduceTransparency
        reduceMotion = ws.accessibilityDisplayShouldReduceMotion
        revision += 1
    }
}

// MARK: Appearance control

/// System, Light or Dark, as a segmented row in Settings.
struct AppearanceSettings: View {
    @AppStorage("appearance") private var appearance = AppearanceChoice.system.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("APPEARANCE").eyebrow().padding(.leading, 4)
            Segmented(options: AppearanceChoice.allCases, selected: AppearanceChoice(rawValue: appearance) ?? .system,
                      tint: Theme.sand, id: "appearance", compact: true) { choice in
                Image(systemName: choice.symbol).font(.system(size: 12, weight: .regular))
                Text(choice.title).font(.system(size: 12, weight: .semibold))
            } onSelect: { choice in
                appearance = choice.rawValue
                choice.apply()
                AccessibilityDisplay.shared.refresh()
            }
            .accessibilityLabel("Appearance")
            Text("System follows your Mac. Hearth adapts contrast, transparency and motion to your accessibility settings.")
                .font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
