import Foundation

/// Failed optimistic controls read back only their explicit entity. Never infer a
/// device/area target or replay a failed command. HomeStore.refreshEntity retains
/// newer state_changed pushes while that read is in flight.
enum CommandReconciliation {
    static func target(for action: DeviceCommand) -> String? {
        guard let id = action.entityID, !id.isEmpty, id.contains("."),
              !id.contains(","), !id.contains(where: \.isWhitespace), id != "all" else { return nil }
        return id
    }

    @MainActor
    static func perform(_ action: DeviceCommand,
                        send: (DeviceCommand) async throws -> Void,
                        refresh: (String) async -> Entity?) async throws {
        do { try await send(action) }
        catch {
            if let id = target(for: action) { _ = await refresh(id) }
            throw error
        }
    }
}
