//
//  JobAppStore.swift
//  Sprung
//
//  Created by Christopher Culbreath on 9/1/24.
//
import SwiftData
import Foundation
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
        saveContext()
        // Handle additional logic like notifying listeners as needed
    }
    func addJobApp(_ jobApp: JobApp) -> JobApp? {
        modelContext.insert(jobApp)
        saveContext()
        selectedApp = jobApp
        return jobApp
    }
    func deleteSelected() {
        guard let deleteMe = selectedApp else {
            Logger.error("No job application available to delete.")
            return
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
            Logger.error("No job application available to edit.")
            return
        }
        populateFormFromObj(jobAppEditing)
    }
    func cancelFormEdit(_ jobApp: JobApp? = nil) {
        let jobAppEditing = jobApp ?? selectedApp
        guard let jobAppEditing = jobAppEditing else {
            Logger.error("No job application available to restore state.")
            return
        }
        populateFormFromObj(jobAppEditing)
    }
    func saveForm(_ jobApp: JobApp? = nil) {
        let jobAppToSave = jobApp ?? selectedApp
        guard let jobAppToSave = jobAppToSave else {
            Logger.error("No job application available to save.")
            return
        }
        // Directly assign properties from form
        jobAppToSave.jobPosition = form.jobPosition
        jobAppToSave.jobLocation = form.jobLocation
        jobAppToSave.companyName = form.companyName
        jobAppToSave.companyLinkedinId = form.companyLinkedinId
        jobAppToSave.jobPostingTime = form.jobPostingTime
        jobAppToSave.jobDescription = form.jobDescription
        jobAppToSave.seniorityLevel = form.seniorityLevel
        jobAppToSave.employmentType = form.employmentType
        jobAppToSave.jobFunction = form.jobFunction
        jobAppToSave.industries = form.industries
        jobAppToSave.jobApplyLink = form.jobApplyLink
        jobAppToSave.postingURL = form.postingURL
        saveContext()
    }
    func updateJobApp(_: JobApp) {
        // Persist the changes that should already be reflected on the entity
        // instance.
        _ = saveContext()
    }
    // Save changes to the database
    // `saveContext()` now lives in `SwiftDataStore`.
}
