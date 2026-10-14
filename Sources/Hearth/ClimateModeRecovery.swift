import Foundation

/// A rejected LG control can be transient. Retry this idempotent mode request
/// once, after fresh reads and a short settle, only while the original mode is
/// still reported. Never retry temperature changes, auth failures or timeouts.
@MainActor
enum ClimateModeRecovery {
    static func perform(_ action: DeviceCommand, initial: Entity,
                        send: (DeviceCommand) async throws -> Void,
                        refresh: () async -> Entity?,
                        settle: () async throws -> Void = { try await Task.sleep(for: .seconds(3)) }) async throws {
        do {
            try await send(action)
        } catch {
            let rejection = error
            guard action.domain == "climate", action.service == "set_hvac_mode",
                  action.entityID == initial.id,
                  let requested = action.data["hvac_mode"] as? String,
                  error.localizedDescription.lowercased().contains("fail device control") else { throw rejection }
            guard let fresh = await refresh(), eligible(fresh, initial: initial, requested: requested) else { throw rejection }
            if fresh.state == requested { return }
            try await settle()
            try Task.checkCancellation()
            guard let settled = await refresh(), eligible(settled, initial: initial, requested: requested) else { throw rejection }
            if settled.state == requested { return }
            // The exact original request is reused. A second rejection propagates.
            try await send(action)
        }
    }

    private static func eligible(_ current: Entity, initial: Entity, requested: String) -> Bool {
        current.id == initial.id && !current.isUnavailable && current.list("hvac_modes").contains(requested)
            && (current.state == initial.state || current.state == requested)
    }
}
