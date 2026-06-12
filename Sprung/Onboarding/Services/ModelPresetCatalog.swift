//
//  ModelPresetCatalog.swift
//  Sprung
//
//  Family-based model presets for the onboarding budget sheet.
//
//  Presets deliberately map operations to Claude FAMILIES (opus/sonnet/haiku),
//  never to concrete model IDs — the repo's no-hardcoded-model-IDs rule. At
//  presentation time each family resolves to the newest live model of that
//  family from the same API-backed lists the settings pickers use, the sheet
//  shows the resolved IDs, and nothing is written until the user confirms.
//  When a new generation ships (e.g. Opus 5) it appears in the live lists and
//  presets resolve to it with no code change; if a family stops resolving the
//  operation is flagged unresolved rather than silently substituted.
//

import Foundation
import SwiftOpenAI

// MARK: - Families

/// Claude model family tiers, cheapest first.
enum ClaudeFamily: String, CaseIterable, Identifiable {
    case haiku
    case sonnet
    case opus

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

// MARK: - Operations

/// Every onboarding-phase model preference a preset sets in batch.
enum OnboardingModelOperation: String, CaseIterable, Identifiable {
    // Billed to the Anthropic API key
    case interview
    case docAnalysis
    case cardMerge
    case gitIngest
    // Billed to the OpenRouter account
    case inferenceGuidance
    case skillsProcessing
    case skillCuration
    case voiceProfile
    case kcAgent
    case backgroundProcessing

    var id: String { rawValue }

    /// The existing UserDefaults key each settings picker persists to.
    /// Presets are a batch-writer over these — single source of truth unchanged.
    var defaultsKey: String {
        switch self {
        case .interview: return "onboardingAnthropicModelId"
        case .docAnalysis: return "onboardingDocAnalysisModelId"
        case .cardMerge: return "onboardingCardMergeModelId"
        case .gitIngest: return "onboardingGitIngestModelId"
        case .inferenceGuidance: return "guidanceExtractionModelId"
        case .skillsProcessing: return "skillsProcessingModelId"
        case .skillCuration: return "skillCurationModelId"
        case .voiceProfile: return "voiceProfileModelId"
        case .kcAgent: return "onboardingKCAgentModelId"
        case .backgroundProcessing: return "backgroundProcessingModelId"
        }
    }

    var displayName: String {
        switch self {
        case .interview: return "Interview"
        case .docAnalysis: return "Document Analysis"
        case .cardMerge: return "Card Merge"
        case .gitIngest: return "Git Ingest"
        case .inferenceGuidance: return "Inference Guidance"
        case .skillsProcessing: return "Skills Processing"
        case .skillCuration: return "Skill Curation"
        case .voiceProfile: return "Voice Profile"
        case .kcAgent: return "KC Agent"
        case .backgroundProcessing: return "Background Processing"
        }
    }

    /// True when requests bill the Anthropic API key directly; false when they
    /// bill the OpenRouter account. Drives the estimate's per-pool split.
    var billsToAnthropic: Bool {
        switch self {
        case .interview, .docAnalysis, .cardMerge, .gitIngest:
            return true
        case .inferenceGuidance, .skillsProcessing, .skillCuration,
             .voiceProfile, .kcAgent, .backgroundProcessing:
            return false
        }
    }
}

// MARK: - Presets

struct OnboardingModelPreset: Identifiable {
    let id: String
    let title: String
    let tagline: String
    let assignments: [OnboardingModelOperation: ClaudeFamily]

    static let frugal = OnboardingModelPreset(
        id: "frugal",
        title: "Frugal",
        tagline: "Cheapest viable run. Sonnet steers the interview; Haiku does the heavy lifting.",
        assignments: [
            .interview: .sonnet,
            .docAnalysis: .haiku,
            .cardMerge: .haiku,
            .gitIngest: .haiku,
            .inferenceGuidance: .haiku,
            .skillsProcessing: .haiku,
            .skillCuration: .sonnet,
            .voiceProfile: .sonnet,
            .kcAgent: .haiku,
            .backgroundProcessing: .haiku,
        ]
    )

    static let balanced = OnboardingModelPreset(
        id: "balanced",
        title: "Balanced",
        tagline: "Opus interviews you; Sonnet reads your documents; Haiku scans your code.",
        assignments: [
            .interview: .opus,
            .docAnalysis: .sonnet,
            .cardMerge: .sonnet,
            .gitIngest: .haiku,
            .inferenceGuidance: .sonnet,
            .skillsProcessing: .sonnet,
            .skillCuration: .sonnet,
            .voiceProfile: .opus,
            .kcAgent: .sonnet,
            .backgroundProcessing: .sonnet,
        ]
    )

