import AppKit
import CoreImage
import SwiftUI

/// Privacy blur: softens every camera picture and live feed, like a video call's background
/// blur, while the controls and labels around them stay sharp. For showing Hearth to other
/// people (a screen share, a post) without showing where you live. The cameras keep running.
enum PrivacyBlur {
    static let key = "privacy.blur"
    static let amountKey = "privacy.blurAmount"
    /// How strong the blur is, from a soft haze (0) to frosted glass (1).
    static var amount: Double { UserDefaults.standard.object(forKey: amountKey) as? Double ?? 0.45 }
    /// The amount as a blur radius. 0.45 is about 14 pt: you can see something moving, not who.
    static func radius(_ amount: Double) -> CGFloat { 4 + CGFloat(amount) * 22 }
    static var radius: CGFloat { radius(amount) }
}

extension View {
    /// Blurs this picture when privacy blur is on. Apply it to the image itself, inside its clip.
    func privacyBlurred() -> some View { modifier(PrivacyBlurModifier()) }
}

private struct PrivacyBlurModifier: ViewModifier {
    @AppStorage(PrivacyBlur.key) private var on = false
    @AppStorage(PrivacyBlur.amountKey) private var amount = 0.45
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            // Opaque keeps the edges solid, and a slight zoom hides the soft border blur leaves.
            .blur(radius: on ? PrivacyBlur.radius(amount) : 0, opaque: true)
            .scaleEffect(on ? 1.03 + amount * 0.06 : 1)
            .animation(reduceMotion ? nil : .glide, value: on)
    }
}

/// The eye that turns privacy blur on and off, for the Security page and the camera window.
struct PrivacyBlurButton: View {
    @AppStorage(PrivacyBlur.key) private var on = false
    var onMedia = false

    var body: some View {
        Button {
            withAnimation(.glide) { on.toggle() }
        } label: {
            Image(systemName: on ? "eye.slash.fill" : "eye")
                .font(.system(size: 13, weight: on ? .semibold : .regular))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(onMedia ? Theme.onMedia : (on ? Theme.onKey : Theme.ink))
                .frame(width: onMedia ? 32 : 34, height: onMedia ? 32 : 34)
                .background {
                    if onMedia {
                        Circle().fill(.ultraThinMaterial).overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 0.75))
                    } else if on {
                        Key(shape: Circle())
                    } else {
                        Circle().fill(Theme.fg.opacity(0.05)).overlay(Circle().strokeBorder(Theme.hairline))
                    }
                }
        }
        .buttonStyle(PressStyle())
        .help(on ? "Privacy blur is on: camera pictures are blurred. Click to show them." : "Blur camera pictures, for sharing your screen")
        .accessibilityLabel("Privacy blur")
        .accessibilityValue(on ? "On" : "Off")
    }
}

extension NSView {
    /// Blurs a native view's own drawing (the HLS player) for privacy blur.
    func setPrivacyBlur(_ on: Bool, amount: Double = PrivacyBlur.amount) {
        wantsLayer = true
        layerUsesCoreImageFilters = true
        contentFilters = on ? [CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: PrivacyBlur.radius(amount)])].compactMap { $0 } : []
    }
}

/// The eye on the lead camera's frame. Click to blur every camera. While it's on, the strength
/// slider slides out beside it, then folds into a small drop once you're done, so it stops
/// taking up the frame. Click the drop to adjust again.
struct PrivacyBlurControl: View {
    @AppStorage(PrivacyBlur.key) private var on = false
    @AppStorage(PrivacyBlur.amountKey) private var amount = 0.45
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @State private var dragging = false
    @State private var fold: Task<Void, Never>?

    private var motion: Animation? { reduceMotion ? nil : .settle }

    var body: some View {
        HStack(spacing: 8) {
            if on {
                if expanded { slider } else { drop }
            }
            eye
        }
        .onChange(of: on) { _, now in
            if now { show(for: 3) } else { fold?.cancel(); withAnimation(motion) { expanded = false } }
        }
        .onChange(of: amount) { _, _ in
            if expanded, !dragging { foldLater() }
        }
        .onDisappear { fold?.cancel() }
    }

    // MARK: Pieces

    private var slider: some View {
        HStack(spacing: 6) {
            Image(systemName: "drop").font(.system(size: 9, weight: .semibold))
            Slider(value: $amount, in: 0...1) { editing in
                dragging = editing
                if editing { fold?.cancel() } else { foldLater() }
            }
            .controlSize(.mini)
            .tint(.white)
            .frame(width: 84)
            .accessibilityLabel("Blur strength")
            .accessibilityValue("\(Int(amount * 100)) percent")
            Image(systemName: "drop.fill").font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
            .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.75)))
        .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .trailing)))
    }

    /// The folded slider: a small drop whose ring shows how strong the blur is.
    private var drop: some View {
        Button { show(for: 3) } label: {
            ZStack {
                Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                Circle().strokeBorder(.white.opacity(0.14), lineWidth: 0.75)
                Circle().trim(from: 0, to: max(0.04, amount))
                    .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(2.5)
                Image(systemName: "drop.fill").font(.system(size: 7.5, weight: .bold)).foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: 22, height: 22)
        }
        .buttonStyle(PressStyle())
        .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .trailing)))
        .help("Blur strength \(Int(amount * 100))%. Click to adjust")
        .accessibilityLabel("Blur strength")
        .accessibilityValue("\(Int(amount * 100)) percent")
        .accessibilityHint("Opens the strength slider")
    }

    private var eye: some View {
        Button {
            withAnimation(motion) { on.toggle() }
        } label: {
            Image(systemName: on ? "eye.slash.fill" : "eye")
                .font(.system(size: 12, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(on ? Color.black.opacity(0.85) : .white)
                .frame(width: 30, height: 30)
                .background {
                    if on {
                        Circle().fill(.white)
                    } else {
                        Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                            .overlay(Circle().strokeBorder(.white.opacity(0.14), lineWidth: 0.75))
                    }
                }
        }
        .buttonStyle(PressStyle())
        .help(on ? "Show camera pictures" : "Blur every camera, for sharing your screen")
        .accessibilityLabel("Privacy blur")
        .accessibilityValue(on ? "On" : "Off")
    }

    // MARK: Folding

    /// Slides the slider out, and folds it again after a quiet moment.
    private func show(for seconds: Double) {
        withAnimation(motion) { expanded = true }
        foldLater(after: seconds)
    }

    private func foldLater(after seconds: Double = 1.2) {
        fold?.cancel()
        fold = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            withAnimation(motion) { expanded = false }
        }
    }
}
