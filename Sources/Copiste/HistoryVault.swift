import CryptoKit
import Foundation
import Security

/// Chiffrement de l'historique conservé sur disque (option, désactivée par défaut).
/// AES-256-GCM ; la clé est créée au premier usage et gardée dans le Trousseau de session
/// (jamais dans un fichier). Sans la clé, le fichier `history.enc` est illisible.
enum HistoryVault {
    static var service = "fr.louisclauzier.copiste"
    private static let account = "history-key"

    /// Clé existante, ou nouvelle clé enregistrée dans le Trousseau si `create`.
    private static func key(create: Bool) -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var found: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess, let data = found as? Data {
            return SymmetricKey(data: data)
        }
        guard create else { return nil }
        let fresh = SymmetricKey(size: .bits256)
        let data = fresh.withUnsafeBytes { Data($0) }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess ? fresh : nil
    }

    static func seal(_ plain: Data) -> Data? {
        guard let key = key(create: true), let box = try? AES.GCM.seal(plain, using: key) else { return nil }
        return box.combined
    }

    static func open(_ sealed: Data) -> Data? {
        guard let key = key(create: false), let box = try? AES.GCM.SealedBox(combined: sealed) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }

    /// Supprime la clé : tout fichier chiffré restant devient définitivement illisible.
    static func deleteKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
