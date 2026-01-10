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
