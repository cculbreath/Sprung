//
//  ModelConfigurationError.swift
//  Sprung
//
//  Error thrown when required LLM model configuration is missing.
//  Callers should catch this and surface the settings UI.
//

import Foundation

/// Error thrown when a required LLM model is not configured.
/// UI layers should catch this and present the model settings view.
enum ModelConfigurationError: LocalizedError {
    /// No model ID configured for the specified setting
    case modelNotConfigured(settingKey: String, operationName: String)

    /// The configured model is not available (e.g., not in enabled models list)
    case modelUnavailable(modelId: String, settingKey: String, operationName: String)

    var errorDescription: String? {
        switch self {
        case let .modelNotConfigured(_, operationName):
            return "\(operationName) requires a model to be configured"
        case let .modelUnavailable(modelId, _, operationName):
            return "Model '\(modelId)' is not available for \(operationName)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .modelNotConfigured:
            return "Open Settings > Models to select a model for this operation."
        case .modelUnavailable:
            return "Open Settings > Models to select an available model."
        }
    }

    /// The UserDefaults key that needs to be configured
    var settingKey: String {
        switch self {
        case let .modelNotConfigured(key, _):
            return key
        case let .modelUnavailable(_, key, _):
            return key
        }
    }

    /// Human-readable name of the operation that requires the model
    var operationName: String {
        switch self {
        case let .modelNotConfigured(_, name):
            return name
        case let .modelUnavailable(_, _, name):
            return name
        }
    }
}
