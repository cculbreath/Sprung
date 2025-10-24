//
//  ModelProvider.swift
//  Sprung
//
//  Centralizes model selection for onboarding interview tasks.
//

import Foundation

enum ModelTaskType {
    case orchestrator
    case validate
    case extract
    case summarize
    case knowledgeCard
}

struct ModelProvider {
    struct Configuration {
        let id: String
        let defaultVerbosity: String?
        let defaultReasoningEffort: String?
    }

    static func configuration(for task: ModelTaskType) -> Configuration {
        switch task {
        case .orchestrator, .knowledgeCard:
            return Configuration(
                id: "gpt-5",
                defaultVerbosity: "medium",
                defaultReasoningEffort: nil
            )
        case .validate, .extract:
            return Configuration(
                id: "gpt-5-mini",
                defaultVerbosity: "low",
                defaultReasoningEffort: "minimal"
            )
        case .summarize:
            return Configuration(
                id: "gpt-5-nano",
                defaultVerbosity: "low",
                defaultReasoningEffort: "minimal"
            )
        }
    }

    static func escalate(from configuration: Configuration) -> Configuration {
        Configuration(
            id: "o1",
            defaultVerbosity: configuration.defaultVerbosity,
            defaultReasoningEffort: nil
        )
    }
}

