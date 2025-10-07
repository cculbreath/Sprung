//
//  APIKeyManager.swift
//  PhysCloudResume
//
//  Keychain-backed storage for API keys with optional UserDefaults migration.
//

import Foundation
import Security

enum APIKeyType: String {
    case openRouter = "openRouterApiKey"
    case openAI = "openAiApiKey"
}

struct APIKeyManager {
    private static let service = Bundle.main.bundleIdentifier ?? "Physics-Cloud.PhysCloudResume"

    static func get(_ type: APIKeyType) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: type.rawValue,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne,
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
            kSecAttrAccount as String: type.rawValue,
        ]

        // Update if exists
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
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
            kSecAttrAccount as String: type.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// One-time migration of keys from UserDefaults to Keychain.
    static func migrateFromUserDefaults() {
        let defaults = UserDefaults.standard

        // OpenRouter
        if get(.openRouter) == nil, let val = defaults.string(forKey: APIKeyType.openRouter.rawValue), !val.isEmpty {
            if set(.openRouter, value: val) {
                Logger.debug("🔑 Migrated OpenRouter API key to Keychain")
            }
        }

        // OpenAI (optional, used by TTS)
        if get(.openAI) == nil, let val = defaults.string(forKey: APIKeyType.openAI.rawValue), !val.isEmpty, val != "none" {
            if set(.openAI, value: val) {
                Logger.debug("🔑 Migrated OpenAI API key to Keychain")
            }
        }
    }
}

