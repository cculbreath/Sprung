//
//  PhaseScriptRegistry.swift
//  Sprung
//
//  Registry for phase scripts, providing access to phase-specific behavior.
//

import Foundation

@MainActor
final class PhaseScriptRegistry {
    // MARK: - Properties

    private let scripts: [InterviewPhase: PhaseScript]

    // MARK: - Init

    init() {
        self.scripts = [
            .phase1CoreFacts: PhaseOneScript(),
            .phase2DeepDive: PhaseTwoScript(),
            .phase3WritingCorpus: PhaseThreeScript()
        ]
    }

    // MARK: - Public API

    /// Returns the script for the given phase.
    func script(for phase: InterviewPhase) -> PhaseScript? {
        scripts[phase]
    }

    /// Returns the script for the current session phase.
    func currentScript(for session: InterviewSession) -> PhaseScript? {
        script(for: session.phase)
    }

    /// Builds a complete system prompt by combining base instructions with the current phase script.
    func buildSystemPrompt(for session: InterviewSession) -> String {
        let basePrompt = Self.baseSystemPrompt()

        guard let currentScript = currentScript(for: session) else {
            return basePrompt
        }

        return """
        \(basePrompt)

        ---

        \(currentScript.systemPromptFragment)
        """
    }

    // MARK: - Base System Prompt

    private static func baseSystemPrompt() -> String {
        SystemPromptTemplates.basePrompt
    }
}
