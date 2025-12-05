//
//  ModelProvider.swift
//  Sprung
//
//  Centralizes model selection for onboarding interview tasks.
//
import Foundation
enum TaskType {
    case orchestrator
    case validate
    case extract
    case summarize
    case knowledgeCard
}
struct ModelProvider {
    struct Config {
        let id: String
        let defaultVerbosity: String?
        let defaultReasoningEffort: String?
    }
    static func forTask(_ type: TaskType) -> Config {
        switch type {
        case .orchestrator:
            return Config(
                id: OnboardingModelConfig.currentModelId,
                defaultVerbosity: "medium",
                defaultReasoningEffort: userReasoningEffort(defaultValue: "medium")
            )
        case .knowledgeCard:
            return Config(
                id: OnboardingModelConfig.currentModelId,
                defaultVerbosity: "medium",
                defaultReasoningEffort: nil
            )
        case .validate, .extract:
            return Config(
                id: "gpt-5-mini",
                defaultVerbosity: "low",
                defaultReasoningEffort: "low"  // GPT-5.1 supports: none, low, medium, high
            )
        case .summarize:
            return Config(
                id: "gpt-5-nano",
                defaultVerbosity: "low",
                defaultReasoningEffort: "low"  // GPT-5.1 supports: none, low, medium, high
            )
        }
    }
    static func escalate(_ prior: Config) -> Config {
        Config(
            id: "o1",
            defaultVerbosity: prior.defaultVerbosity,
            defaultReasoningEffort: nil
        )
    }
    // GPT-5.1 supports: none, low, medium, high (not "minimal")
    private static let supportedReasoningEfforts: Set<String> = ["none", "low", "medium", "high"]
    private static func userReasoningEffort(defaultValue: String?) -> String? {
        let stored = UserDefaults.standard.string(forKey: "reasoningEffort")?.lowercased()
        if let stored {
            // Migrate "minimal" → "low" for GPT-5.1 compatibility
            if stored == "minimal" {
                return "low"
            }
            if supportedReasoningEfforts.contains(stored) {
                return stored
            }
        }
        return defaultValue
    }
}
