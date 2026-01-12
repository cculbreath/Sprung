//
//  CandidateDossierStore.swift
//  Sprung
//
//  Repository for CandidateDossier CRUD operations.
//  Injected via @Environment for SwiftUI views.
//

import Foundation
import SwiftData

@Observable
@MainActor
final class CandidateDossierStore: SwiftDataStore {
    unowned let modelContext: ModelContext

    init(context: ModelContext) {
        modelContext = context
    }

    // MARK: - Read

    /// The current candidate dossier (there should only be one)
    var dossier: CandidateDossier? {
        let descriptor = FetchDescriptor<CandidateDossier>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor))?.first
    }

    /// All dossiers (for debugging/migration)
    var allDossiers: [CandidateDossier] {
        (try? modelContext.fetch(FetchDescriptor<CandidateDossier>())) ?? []
    }

    /// Whether a dossier exists
    var hasDossier: Bool {
        dossier != nil
    }

    // MARK: - Create/Update

    /// Create or update the candidate dossier
    @discardableResult
    func upsertDossier(
        jobSearchContext: String,
        strengthsToEmphasize: String? = nil,
        pitfallsToAvoid: String? = nil,
        workArrangementPreferences: String? = nil,
        availability: String? = nil,
        uniqueCircumstances: String? = nil,
        interviewerNotes: String? = nil
    ) -> CandidateDossier {
        if let existing = dossier {
            // Update existing
            existing.jobSearchContext = jobSearchContext
            existing.strengthsToEmphasize = strengthsToEmphasize
            existing.pitfallsToAvoid = pitfallsToAvoid
            existing.workArrangementPreferences = workArrangementPreferences
            existing.availability = availability
            existing.uniqueCircumstances = uniqueCircumstances
            existing.interviewerNotes = interviewerNotes
            existing.updatedAt = Date()
            saveContext()
            Logger.info("Updated candidate dossier (\(existing.wordCount) words)", category: .storage)
            return existing
        } else {
            // Create new
            let newDossier = CandidateDossier(
                jobSearchContext: jobSearchContext,
                strengthsToEmphasize: strengthsToEmphasize,
                pitfallsToAvoid: pitfallsToAvoid,
                workArrangementPreferences: workArrangementPreferences,
                availability: availability,
                uniqueCircumstances: uniqueCircumstances,
                interviewerNotes: interviewerNotes
            )
            modelContext.insert(newDossier)
            saveContext()
            Logger.info("Created candidate dossier (\(newDossier.wordCount) words)", category: .storage)
            return newDossier
        }
    }

    /// Update a specific field on the dossier
    func updateField(_ keyPath: WritableKeyPath<CandidateDossier, String>, value: String) {
        guard var existing = dossier else {
            Logger.warning("Cannot update field - no dossier exists", category: .storage)
            return
        }
        existing[keyPath: keyPath] = value
        existing.updatedAt = Date()
        saveContext()
    }

    /// Update an optional string field
    func updateOptionalField(_ keyPath: WritableKeyPath<CandidateDossier, String?>, value: String?) {
        guard var existing = dossier else {
            Logger.warning("Cannot update field - no dossier exists", category: .storage)
            return
        }
        existing[keyPath: keyPath] = value
        existing.updatedAt = Date()
        saveContext()
    }

    // MARK: - Section-Based Updates

    /// Update a specific dossier section, creating dossier if needed.
    /// Used by complete_dossier_section tool for incremental dossier building.
    @discardableResult
    func updateSection(_ section: DossierSection, content: String) -> CandidateDossier {
        if let existing = dossier {
            // Update existing dossier
            switch section {
            case .jobContext:
                existing.jobSearchContext = content
            case .strengths:
                existing.strengthsToEmphasize = content
            case .pitfalls:
                existing.pitfallsToAvoid = content
            case .workPreferences:
                existing.workArrangementPreferences = content
            case .availability:
                existing.availability = content
            case .uniqueCircumstances:
                existing.uniqueCircumstances = content
            case .notes:
                existing.interviewerNotes = content
            }
            existing.updatedAt = Date()
            saveContext()
            Logger.info("Updated dossier section '\(section.rawValue)' (\(content.count) chars)", category: .storage)
            return existing
        } else {
            // Create new dossier with this section
            let newDossier = CandidateDossier()
            switch section {
            case .jobContext:
                newDossier.jobSearchContext = content
            case .strengths:
                newDossier.strengthsToEmphasize = content
            case .pitfalls:
                newDossier.pitfallsToAvoid = content
            case .workPreferences:
                newDossier.workArrangementPreferences = content
            case .availability:
                newDossier.availability = content
            case .uniqueCircumstances:
                newDossier.uniqueCircumstances = content
            case .notes:
                newDossier.interviewerNotes = content
            }
            modelContext.insert(newDossier)
            saveContext()
            Logger.info("Created dossier with section '\(section.rawValue)' (\(content.count) chars)", category: .storage)
            return newDossier
        }
    }

    /// Get current content for a section (for validation/review)
    func sectionContent(_ section: DossierSection) -> String? {
        guard let existing = dossier else { return nil }
        switch section {
        case .jobContext:
            return existing.jobSearchContext.isEmpty ? nil : existing.jobSearchContext
        case .strengths:
            return existing.strengthsToEmphasize
        case .pitfalls:
            return existing.pitfallsToAvoid
        case .workPreferences:
            return existing.workArrangementPreferences
        case .availability:
            return existing.availability
        case .uniqueCircumstances:
            return existing.uniqueCircumstances
        case .notes:
            return existing.interviewerNotes
        }
    }

    /// Check which sections are complete (meet minimum length requirements)
    func completedSections() -> [DossierSection] {
        guard let existing = dossier else { return [] }
        var completed: [DossierSection] = []

        if existing.jobSearchContext.count >= CandidateDossier.FieldMinimums.jobSearchContext {
            completed.append(.jobContext)
        }
        if let strengths = existing.strengthsToEmphasize, strengths.count >= CandidateDossier.FieldMinimums.strengthsToEmphasize {
            completed.append(.strengths)
        }
        if let pitfalls = existing.pitfallsToAvoid, pitfalls.count >= CandidateDossier.FieldMinimums.pitfallsToAvoid {
            completed.append(.pitfalls)
        }
        // Optional sections just need content
        if let prefs = existing.workArrangementPreferences, !prefs.isEmpty {
            completed.append(.workPreferences)
        }
        if let avail = existing.availability, !avail.isEmpty {
            completed.append(.availability)
        }
        if let circumstances = existing.uniqueCircumstances, !circumstances.isEmpty {
            completed.append(.uniqueCircumstances)
        }
        if let notes = existing.interviewerNotes, notes.count >= CandidateDossier.FieldMinimums.interviewerNotes {
            completed.append(.notes)
        }

        return completed
    }

    /// Check which required sections are missing
    func missingSections() -> [DossierSection] {
        let completed = Set(completedSections())
        let required: [DossierSection] = [.jobContext, .strengths, .pitfalls]
        return required.filter { !completed.contains($0) }
    }

    // MARK: - Delete

    /// Delete the candidate dossier
    func deleteDossier() {
        guard let existing = dossier else { return }
        modelContext.delete(existing)
        saveContext()
        Logger.info("Deleted candidate dossier", category: .storage)
    }

    /// Delete all dossiers (for reset)
    func deleteAllDossiers() {
        for d in allDossiers {
            modelContext.delete(d)
        }
        saveContext()
        Logger.info("Deleted all candidate dossiers", category: .storage)
    }

    // MARK: - Export

    /// Export dossier for cover letter generation
    func exportForCoverLetter() -> String? {
        dossier?.exportForCoverLetter()
    }

    /// Export full dossier including private fields
    func exportFull() -> String? {
        dossier?.exportFull()
    }
}

