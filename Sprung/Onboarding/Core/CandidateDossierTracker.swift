//
//  CandidateDossierTracker.swift
//  Sprung
//
//  Tracks which dossier fields have been collected during the interview.
//  Provides question suggestions for opportunistic dossier collection.
//
import Foundation

/// Dossier fields that can be collected during the interview
enum CandidateDossierField: String, CaseIterable {
    case jobSearchContext = "job_search_context"
    case workArrangementPreferences = "work_arrangement_preferences"
    case availability = "availability"
    case uniqueCircumstances = "unique_circumstances"
    case strengthsToEmphasize = "strengths_to_emphasize"
    case pitfallsToAvoid = "pitfalls_to_avoid"

    /// Human-readable description of the field
    var description: String {
        switch self {
        case .jobSearchContext:
            return "Job search motivation and priorities"
        case .workArrangementPreferences:
            return "Remote/hybrid/office preferences"
        case .availability:
            return "Start date and availability"
        case .uniqueCircumstances:
            return "Career gaps or pivots to address"
        case .strengthsToEmphasize:
            return "Hidden strengths to highlight"
        case .pitfallsToAvoid:
            return "Concerns to navigate"
        }
    }

    /// Sample question for this field
    var sampleQuestion: String {
        switch self {
        case .jobSearchContext:
            return "What's motivating your job search right now?"
        case .workArrangementPreferences:
            return "What's your preference for remote vs. in-office work?"
        case .availability:
            return "When could you start a new role?"
        case .uniqueCircumstances:
            return "Is there anything about your career path that might need framing for employers?"
        case .strengthsToEmphasize:
            return "Are there any strengths that might not be obvious from your resume?"
        case .pitfallsToAvoid:
            return "Are there any concerns we should be prepared to address?"
        }
    }

    /// Phase(s) where this field should be collected
    var applicablePhases: Set<InterviewPhase> {
        switch self {
        case .jobSearchContext, .workArrangementPreferences, .availability, .uniqueCircumstances:
            // Early fields - collect in Phase 1 or 2
            return [.phase1CoreFacts, .phase2DeepDive]
        case .strengthsToEmphasize, .pitfallsToAvoid:
            // Strategic fields - better to collect after understanding the candidate
            return [.phase2DeepDive, .phase3WritingCorpus]
        }
    }
}

/// Tracks collected dossier fields and provides next-field suggestions
struct CandidateDossierTracker {
    private(set) var collectedFields: Set<String> = []

    /// Mark a field as collected
    mutating func recordFieldCollected(_ field: String) {
        collectedFields.insert(field)
    }

    /// Get the next field to collect for the given phase, or nil if all applicable fields are collected
    func getNextField(for phase: InterviewPhase) -> CandidateDossierField? {
        for field in CandidateDossierField.allCases {
            guard field.applicablePhases.contains(phase) else { continue }
            guard !collectedFields.contains(field.rawValue) else { continue }
            return field
        }
        return nil
    }

    /// Check if a specific field has been collected
    func hasCollected(_ field: CandidateDossierField) -> Bool {
        collectedFields.contains(field.rawValue)
    }

    /// Get all uncollected fields for the given phase
    func getUncollectedFields(for phase: InterviewPhase) -> [CandidateDossierField] {
        CandidateDossierField.allCases.filter { field in
            field.applicablePhases.contains(phase) && !collectedFields.contains(field.rawValue)
        }
    }

    /// Build a prompt instructing the LLM to ask a dossier question
    func buildDossierPrompt(for phase: InterviewPhase) -> String? {
        guard let nextField = getNextField(for: phase) else {
            return nil
        }

        return """
            OPPORTUNISTIC DOSSIER COLLECTION:
            While the document is being extracted, ask the user about: \(nextField.description)

            Suggested question: "\(nextField.sampleQuestion)"

            When you receive their answer, persist it with:
            persist_data(dataType: "candidate_dossier_entry", data: {
                "field_type": "\(nextField.rawValue)",
                "question": "[your question]",
                "answer": "[their response]"
            })

            Keep the conversation natural - don't mention you're collecting dossier data.
            """
    }
}