    static let best = OnboardingModelPreset(
        id: "best",
        title: "Best",
        tagline: "Opus everywhere quality shows. Only repo scanning stays on a lighter model.",
        assignments: [
            .interview: .opus,
            .docAnalysis: .opus,
            .cardMerge: .opus,
            .gitIngest: .sonnet,
            .inferenceGuidance: .sonnet,
            .skillsProcessing: .sonnet,
            .skillCuration: .opus,
            .voiceProfile: .opus,
            .kcAgent: .opus,
            .backgroundProcessing: .sonnet,
        ]
    )

    static let all: [OnboardingModelPreset] = [.frugal, .balanced, .best]
}

// MARK: - Resolution

/// A preset with its families resolved to concrete live model IDs.
struct ResolvedModelPreset {
    let preset: OnboardingModelPreset
    /// Concrete model ID per operation (Anthropic ID or OpenRouter slug,
    /// matching what that operation's request path expects).
    let modelIds: [OnboardingModelOperation: String]
    let displayNames: [OnboardingModelOperation: String]
    /// Operations whose family had no live model in the fetched lists.
    let unresolved: [OnboardingModelOperation]

    /// Batch-write the resolved IDs through the operations' existing
    /// UserDefaults keys. Called only after explicit user confirmation.
    func apply() {
        for (operation, modelId) in modelIds {
            UserDefaults.standard.set(modelId, forKey: operation.defaultsKey)
        }
        Logger.info(
            "💰 Applied model preset '\(preset.id)': " +
            modelIds.map { "\($0.key.rawValue)=\($0.value)" }.sorted().joined(separator: ", "),
            category: .ai
        )
    }
}

enum ModelPresetCatalog {
    /// Resolve a preset's families against the live model lists.
    static func resolve(
        _ preset: OnboardingModelPreset,
        anthropicModels: [AnthropicModel],
        openRouterModels: [OpenRouterModel]
    ) -> ResolvedModelPreset {
        var modelIds: [OnboardingModelOperation: String] = [:]
        var displayNames: [OnboardingModelOperation: String] = [:]
        var unresolved: [OnboardingModelOperation] = []

        for (operation, family) in preset.assignments {
            if operation.billsToAnthropic {
                if let model = newestAnthropicModel(family: family, in: anthropicModels) {
                    modelIds[operation] = model.id
                    displayNames[operation] = model.displayName
                } else {
                    unresolved.append(operation)
                }
            } else {
                if let model = newestOpenRouterClaudeModel(family: family, in: openRouterModels) {
                    modelIds[operation] = model.id
                    displayNames[operation] = model.displayName
                } else {
                    unresolved.append(operation)
                }
            }
        }

        return ResolvedModelPreset(
            preset: preset,
            modelIds: modelIds,
            displayNames: displayNames,
            unresolved: unresolved.sorted { $0.rawValue < $1.rawValue }
        )
    }

    /// Newest live Anthropic model of a family: highest version vector, with
    /// `created_at` as the tiebreak.
    static func newestAnthropicModel(
        family: ClaudeFamily,
        in models: [AnthropicModel]
    ) -> AnthropicModel? {
        models
            .filter { matches(family: family, modelId: $0.id) }
            .max { lhs, rhs in
                let lhsVersion = version(of: lhs.id)
                let rhsVersion = version(of: rhs.id)
                if lhsVersion != rhsVersion {
                    return ModelPricing.isVersion(rhsVersion, newerThan: lhsVersion)
                }
                return (lhs.createdAt ?? "") < (rhs.createdAt ?? "")
            }
    }

    /// Newest Anthropic-vendor model of a family on OpenRouter. Variant
    /// endpoints (":free", ":thinking") are excluded; pricing must be present
    /// so estimates stay meaningful.
    static func newestOpenRouterClaudeModel(
        family: ClaudeFamily,
        in models: [OpenRouterModel]
    ) -> OpenRouterModel? {
        models
            .filter { model in
                model.id.hasPrefix("anthropic/")
                    && !model.id.contains(":")
                    && model.pricing?.promptUSDPerToken != nil
                    && matches(family: family, modelId: model.id)
            }
            .max { lhs, rhs in
                ModelPricing.isVersion(version(of: rhs.id), newerThan: version(of: lhs.id))
            }
    }

    private static func matches(family: ClaudeFamily, modelId: String) -> Bool {
        let normalized = ModelPricing.normalize(modelId)
        guard normalized.contains("claude") else { return false }
        return ModelPricing.familyAndVersion(normalized)?.family == family.rawValue
    }

    private static func version(of modelId: String) -> [Int] {
        ModelPricing.familyAndVersion(ModelPricing.normalize(modelId))?.version ?? []
    }
}
