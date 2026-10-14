import Combine
import Foundation
import WidgetKit

/// WidgetKit is opt-in at bundle build time: an unconfigured desktop-only build
/// never resolves or writes an app-group container.
@MainActor
final class WidgetSnapshotPublisher {
    static let shared = WidgetSnapshotPublisher()
    private var subscriptions = Set<AnyCancellable>()
    private weak var store: HomeStore?
    private weak var log: ActivityLog?
    private var storage: HearthWidgetStore?
    private var pending: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var lastReload = Date.distantPast

    func attach(store: HomeStore, log: ActivityLog) {
        guard storage == nil, let storage = HearthWidgetStore.shared() else { return }
        self.storage = storage
        self.store = store
        self.log = log
        store.objectWillChange.merge(with: log.objectWillChange)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.schedule() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.schedule() }.store(in: &subscriptions)
        publish()
        heartbeat = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { break }
                self?.publish()
            }
        }
    }
    private func schedule() {
        pending?.cancel()
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.publish()
        }
    }
    private func publish() {
        guard let store, let log, let storage else { return }
        let climates = store.entities.values.filter {
            $0.domain == "climate" && !DeviceKind.vehicles.contains(store.homeDevice(store.registry[$0.id]?.deviceID ?? "")?.kind ?? .generic)
        }.sorted { $0.id < $1.id }
        let selected = UserDefaults.standard.string(forKey: "desktopWidgets.climateEntity") ?? ""
        let climate = climates.first { $0.id == selected }
            ?? climates.first { !$0.isUnavailable && Climate(e: $0).on }
            ?? climates.first { !$0.isUnavailable } ?? climates.first
        let reading = climate.map { entity in
            let c = Climate(e: entity)
            return HearthWidgetSnapshot.ClimateReading(entityID: entity.id, name: Climate.shortName(entity.name),
                mode: c.mode, target: c.target, room: c.room, available: !entity.isUnavailable)
        }
        let event = log.items.first { [.person, .doorbell].contains($0.kind) }
        let energy = EnergySystem.read(store, prefs: nil)
        let homes = HomeList.shared
        let homeWatts = HomeEnergy(home: homes.main, store: store, list: homes, gadgets: GadgetStore.shared.gadgets).nowWatts
        let player = store.entities.values.filter { $0.domain == "media_player" && $0.state == "playing" }.sorted { $0.id < $1.id }.first
        let connection: String = switch store.status {
        case .connected: store.isDemo ? "Sample" : "Connected"
        case .connecting: "Connecting"
        case .needsSetup: "Connect Hearth"
        case .rejected: "Sign-in needed"
        case .failed: "Offline"
        }
        let snapshot = HearthWidgetSnapshot(updatedAt: .now, connection: connection, climate: reading,
            activity: event.map { .init(title: $0.title, symbol: $0.kind.symbol, date: $0.date) },
            energy: .init(batteryPercent: energy.chargePercent, solarWatts: energy.solarWatts, homeWatts: homeWatts),
            playing: player.map { .init(title: $0.str("media_title") ?? $0.name, artist: $0.str("media_artist")) },
            deviceCount: store.devices.count, roomCount: store.areas.count)
        do {
            try storage.write(snapshot)
            // WidgetKit owns its refresh budget; avoid reloading every sensor event.
            if Date.now.timeIntervalSince(lastReload) >= 60 {
                WidgetCenter.shared.reloadAllTimelines()
                lastReload = .now
            }
        } catch {
            NSLog("Hearth: widget snapshot could not be saved")
        }
    }
}
