import Foundation

/// Captured at user-command submission, independently of transport reconnects.
/// Every deferred boundary rechecks authority before it can use a live socket.
struct CommandSession {
    let generation: Int

    func check(current: Int) throws {
        guard generation == current else { throw HASessionError.staleSession }
    }

    @MainActor
    func waitForConnection(current: () -> Int, connected: () -> Bool,
                           pause: () async throws -> Void) async throws {
        try Task.checkCancellation()
        try check(current: current())
        for _ in 0..<100 {
            if connected() {
                try check(current: current())
                return
            }
            try await pause()
            try Task.checkCancellation()
            try check(current: current())
        }
    }
}