// MARK: - Dossier Section Enum

/// Sections of the candidate dossier for incremental updates
enum DossierSection: String, CaseIterable, Codable {
    case jobContext = "job_context"
    case strengths = "strengths"
    case pitfalls = "pitfalls"
    case workPreferences = "work_preferences"
    case availability = "availability"
    case uniqueCircumstances = "unique_circumstances"
    case notes = "notes"

    var displayName: String {
        switch self {
        case .jobContext: return "Job Search Context"
        case .strengths: return "Strengths to Emphasize"
        case .pitfalls: return "Pitfalls to Avoid"
        case .workPreferences: return "Work Arrangement Preferences"
        case .availability: return "Availability"
        case .uniqueCircumstances: return "Unique Circumstances"
        case .notes: return "Interviewer Notes"
        }
    }

    /// Minimum character count for this section (0 = optional)
    var minimumLength: Int {
        switch self {
        case .jobContext: return CandidateDossier.FieldMinimums.jobSearchContext
        case .strengths: return CandidateDossier.FieldMinimums.strengthsToEmphasize
        case .pitfalls: return CandidateDossier.FieldMinimums.pitfallsToAvoid
        case .notes: return CandidateDossier.FieldMinimums.interviewerNotes
        case .workPreferences, .availability, .uniqueCircumstances: return 0
        }
    }

    /// Whether this section is required for dossier completion
    var isRequired: Bool {
        switch self {
        case .jobContext, .strengths, .pitfalls: return true
        case .workPreferences, .availability, .uniqueCircumstances, .notes: return false
        }
    }

    /// Objective to mark complete when this section is filled
    var associatedObjective: OnboardingObjectiveId? {
        switch self {
        case .strengths: return .strengthsIdentified
        case .pitfalls: return .pitfallsDocumented
        default: return nil
        }
    }
}
