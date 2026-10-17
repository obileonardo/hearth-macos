import Foundation

/// An accepted command is not a confirmed mode. Read immediately when the push
/// has not arrived, then retain the bounded event wait and final reconciliation.
/// All state comes from Home Assistant; this helper never changes entity values.
@MainActor
enum ClimateModeConfirmation {
    static func wait(for requested: String,
                     currentMode: () -> String?,
                     refresh: () async -> Void,
                     isCurrent: () -> Bool,
                     pause: () async throws -> Void = { try await Task.sleep(for: .milliseconds(250)) }) async throws -> Bool {
        func checkSession() throws {
            try Task.checkCancellation()
            guard isCurrent() else { throw CancellationError() }
        }

        try checkSession()
        if currentMode() == requested { return true }
        // Some integrations acknowledge promptly but deliver state_changed late.
        // A fresh snapshot can confirm the result without the former five-second delay.
        await refresh()
        try checkSession()
        if currentMode() == requested { return true }

        for _ in 0..<20 {
            try await pause()
            try checkSession()
            if currentMode() == requested { return true }
        }
        await refresh()
        try checkSession()
        return currentMode() == requested
    }
}
