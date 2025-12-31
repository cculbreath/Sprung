//
//  InterviewPhase.swift
//  Sprung
//
//  Defines the phases of the onboarding interview process.
//
//  PHASE STRUCTURE (Interview Revitalization Plan):
//  - Phase 1: Voice & Context — Writing samples, job search context, profile
//  - Phase 2: Career Story — Timeline collection, active interviewing, dossier weaving
//  - Phase 3: Evidence Collection — Documents, git repos, card generation
//  - Phase 4: Strategic Synthesis — Strengths, pitfalls, dossier completion
//
import Foundation
/// The phases of the onboarding interview
enum InterviewPhase: String, Codable, CaseIterable {
    case phase1VoiceContext = "Phase 1: Voice & Context"
    case phase2CareerStory = "Phase 2: Career Story"
    case phase3EvidenceCollection = "Phase 3: Evidence Collection"
    case phase4StrategicSynthesis = "Phase 4: Strategic Synthesis"
    case complete = "Complete"

    /// Short identifier for logging
    var shortName: String {
        switch self {
        case .phase1VoiceContext:
            return "phase1"
        case .phase2CareerStory:
            return "phase2"
        case .phase3EvidenceCollection:
            return "phase3"
        case .phase4StrategicSynthesis:
            return "phase4"
        case .complete:
            return "complete"
        }
    }

    /// Human-readable display name for UI
    var displayName: String {
        rawValue
    }

    /// Returns the next phase in sequence, or nil if complete
    func next() -> InterviewPhase? {
        switch self {
        case .phase1VoiceContext:
            return .phase2CareerStory
        case .phase2CareerStory:
            return .phase3EvidenceCollection
        case .phase3EvidenceCollection:
            return .phase4StrategicSynthesis
        case .phase4StrategicSynthesis:
            return .complete
        case .complete:
            return nil
        }
    }
}
/// Status of an objective in the interview
enum ObjectiveStatus: String, Codable {
    case pending
    case inProgress = "in_progress"
    case completed
    case skipped
}
