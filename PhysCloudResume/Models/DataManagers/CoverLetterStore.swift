
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
        print("CoverLetterStore Initialized")
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
        print("Model context available")
        print("Creating cover letter for job application: \(jobApp)")

        let letter = CoverLetter(
            enabledRefs: coverRefStore.defaultSources,
            jobApp: jobApp
        )
        print("CoverLetter object created")

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
        newLetter.generated = false
        newLetter.encodedMessageHistory = letter.encodedMessageHistory
        newLetter.currentMode = letter.currentMode
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
        } else {
            print("letter not attached to jobapp!")
        }
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
}
