//
//  EnabledLLM.swift
//  Sprung
//
//  Track enabled models and their verified capabilities
//
import Foundation
import SwiftData
@Model
class EnabledLLM {
    @Attribute(.unique) var modelId: String = ""
    var displayName: String = ""
    var isEnabled: Bool = true
    var dateAdded: Date = Date()
    var lastUsed: Date = Date()
    // Verified capabilities based on actual API responses
    var supportsStructuredOutput: Bool = false
    var supportsJSONSchema: Bool = false  // More specific than structured output
    var supportsImages: Bool = false
    var supportsReasoning: Bool = false  // Supports reasoning tokens (o1, Claude 3.7, DeepSeek R1, etc.)
    var isTextToText: Bool = true
    // Failure tracking
    var jsonSchemaFailureCount: Int = 0
    var lastJSONSchemaFailure: Date?
    var consecutiveFailures: Int = 0
    var lastFailureReason: String?
    // Provider info
    var provider: String = ""
    var contextLength: Int = 0
    var pricingTier: String = ""
    init(modelId: String, displayName: String, provider: String = "") {
        self.modelId = modelId
        self.displayName = displayName
        self.provider = provider
    }
    /// Mark that JSON schema failed for this model
    func recordJSONSchemaFailure(reason: String) {
        jsonSchemaFailureCount += 1
        lastJSONSchemaFailure = Date()
        consecutiveFailures += 1
        lastFailureReason = reason
        Logger.debug("⚠️ JSON schema failure #\(consecutiveFailures) for \(modelId): \(reason)")
    }
    /// Mark successful JSON schema usage - clears failure tracking
    func recordJSONSchemaSuccess() {
        consecutiveFailures = 0
        lastFailureReason = nil
        lastUsed = Date()
    }
    /// Check if we should temporarily avoid JSON schema for this model
    /// Blocked for 1 hour after 2+ consecutive failures, then falls back to OpenRouter-reported support
    var shouldAvoidJSONSchema: Bool {
        if let lastFailure = lastJSONSchemaFailure,
           Date().timeIntervalSince(lastFailure) < 3600,
           consecutiveFailures >= 2 {
            return true
        }
        return false  // Default to OpenRouter-reported capability
    }
}
