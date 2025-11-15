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
                id: "gpt-5.1",
                defaultVerbosity: "medium",
                defaultReasoningEffort: userReasoningEffort(defaultValue: "medium")
            )
        case .knowledgeCard:
            return Config(
                id: "gpt-5.1",
                defaultVerbosity: "medium",
                defaultReasoningEffort: nil
            )
        case .validate, .extract:
            return Config(
                id: "gpt-5-mini",
                defaultVerbosity: "low",
                defaultReasoningEffort: "minimal"
            )
        case .summarize:
            return Config(
                id: "gpt-5-nano",
                defaultVerbosity: "low",
                defaultReasoningEffort: "minimal"
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

    private static let supportedReasoningEfforts: Set<String> = ["minimal", "low", "medium", "high"]

    private static func userReasoningEffort(defaultValue: String?) -> String? {
        let stored = UserDefaults.standard.string(forKey: "reasoningEffort")?.lowercased()
        if let stored, supportedReasoningEfforts.contains(stored) {
            return stored
        }
        return defaultValue
    }
}
