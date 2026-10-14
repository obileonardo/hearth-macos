import Foundation

/// Commands to one physical AC run serially. Other devices retain independent
/// concurrency. Cooldown starts after acknowledgement or error, not after UI input.
@MainActor
final class ClimateCommandQueue {
    private struct Tail {
        let token: UUID
        let completion: Task<Void, Never>
    }
    private var tails: [String: Tail] = [:]
    private let spacing: Duration

    init(spacing: Duration = .milliseconds(600)) { self.spacing = spacing }

    func run<Value>(key: String, operation: @escaping @MainActor () async throws -> Value) async throws -> Value {
        let predecessor = tails[key]?.completion
        let token = UUID()
        let permit = CommandStartPermit()
        let response = CommandResponse<Value>()
        // Void is Sendable; the generic response remains confined to MainActor.
        let work = Task<Void, Error> { @MainActor in
            if let predecessor { await predecessor.value }
            try Task.checkCancellation()
            guard permit.begin() else { throw CancellationError() }
            response.result = .success(try await operation())
        }
        let spacing = self.spacing
        let completion = Task<Void, Never> { @MainActor [weak self] in
            // Failure never breaks the chain. A cancelled, unsent job adds no cooldown.
            _ = await work.result
            if permit.didStart { try? await Task.sleep(for: spacing) }
            if self?.tails[key]?.token == token { self?.tails.removeValue(forKey: key) }
        }
        tails[key] = Tail(token: token, completion: completion)
        return try await withTaskCancellationHandler {
            try await work.value
            guard let result = response.result else { throw QueueError.missingResponse }
            return result.get()
        } onCancel: {
            // Once the operation reaches transport, wait for its actual outcome.
            // Cancelling a UI task must not invent a rollback of a sent command.
            if permit.cancelBeforeStart() { work.cancel() }
        }
    }

    private enum QueueError: Error { case missingResponse }
}

@MainActor
private final class CommandResponse<Value> {
    var result: Result<Value, Never>?
}

/// Cancellation handlers can run off-actor. This tiny lock protects only the
/// queued-to-started handoff; no lock is held across an await or device operation.
private final class CommandStartPermit: @unchecked Sendable {
    private let lock = NSLock()
    private var started = false
    private var cancelled = false

    func begin() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { return false }
        started = true
        return true
    }

    func cancelBeforeStart() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !started else { return false }
        cancelled = true
        return true
    }

    var didStart: Bool {
        lock.lock(); defer { lock.unlock() }
        return started
    }
}

/// Scope only an explicit single-entity climate command or a verified AC sibling.
/// Multi-target calls and unrelated domains remain unchanged; payloads are never rewritten.
enum ClimateCommandScope {
    static func key(for body: JSON, registry: [String: RegistryEntry], entities: [String: Entity]) -> String? {
        guard body["type"] as? String == "call_service",
              let domain = body["domain"] as? String,
              let target = body["target"] as? JSON,
              !target.keys.contains(where: { $0 != "entity_id" }) else { return nil }
        let id: String
        if let single = target["entity_id"] as? String { id = single }
        else if let list = target["entity_id"] as? [String], list.count == 1 { id = list[0] }
        else { return nil }
        guard !id.isEmpty, !id.contains(","), !id.contains(where: \.isWhitespace) else { return nil }
        let entityDomain = String(id.prefix { $0 != "." })
        let device = registry[id]?.deviceID.flatMap { $0.isEmpty ? nil : $0 }
        if domain == "climate", entityDomain == "climate" {
            return device.map { "device:\($0)" } ?? "entity:\(id)"
        }
        guard domain == entityDomain, ["switch", "number", "select", "fan", "button"].contains(domain),
              let device,
              entities.values.contains(where: { $0.domain == "climate" && registry[$0.id]?.deviceID == device }) else { return nil }
        return "device:\(device)"
    }
}
