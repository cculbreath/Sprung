//
//  JobAppStore.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/1/24.
//

import SwiftData

// Shared helper for SwiftData persistence.

@Observable
@MainActor
final class JobAppStore: SwiftDataStore {
    // MARK: - Properties

    unowned let modelContext: ModelContext
    // Computed collection that always reflects the latest state stored in
    // `modelContext`.  Because this is *computed*, any view access will fetch
    // directly from SwiftData and therefore stay in sync with persistent
    // storage without additional bookkeeping.
    var jobApps: [JobApp] {
        (try? modelContext.fetch(FetchDescriptor<JobApp>())) ?? []
    }

    var selectedApp: JobApp?
    var form = JobAppForm()
    var resStore: ResStore
    var coverLetterStore: CoverLetterStore

    // MARK: - Initialiser

    init(context: ModelContext, resStore: ResStore, coverLetterStore: CoverLetterStore) {
        modelContext = context
        self.resStore = resStore
        self.coverLetterStore = coverLetterStore
    }

    // MARK: - Methods

    func updateJobAppStatus(_ jobApp: JobApp, to newStatus: Statuses) {
        jobApp.status = newStatus
//    saveContext()
        // Handle additional logic like saving or notifying listeners
    }

    func addJobApp(_ jobApp: JobApp) -> JobApp? {
        // Side‑effect: create an empty cover‑letter placeholder so the UI can
        // immediately reference `selectedCover`.
        coverLetterStore.createBlank(jobApp: jobApp)

        modelContext.insert(jobApp)
        saveContext()

        selectedApp = jobApp
        return jobApp
    }

    func deleteSelected() {
        guard let deleteMe = selectedApp else {
            fatalError("No job application available to delete.")
        }

        deleteJobApp(deleteMe)
        // Fallback to most recent app (if any)
        selectedApp = jobApps.last
    }

    func deleteJobApp(_ jobApp: JobApp) {
        // Clean up child objects first
        for resume in jobApp.resumes {
            resStore.deleteRes(resume)
        }

        modelContext.delete(jobApp)
        saveContext()

        if selectedApp == jobApp {
            selectedApp = nil
        }
        if selectedApp == nil {
            selectedApp = jobApps.first
        }
    }

    private func populateFormFromObj(_ jobApp: JobApp) {
        form.populateFormFromObj(jobApp)
    }

    func editWithForm(_ jobApp: JobApp? = nil) {
        let jobAppEditing = jobApp ?? selectedApp
        guard let jobAppEditing = jobAppEditing else {
            fatalError("No job application available to edit.")
        }
        populateFormFromObj(jobAppEditing)
    }

    func cancelFormEdit(_ jobApp: JobApp? = nil) {
        let jobAppEditing = jobApp ?? selectedApp
        guard let jobAppEditing = jobAppEditing else {
            fatalError("No job application available to restore state.")
        }
        populateFormFromObj(jobAppEditing)
    }

    func saveForm(_ jobApp: JobApp? = nil) {
        let jobAppToSave = jobApp ?? selectedApp
        guard let jobAppToSave = jobAppToSave else {
            fatalError("No job application available to save.")
        }
        jobAppToSave.assignPropsFromForm(form)
//    saveContext()
    }

    func updateJobApp(_: JobApp) {
        // Persist the changes that should already be reflected on the entity
        // instance.
        _ = saveContext()
    }

    // Save changes to the database
    // `saveContext()` now lives in `SwiftDataStore`.
}
