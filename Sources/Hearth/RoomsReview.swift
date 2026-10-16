#if DEBUG
import AppKit
import SwiftUI

/// Interactive, synthetic-only native QA. Returns before normal app startup:
/// no saved session, notifications, activity database or physical device requests.
@MainActor
enum RoomsReview {
    static func open() -> NSWindow {
        let store = HomeStore()
        let rooms = [Area(id: "bedroom", name: "Bedroom", floorID: "first"),
                     Area(id: "kitchen", name: "Kitchen", floorID: "ground"),
                     Area(id: "lab", name: "Lab", floorID: "first"),
                     Area(id: "living", name: "Living Room", floorID: "ground"),
                     Area(id: "master", name: "Master Bedroom", floorID: "second"),
                     Area(id: "office", name: "Office", floorID: "first"),
                     Area(id: "outdoor", name: "Outdoor", floorID: "ground")]
        let devices = rooms.enumerated().map { i, area in
            DeviceInfo(id: "preview-speaker-\(i)", name: "\(area.name) speaker",
                       manufacturer: "Amazon", model: "Echo Dot", areaID: area.id)
        }
        let players = devices.enumerated().map { i, device in
            Entity(id: "media_player.preview_\(i)", state: "paused", attributes: ["friendly_name": device.name])
        }
        store.playDemo(devices: devices, entities: players,
                       deviceOf: Dictionary(uniqueKeysWithValues: zip(players.map(\.id), devices.map(\.id))),
                       areas: rooms, floors: [Floor(id: "ground", name: "Ground floor", level: 0),
                                             Floor(id: "first", name: "First floor", level: 1),
                                             Floor(id: "second", name: "Second floor", level: 2)], simulator: { _ in nil })
        let defaults = UserDefaults(suiteName: "com.elvisobi.hearth.offline-rooms-review")!
        defaults.set(RoomsLayoutPreference.interactive.rawValue, forKey: RoomsLayoutPreference.key)
        let content = ScrollView {
            RoomsOverview(shown: true, explorer: RoomsExplorerState(), open: { _ in }, openDevice: { _ in })
                .padding(.horizontal, PanelView.scrollContentInset).padding(.vertical, 22)
                .padding(.bottom, 64)
        }
        .scrollIndicators(.never)
        .defaultAppStorage(defaults)
        .frame(width: Theme.panelSize.width, height: Theme.panelSize.height)
        .foregroundStyle(Theme.ink).background(Theme.base)
        .environmentObject(store)
        .environmentObject(ActivityLog(previewItems: []))
        .preferredColorScheme(.dark)
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: Theme.panelSize.width, height: Theme.panelSize.height),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Hearth · Offline Rooms Review · Drag revision"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return window
    }
}
#endif
