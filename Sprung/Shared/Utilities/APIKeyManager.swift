//
//  APIKeyManager.swift
//  Sprung
//
//  Keychain-backed storage for API keys.
//
import Foundation
import Security
enum APIKeyType: String {
    case openRouter = "openRouterApiKey"
    case openAI = "openAiApiKey"
    case scrapingDog = "scrapingDogApiKey"
}
struct APIKeyManager {
    private static let service = Bundle.main.bundleIdentifier ?? "physicscloud.Sprung"
    static func get(_ type: APIKeyType) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: type.rawValue,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, let str = String(data: data, encoding: .utf8), !str.isEmpty {
            return str
        }
        return nil
    }
    @discardableResult
    static func set(_ type: APIKeyType, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: type.rawValue
        ]
        // Update if exists
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data
        ]
        var status = SecItemUpdate(query as CFDictionary, updateAttrs as CFDictionary)
        if status == errSecItemNotFound {
            // Add new
            var addQuery = query
            addQuery[kSecValueData as String] = data
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
        return status == errSecSuccess
    }
    static func delete(_ type: APIKeyType) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: type.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }
}
