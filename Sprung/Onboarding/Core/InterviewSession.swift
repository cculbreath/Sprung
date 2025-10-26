//
//  InterviewSession.swift
//  Sprung
//
//  Created for the clean-slate onboarding interview feature.
//

import Foundation

/// Represents the high-level phase progression for the onboarding interview.
enum InterviewPhase: String, Codable {
    case phase1CoreFacts
    case phase2DeepDive
    case phase3WritingCorpus
    case complete
}

/// Minimal session state tracked for the interview flow.
struct InterviewSession: Codable {
    var phase: InterviewPhase = .phase1CoreFacts
    var objectivesDone: Set<String> = []
    var waiting: Waiting? = nil

    enum Waiting: String, Codable {
        case selection
        case upload
        case validation
    }
}

/// Actor-isolated wrapper around the interview session for safe concurrent mutation.
actor InterviewState {
    private(set) var session = InterviewSession()

    func completeObjective(_ id: String) async {
        session.objectivesDone.insert(id)
    }

    func resetObjective(_ id: String) async {
        session.objectivesDone.remove(id)
    }

    func setWaiting(_ waiting: InterviewSession.Waiting?) async {
        session.waiting = waiting
    }

    func currentSession() -> InterviewSession {
        session
    }

    func restore(from snapshot: InterviewSession) {
        session = snapshot
        debugLog("State restored to phase: \(session.phase)")
    }

    func missingObjectives() -> [String] {
        let required: [String]
        switch session.phase {
        case .phase1CoreFacts:
            required = ["applicant_profile", "skeleton_timeline", "enabled_sections"]
        case .phase2DeepDive:
            required = ["interviewed_one_experience", "one_card_generated"]
        case .phase3WritingCorpus:
            required = ["one_writing_sample", "dossier_complete"]
        case .complete:
            required = []
        }
        return required.filter { !session.objectivesDone.contains($0) }
    }

    func nextPhase() -> InterviewPhase? {
        switch session.phase {
        case .phase1CoreFacts:
            return .phase2DeepDive
        case .phase2DeepDive:
            return .phase3WritingCorpus
        case .phase3WritingCorpus:
            return .complete
        case .complete:
            return nil
        }
    }

    func advanceToNextPhase() {
        advancePhase()
        debugLog("Advanced to phase: \(session.phase)")
    }

    private func shouldAdvancePhase() -> Bool {
        switch session.phase {
        case .phase1CoreFacts:
            return ["applicant_profile", "skeleton_timeline", "enabled_sections"]
                .allSatisfy(session.objectivesDone.contains)
        case .phase2DeepDive:
            return ["interviewed_one_experience", "one_card_generated"]
                .allSatisfy(session.objectivesDone.contains)
        case .phase3WritingCorpus:
            return ["one_writing_sample", "dossier_complete"]
                .allSatisfy(session.objectivesDone.contains)
        case .complete:
            return false
        }
    }

    private func advancePhase() {
        switch session.phase {
        case .phase1CoreFacts:
            session.phase = .phase2DeepDive
        case .phase2DeepDive:
            session.phase = .phase3WritingCorpus
        case .phase3WritingCorpus:
            session.phase = .complete
        case .complete:
            break
        }
    }
}
