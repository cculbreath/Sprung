//
//  ModelCapabilityValidator.swift
//  Sprung
//
//  Validates model capabilities for onboarding settings.
//  Extracted from OnboardingModelSettingsView for single responsibility.
//
//  This gates **UI options for an already-user-selected model** (which
//  reasoning-effort / flex-processing / prompt-cache-retention controls to
//  show). It never substitutes or falls back to a model, so it is not a
//  "model selection" concern under agents.md's no-hardcoded-model-IDs rule
//  — that rule targets picking a model, not gating options for one the user
//  already picked. See plans/deferred-actions.md D-01.
//
//  NO SPECULATION: capabilityTable only lists models we have verified
//  behavior for. An unrecognized model ID (including any future model,
//  e.g. an eventual gpt-6/gpt-7 family) simply misses every lookup below
//  and falls through to each function's conservative default — we do not
//  guess forward compatibility.
//

import Foundation

/// Validates model capabilities for onboarding settings
struct ModelCapabilityValidator {

    /// Per-model capability flags. Single source of truth for the two
    /// previously-separate cache-retention / flex-processing capability
    /// Sets (consolidated 2026-07-06, D-01). Lookup is an **exact,
    /// case-sensitive** match on the model ID, matching the original Sets'
    /// `Set<String>.contains` behavior.
    struct Capabilities {
        /// Supports `prompt_cache_retention: "24h"` (Responses API).
        let promptCacheRetention: Bool
        /// Supports `service_tier: "flex"` (Responses API; ~50% cost savings, variable latency).
        let flexProcessing: Bool
    }

    static let capabilityTable: [String: Capabilities] = [
        // GPT-5.5 family: Responses-API-only. Cache retention is "24h" only
        // ("in_memory" unsupported); flex processing confirmed. (2026-06-15)
        "gpt-5.5": Capabilities(promptCacheRetention: true, flexProcessing: true),
        "gpt-5.5-pro": Capabilities(promptCacheRetention: true, flexProcessing: true),

        // GPT-5.4 family: same cache/flex behavior as 5.5. (2026-06-15)
        "gpt-5.4": Capabilities(promptCacheRetention: true, flexProcessing: true),
        "gpt-5.4-mini": Capabilities(promptCacheRetention: true, flexProcessing: true),
        "gpt-5.4-nano": Capabilities(promptCacheRetention: true, flexProcessing: true),
        "gpt-5.4-pro": Capabilities(promptCacheRetention: true, flexProcessing: true),

        // GPT-5.2: cache retention + flex processing confirmed. (2026-06-15)
        "gpt-5.2": Capabilities(promptCacheRetention: true, flexProcessing: true),

        // GPT-5.1 family: cache retention confirmed for all variants; flex
        // processing confirmed only for the base gpt-5.1 (codex / codex-mini /
        // chat-latest variants are not flex-eligible). (2026-06-15)
        "gpt-5.1-codex-max": Capabilities(promptCacheRetention: true, flexProcessing: false),
        "gpt-5.1": Capabilities(promptCacheRetention: true, flexProcessing: true),
        "gpt-5.1-codex": Capabilities(promptCacheRetention: true, flexProcessing: false),
        "gpt-5.1-codex-mini": Capabilities(promptCacheRetention: true, flexProcessing: false),
        "gpt-5.1-chat-latest": Capabilities(promptCacheRetention: true, flexProcessing: false),

        // GPT-5 base family: cache retention confirmed for base + codex;
        // flex processing confirmed for base + mini/nano (codex variant is
        // not flex-eligible). (2026-06-15)
        "gpt-5": Capabilities(promptCacheRetention: true, flexProcessing: true),
        "gpt-5-codex": Capabilities(promptCacheRetention: true, flexProcessing: false),
        "gpt-5-mini": Capabilities(promptCacheRetention: false, flexProcessing: true),
        "gpt-5-nano": Capabilities(promptCacheRetention: false, flexProcessing: true),

        // GPT-4.1: cache retention confirmed; not part of the flex tier. (2026-06-15)
        "gpt-4.1": Capabilities(promptCacheRetention: true, flexProcessing: false),

        // o-series reasoning models: flex processing confirmed; o-series cache
        // semantics differ, so these are not part of the cache-retention set. (2026-06-15)
        "o3": Capabilities(promptCacheRetention: false, flexProcessing: true),
        "o4-mini": Capabilities(promptCacheRetention: false, flexProcessing: true),
    ]

    /// Reasoning options. `xhigh` is supported for all models after gpt-5.1-codex-max
    /// (gpt-5.2, gpt-5.4, gpt-5.5, and their pro/mini/nano variants).
    static let reasoningOptions: [(value: String, label: String, detail: String)] = [
        ("none", "None", "GPT-5.1+ only; fastest responses, no reasoning tokens"),
        ("minimal", "Minimal", "GPT-5 base only; lightweight reasoning"),
        ("low", "Low", "Light reasoning for moderately complex tasks"),
        ("medium", "Medium", "Balanced speed and reasoning depth"),
        ("high", "High", "Maximum reasoning; best for complex tasks"),
        ("xhigh", "Extra High", "GPT-5.2+ only; deepest reasoning for the hardest async tasks")
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

    /// Check if model supports "none" reasoning effort.
    /// Conservative default: `false` for anything that isn't a recognized
    /// gpt-5.x point release — including any unrecognized future model.
    static func supportsNoneReasoning(_ modelId: String) -> Bool {
        let id = modelId.lowercased()
        return id.hasPrefix("gpt-5.")
    }

    /// Check if model supports "xhigh" reasoning effort.
    /// Per OpenAI docs, xhigh is supported for all models after gpt-5.1-codex-max.
    /// Conservative default: `false` for anything that isn't a recognized
    /// gpt-5.2/5.4/5.5 family member — including any unrecognized future model.
    static func supportsXHighReasoning(_ modelId: String) -> Bool {
        let id = modelId.lowercased()
        if id.hasPrefix("gpt-5.2") { return true }
        if id.hasPrefix("gpt-5.4") { return true }
        if id.hasPrefix("gpt-5.5") { return true }
        return false
    }

    /// Get available reasoning options based on model
    static func availableReasoningOptions(for modelId: String) -> [(value: String, label: String, detail: String)] {
        var options = reasoningOptions
        if isGPT5BaseModel(modelId) {
            options.removeAll { $0.value == "none" }
        } else {
            options.removeAll { $0.value == "minimal" }
        }
        if !supportsXHighReasoning(modelId) {
            options.removeAll { $0.value == "xhigh" }
        }
        return options
    }

    /// Check if model supports flex processing
    static func isFlexProcessingCompatible(_ modelId: String) -> Bool {
        capabilityTable[modelId]?.flexProcessing ?? false
    }

    /// Check if model supports extended prompt cache retention
    static func isPromptCacheRetentionCompatible(_ modelId: String) -> Bool {
        capabilityTable[modelId]?.promptCacheRetention ?? false
    }

    /// Sanitize reasoning effort when model changes
    static func sanitizeReasoningEffort(_ effort: String, for modelId: String) -> String {
        if effort == "xhigh" && !supportsXHighReasoning(modelId) {
            return "high"
        }
        if isGPT5BaseModel(modelId) && effort == "none" {
            return "minimal"
        } else if supportsNoneReasoning(modelId) && effort == "minimal" {
            return "none"
        }
        return effort
    }
}
