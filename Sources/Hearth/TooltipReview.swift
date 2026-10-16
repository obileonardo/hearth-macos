#if DEBUG
import AppKit
import SwiftUI

/// Offline controls and illustrations only. No registry, saved session or cameras.
@MainActor
enum TooltipReview {
    static func open() -> NSWindow {
        let content = ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Security").font(.system(size: 26, weight: .bold))
                Text("Offline demo · Hover or click each information button")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted)
                ForEach([["Backyard", "Entrance"], ["Kitchen", "Office"], ["Lab", "Living Room"]], id: \.self) { row in
                    HStack(spacing: 10) {
                        ForEach(row, id: \.self) { title in
                            VStack(alignment: .leading, spacing: 8) {
                                DeviceArtView(kind: .outdoorCamera, accent: Theme.brand, size: 70)
                                    .frame(maxWidth: .infinity, minHeight: 92)
                                Text(title).font(.system(size: 14, weight: .semibold))
                                Text("Simulated camera").font(.system(size: 12)).foregroundStyle(Theme.muted)
                            }
                            .padding(12).frame(maxWidth: .infinity, minHeight: 150)
                            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.raised))
                            .overlay(alignment: .topTrailing) {
                                PanelInfoButton(message: GridCamera.unreachableNote).padding(10)
                            }
                        }
                    }
                }
            }.padding(22).padding(.bottom, 100)
        }
        .scrollIndicators(.never)
        .frame(width: Theme.panelSize.width, height: Theme.panelSize.height)
        .panelTooltipHost()
        .foregroundStyle(Theme.ink).background(Theme.base)
        .preferredColorScheme(.dark)
        let window = NSWindow(contentRect: NSRect(x: 200, y: 120, width: Theme.panelSize.width, height: Theme.panelSize.height),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Hearth · Offline Camera Tooltip Review"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return window
    }
}
#endif
