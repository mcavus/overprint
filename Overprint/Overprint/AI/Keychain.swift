import Foundation
import Security

/// Minimal generic-password Keychain access for AI credentials (the Claude Code
/// subscription token). Secrets are never written to a file; they live here.
enum Keychain {
    static let service = "com.mcavus.Overprint"

    /// What macOS quotes back in "Overprint wants to access key ... in your keychain", and what
    /// Keychain Access lists the item under. Without it the prompt names the service, so the user
    /// is asked to approve `com.mcavus.Overprint`, which tells them nothing about what is being
    /// read. The dialog has no room for an app-supplied explanation, so this label is the only
    /// part of it Overprint controls.
    static let label = "Overprint: Claude Code token"

    /// Shown as "Kind" in Keychain Access.
    static let kind = "Claude Code subscription token"

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func set(_ value: String, account: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // The label goes on the update too, not just the add, so an item saved by an earlier
        // version gets named the next time the token is saved rather than staying opaque forever.
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrLabel as String: label,
            kSecAttrDescription as String: kind,
        ]
        let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if update == errSecItemNotFound {
            var add = query
            add.merge(attributes) { current, _ in current }
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
        return update == errSecSuccess
    }

    @discardableResult
    static func delete(_ account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
