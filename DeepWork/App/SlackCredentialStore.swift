import Foundation
import LocalAuthentication
import Security

protocol SlackCredentialStoring: Sendable {
    func load() async throws -> Data?
    func save(_ data: Data) async throws
    func delete() async throws
}

/// One Keychain item makes the rotated access/refresh pair an atomic update.
/// Tokens are local to this device, never synchronized or saved in SQLite.
actor KeychainSlackCredentialStore: SlackCredentialStoring {
    private let service: String
    private let account = "slack-user-authorization-v1"

    init(service: String = "app.deepwork.mac.slack") { self.service = service }

    func load() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw SlackClientError.keychainFailure }
        return data
    }

    func save(_ data: Data) throws {
        let update = [kSecValueData as String: data] as CFDictionary
        let query = baseQuery
        let status = SecItemUpdate(query as CFDictionary, update)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw SlackClientError.keychainFailure }
        var insertion = baseQuery
        insertion[kSecValueData as String] = data
        insertion[kSecAttrLabel as String] = "Deep Work Slack authorization"
        insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess else { throw SlackClientError.keychainFailure }
    }

    func delete() throws {
        let query = baseQuery
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SlackClientError.keychainFailure }
    }

    private var baseQuery: [String: Any] {
        let context = LAContext()
        context.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false,
         kSecUseAuthenticationContext as String: context]
    }
}
