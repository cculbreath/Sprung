//
//  CoverLetterStore.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/12/24.
//

//
//  swift
//  PhysicsCloudResume
//
//  Created by Christopher Culbreath on 8/30/24.
//

import Foundation
import SwiftData

// Replaces hand‑rolled `saveContext()` duplication with a shared helper.
import SwiftUI // Needed only for `@Observable` macro, already available.

@Observable
@MainActor
final class CoverLetterStore: SwiftDataStore {
    // MARK: - Properties

    unowned let modelContext: ModelContext
    var coverRefStore: CoverRefStore
    var cL: CoverLetter?
    private let exportService = LocalCoverLetterExportService()

    // MARK: - Initialiser

    init(context: ModelContext, refStore: CoverRefStore) {
        modelContext = context
        coverRefStore = refStore

        // Perform one-time migration for existing cover letters
        performMigrationForGeneratedFlag()
    }

    @discardableResult
    func addLetter(letter: CoverLetter, to jobApp: JobApp) -> CoverLetter {
        jobApp.coverLetters.append(letter)
        jobApp.selectedCover = letter
        modelContext.insert(letter)
//    saveContext()
        return letter
    }

    func createBlank(jobApp: JobApp) {
        let letter = CoverLetter(
            enabledRefs: coverRefStore.defaultSources,
            jobApp: jobApp
        )
        letter.generated = false
        jobApp.coverLetters.append(letter)
        jobApp.selectedCover = letter

        modelContext.insert(letter)
    }

    @discardableResult
    func create(jobApp: JobApp) -> CoverLetter {
        let letter = CoverLetter(
            enabledRefs: coverRefStore.defaultSources,
            jobApp: jobApp
        )

        modelContext.insert(letter)
//      try? modelContext.save()
        return letter
    }

    func createDuplicate(letter: CoverLetter) -> CoverLetter {
        saveContext() // From `SwiftDataStore` extension
        let newLetter = CoverLetter(
            enabledRefs: letter.enabledRefs,
            jobApp: letter.jobApp ?? nil
        )
        newLetter.includeResumeRefs = letter.includeResumeRefs
        newLetter.content = letter.content
        // Set generated to false initially, it will be updated to true
        // by processResults after AI generates content
        newLetter.generated = false
        newLetter.encodedMessageHistory = letter.encodedMessageHistory
        newLetter.currentMode = letter.currentMode
        // Preserve the existing cover letter name for revision operations
        newLetter.name = letter.name
        // Copy other necessary properties here

        if let jobApp = letter.jobApp {
            addLetter(letter: newLetter, to: jobApp)
        }
        saveContext()
        return newLetter
    }

    func deleteLetter(_ letter: CoverLetter) {
        if let jobApp = letter.jobApp {
            if let index = jobApp.coverLetters.firstIndex(of: letter) {
                jobApp.coverLetters.remove(at: index)
                modelContext.delete(letter)
                //      saveContext()
            }
        } else {}
    }

    // `saveContext()` now provided by `SwiftDataStore` default implementation.

    // MARK: - PDF Export

    func exportPDF(from coverLetter: CoverLetter) -> Data {
        return exportService.exportPDF(from: coverLetter, applicant: Applicant())
    }

    func exportAllCoverLetters(for jobApp: JobApp) -> [Data] {
        return jobApp.coverLetters.filter { $0.generated }.map { letter in
            exportService.exportPDF(from: letter, applicant: Applicant())
        }
    }

    // MARK: - Migration

    /// One-time migration to set generated = true for all existing cover letters with content
    @MainActor
    private func performMigrationForGeneratedFlag() {
        // Use AppStorage to track migration status
        let migrationKey = "CoverLetterGeneratedFlagMigrationCompleted"
        let defaults = UserDefaults.standard

        // Only run migration once
        if defaults.bool(forKey: migrationKey) {
            return
        }

        do {
            // Fetch all cover letters
            let descriptor = FetchDescriptor<CoverLetter>()
            let allCoverLetters = try modelContext.fetch(descriptor)

            var updatedCount = 0

            // Update only those with content but not marked as generated
            for letter in allCoverLetters {
                if !letter.content.isEmpty && !letter.generated {
                    letter.generated = true
                    updatedCount += 1
                }
            }

            if updatedCount > 0 {
                print("Migration: Set generated=true for \(updatedCount) cover letters with content")
                saveContext()
            }

            // Mark migration as completed
            defaults.set(true, forKey: migrationKey)

        } catch {
            print("Failed to perform cover letter migration: \(error.localizedDescription)")
        }
    }
}
