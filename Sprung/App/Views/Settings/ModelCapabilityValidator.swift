//
//  ModelCapabilityValidator.swift
//  Sprung
//
//  Validates model capabilities for onboarding settings.
//  Extracted from OnboardingModelSettingsView for single responsibility.
//

import Foundation

/// Validates model capabilities for onboarding settings
struct ModelCapabilityValidator {

    /// Models that support extended prompt cache retention (24h)
    static let promptCacheRetentionCompatibleModels: Set<String> = [
        "gpt-5.2",
        "gpt-5.1-codex-max", "gpt-5.1", "gpt-5.1-codex", "gpt-5.1-codex-mini", "gpt-5.1-chat-latest",
        "gpt-5", "gpt-5-codex",
        "gpt-4.1"
    ]

    /// Models that support flex processing (50% cost savings, variable latency)
    static let flexProcessingCompatibleModels: Set<String> = [
        "gpt-5.2", "gpt-5.1", "gpt-5", "gpt-5-mini", "gpt-5-nano",
        "o3", "o4-mini"
    ]

    /// Reasoning options available for onboarding interviews
    static let reasoningOptions: [(value: String, label: String, detail: String)] = [
        ("none", "None", "GPT-5.1 only; fastest responses, no reasoning tokens"),
        ("minimal", "Minimal", "GPT-5 only; lightweight reasoning"),
        ("low", "Low", "Light reasoning for moderately complex tasks"),
        ("medium", "Medium", "Balanced speed and reasoning depth"),
        ("high", "High", "Maximum reasoning; best for complex tasks")
    ]

    /// Check if model ID is a base GPT-5 model (not GPT-5.x)
    static func isGPT5BaseModel(_ modelId: String) -> Bool {
        let id = modelId.lowercased()
        guard id.hasPrefix("gpt-5") else { return false }
        let afterPrefix = id.dropFirst(5)
        if afterPrefix.isEmpty { return true }
        if afterPrefix.first == "." { return false }
        if afterPrefix.first == "-" { return true }
        return false
    }

    /// Check if model supports "none" reasoning effort
    static func supportsNoneReasoning(_ modelId: String) -> Bool {
        let id = modelId.lowercased()
        if id.hasPrefix("gpt-6") || id.hasPrefix("gpt-7") { return true }
        if id.hasPrefix("gpt-5.") { return true }
        return false
    }

    /// Get available reasoning options based on model
    static func availableReasoningOptions(for modelId: String) -> [(value: String, label: String, detail: String)] {
        if isGPT5BaseModel(modelId) {
            return reasoningOptions.filter { $0.value != "none" }
        } else {
            return reasoningOptions.filter { $0.value != "minimal" }
        }
    }

    /// Check if model supports flex processing
    static func isFlexProcessingCompatible(_ modelId: String) -> Bool {
        flexProcessingCompatibleModels.contains(modelId)
    }

    /// Check if model supports extended prompt cache retention
    static func isPromptCacheRetentionCompatible(_ modelId: String) -> Bool {
        promptCacheRetentionCompatibleModels.contains(modelId)
    }

    /// Sanitize reasoning effort when model changes
    static func sanitizeReasoningEffort(_ effort: String, for modelId: String) -> String {
        if isGPT5BaseModel(modelId) && effort == "none" {
            return "minimal"
        } else if supportsNoneReasoning(modelId) && effort == "minimal" {
            return "none"
        }
        return effort
    }
}
