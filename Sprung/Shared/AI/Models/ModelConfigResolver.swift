import Foundation

/// Resolves a user-configured model id from UserDefaults, throwing
/// `ModelConfigurationError` (never substituting a default) so the UI layer can
/// surface the model picker. Single source of truth for the "configured-or-throw" guard.
enum ModelConfigResolver {
    static func resolve(key: String, operation: String) throws -> String {
        guard let modelId = UserDefaults.standard.string(forKey: key), !modelId.isEmpty else {
            throw ModelConfigurationError.modelNotConfigured(settingKey: key, operationName: operation)
        }
        return modelId
    }
}
