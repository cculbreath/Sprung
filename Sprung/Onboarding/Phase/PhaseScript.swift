//
//  PhaseScript.swift
//  Sprung
//
//  Strategy protocol for onboarding interview phases.
//  Each phase defines its own objectives, system prompt fragment, and validation logic.
//

import Foundation

/// Defines the behavior and configuration for a specific interview phase.
protocol PhaseScript {
    /// The phase this script represents.
    var phase: InterviewPhase { get }

    /// System prompt fragment describing this phase's goals and tools.
    var systemPromptFragment: String { get }

    /// Required objectives that must be completed before advancing.
    var requiredObjectives: [String] { get }

    /// Validates whether this phase can advance based on completed objectives.
    func canAdvance(session: InterviewSession) -> Bool

    /// Returns missing objectives for this phase.
    func missingObjectives(session: InterviewSession) -> [String]
}

// MARK: - Default Implementations

extension PhaseScript {
    func canAdvance(session: InterviewSession) -> Bool {
        requiredObjectives.allSatisfy { session.objectivesDone.contains($0) }
    }

    func missingObjectives(session: InterviewSession) -> [String] {
        requiredObjectives.filter { !session.objectivesDone.contains($0) }
    }
}
