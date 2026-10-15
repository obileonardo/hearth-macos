import AppKit
import SwiftUI

/// `--render-art <dir>` writes every illustration, the app icon and the menu bar glyph
/// to PNGs, so the art can be reviewed and shipped without opening the app.
@MainActor
enum ArtExporter {
    static func export(to dir: String) {
        // Documentation artwork has a deterministic dark backdrop; this command
        // exits before sign-in and never changes the saved appearance choice.
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let root = URL(fileURLWithPath: dir, isDirectory: true)
        let devices = root.appendingPathComponent("devices", isDirectory: true)
        try? FileManager.default.createDirectory(at: devices, withIntermediateDirectories: true)

        for kind in DeviceKind.allCases {
            for active in [true, false] {
                let view = DeviceArtView(kind: kind, active: active, size: 160)
                    .padding(16)
                    .background(Theme.base)
                write(view, to: devices.appendingPathComponent("\(kind.rawValue)\(active ? "" : "-off").png"))
            }
        }
        write(VStack(alignment: .leading, spacing: 24) {
            ForEach([true, false], id: \.self) { active in
                HStack(alignment: .bottom, spacing: 24) {
                    ForEach([24, 46, 72, 160], id: \.self) { size in
                        DeviceArtView(kind: .solarPanel, active: active, accent: EnergyPalette.accent(.solarPanel), size: CGFloat(size))
                    }
                }
            }
        }.padding(24).background(Theme.base), to: root.appendingPathComponent("solar-scale.png"))
        write(ContactSheet(), to: root.appendingPathComponent("devices.png"))
        write(AppIconArt(), to: root.appendingPathComponent("AppIcon-1024.png"), scale: 1)
        write(MenuBarGlyph(size: 18), to: root.appendingPathComponent("menubar-18.png"), scale: 1)
        write(MenuBarGlyph(size: 18), to: root.appendingPathComponent("menubar-36.png"), scale: 2)
        write(MenuBarPreview(), to: root.appendingPathComponent("menubar-preview.png"), scale: 4)
        print("Art written to \(root.path)")
    }

    private static func write(_ view: some View, to url: URL, scale: CGFloat = 2) {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = scale
        guard let cg = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
            print("Could not render \(url.lastPathComponent)")
            return
        }
        try? png.write(to: url)
    }
}

/// Every kind, on and off at full size, then at list sizes, on the panel's black.
private struct ContactSheet: View {
    private let rows = (DeviceKind.allCases.count + 2) / 3

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Grid(horizontalSpacing: 18, verticalSpacing: 22) {
                ForEach(0..<rows, id: \.self) { row in
                    GridRow {
                        ForEach(0..<3, id: \.self) { column in
                            let index = row * 3 + column
                            if index < DeviceKind.allCases.count {
                                let kind = DeviceKind.allCases[index]
                                VStack(spacing: 8) {
                                    HStack(spacing: 6) {
                                        DeviceArtView(kind: kind, active: true, size: 160)
                                        DeviceArtView(kind: kind, active: false, size: 160)
                                    }
                                    Text(kind.title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted)
                                }
                            }
                        }
                    }
                }
            }
            HStack(spacing: 14) {
                ForEach(DeviceKind.allCases, id: \.self) { kind in
                    DeviceArtView(kind: kind, size: 64)
                }
            }
            HStack(spacing: 14) {
                ForEach(DeviceKind.allCases, id: \.self) { kind in
                    DeviceBadge(kind: kind).frame(width: 64)
                }
            }
            // The hubs at the sizes the Security page and device pages use.
            HStack(alignment: .bottom, spacing: 24) {
                ForEach([DeviceKind.securityHub, .securityHubPro], id: \.self) { kind in
                    DeviceArtView(kind: kind, size: 52)
                    DeviceArtView(kind: kind, size: 84)
                    DeviceArtView(kind: kind, active: false, size: 84)
                }
            }
            // The gadgets at the sizes the Gadgets page uses, in their own light.
            HStack(alignment: .bottom, spacing: 24) {
                ForEach([DeviceKind.printer3D, .gameConsole, .computer], id: \.self) { kind in
                    DeviceArtView(kind: kind, accent: HomeDevice.gadgetAccent(kind), size: 44)
                    DeviceArtView(kind: kind, accent: HomeDevice.gadgetAccent(kind), size: 60)
                    DeviceBadge(kind: kind, accent: HomeDevice.gadgetAccent(kind), size: 38)
                }
            }
            // The energy kit at the sizes the Energy page uses, in its own light.
            HStack(alignment: .bottom, spacing: 24) {
                ForEach([DeviceKind.inverter, .battery, .solarPanel], id: \.self) { kind in
                    DeviceArtView(kind: kind, accent: EnergyPalette.accent(kind), size: 46)
                    DeviceArtView(kind: kind, accent: EnergyPalette.accent(kind), size: 54)
                    DeviceBadge(kind: kind, accent: EnergyPalette.accent(kind), size: 38)
                }
            }
        }
        .padding(28)
        .background(Theme.base)
    }
}

/// The glyph as it sits in a light and a dark menu bar.
private struct MenuBarPreview: View {
    var body: some View {
        VStack(spacing: 0) {
            bar(.light)
            bar(.dark)
        }
    }

    private func bar(_ scheme: ColorScheme) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "wifi")
            MenuBarGlyph()
            Image(systemName: "battery.75percent")
            Text("Tue 10:24").font(.system(size: 13))
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.93))
        .environment(\.colorScheme, scheme)
        .foregroundStyle(.primary)
    }
}
