import Foundation
import Security

struct KeychainFailure: LocalizedError {
    let operation: String
    let status: OSStatus
    var errorDescription: String? { "Couldn’t \(operation) the secure sign-in (Keychain status \(status)). Existing saved data has not been reset." }
}

/// Separated mutation algorithm permits deterministic failure tests without
/// reading, writing or deleting the user's Keychain.
enum KeychainMutation {
    static func write(_ value: String?, update: (Data) -> OSStatus,
                      add: (Data) -> OSStatus, delete: () -> OSStatus) throws {
        guard let value, !value.isEmpty else {
            let status = delete()
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainFailure(operation: "remove", status: status) }
            return
        }
        let data = Data(value.utf8)
        let status = update(data)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainFailure(operation: "save", status: status) }
        let added = add(data)
        if added == errSecSuccess { return }
        // Another writer may have inserted the item after our missing-item read.
        if added == errSecDuplicateItem {
            let retried = update(data)
            if retried == errSecSuccess { return }
            throw KeychainFailure(operation: "save", status: retried)
        }
        throw KeychainFailure(operation: "save", status: added)
    }
}

/// Logins and tokens live in the login keychain, never in a public source file.
enum Keychain {
    private static let service = "com.elvisobi.hearth"
    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func read(_ account: String) throws -> String? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainFailure(operation: "read", status: status) }
        guard let data = result as? Data, let text = String(data: data, encoding: .utf8) else {
            throw KeychainFailure(operation: "read", status: errSecDecode)
        }
        return text
    }

    static func get(_ account: String) -> String? { try? read(account) }

    static func write(_ value: String?, for account: String) throws {
        let base = query(account)
        try KeychainMutation.write(value, update: { data in
            SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }, add: { data in
            var request = base
            request[kSecValueData as String] = data
            return SecItemAdd(request as CFDictionary, nil)
        }, delete: { SecItemDelete(base as CFDictionary) })
    }

    /// Existing optional-code callers retain their API; failures never delete an
    /// old value. Authentication uses the throwing API and presents its error.
    @discardableResult
    static func set(_ value: String?, for account: String) -> Bool {
        do { try write(value, for: account); return true } catch { return false }
    }
}
