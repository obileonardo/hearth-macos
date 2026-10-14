#if HEARTH_WIDGET_PREVIEW
import AppKit
import SwiftUI
import WidgetKit

@main
struct WidgetPreviewExporter {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let path = CommandLine.arguments.dropFirst().first ?? "/private/tmp/hearth-widget-gallery-previews"
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for kind in HearthGalleryKind.allCases {
            for family in kind.families {
                let size: CGSize = switch family {
                case .systemSmall: CGSize(width: 170, height: 170)
                case .systemMedium: CGSize(width: 360, height: 170)
                case .systemLarge: CGSize(width: 360, height: 376)
                default: CGSize(width: 746, height: 376)
                }
                for scheme in [ColorScheme.light, .dark] {
                    for empty in [false, true] {
                        let snapshot = empty ? HearthWidgetSnapshot.empty(at: now.addingTimeInterval(-600)) : .sample(at: now)
                        let entry = HearthGalleryEntry(date: now, snapshot: snapshot)
                        let gallery = HearthGalleryView(entry: entry, kind: kind, previewFamily: family, previewing: true)
                        let view = gallery
                            .frame(width: size.width, height: size.height)
                            .environment(\.colorScheme, scheme)
                        let renderer = ImageRenderer(content: view)
                        renderer.scale = 2
                        guard let cg = renderer.cgImage,
                              let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
                            throw NSError(domain: "HearthWidgetPreview", code: 1)
                        }
                        let name = "\(kind.rawValue)-\(family)-\(scheme)-\(empty ? "empty-stale" : "sample").png"
                        try data.write(to: folder.appendingPathComponent(name))
                    }
                }
            }
        }
        print("Rendered gallery surfaces: \(folder.path)")
    }
}
#endif
