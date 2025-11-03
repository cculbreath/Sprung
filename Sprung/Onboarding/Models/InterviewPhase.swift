//
//  InterviewPhase.swift
//  Sprung
//
//  Defines the phases of the onboarding interview process.
//

import Foundation

/// The phases of the onboarding interview
enum InterviewPhase: String, Codable, CaseIterable {
    case phase1CoreFacts = "Phase 1: Core Facts"
    case phase2DeepDive = "Phase 2: Deep Dive"
    case phase3WritingCorpus = "Phase 3: Writing Corpus"
    case complete = "Complete"

    /// Human-readable description
    var description: String {
        rawValue
    }

    /// Short identifier for logging
    var shortName: String {
        switch self {
        case .phase1CoreFacts:
            return "phase1"
        case .phase2DeepDive:
            return "phase2"
        case .phase3WritingCorpus:
            return "phase3"
        case .complete:
            return "complete"
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

/// Entry in the objective ledger
struct ObjectiveEntry: Codable {
    let id: String
    let status: ObjectiveStatus
    let source: String
    let timestamp: Date
    let notes: String?
}