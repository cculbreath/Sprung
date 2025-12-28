//
//  JobAppStore.swift
//  Sprung
//
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

    // MARK: - Preprocessing
    private var preprocessor: JobAppPreprocessor?
    private weak var resRefStore: ResRefStore?

    // MARK: - Initialiser
    init(context: ModelContext, resStore: ResStore, coverLetterStore: CoverLetterStore) {
        modelContext = context
        self.resStore = resStore
        self.coverLetterStore = coverLetterStore
    }

    /// Set the preprocessor and ResRefStore for background job processing
    func setPreprocessor(_ preprocessor: JobAppPreprocessor, resRefStore: ResRefStore) {
        self.preprocessor = preprocessor
        self.resRefStore = resRefStore
    }

    /// Re-run preprocessing for a job (use when preprocessing failed or needs refresh)
    func rerunPreprocessing(for jobApp: JobApp) {
        guard let preprocessor = preprocessor,
              let resRefStore = resRefStore,
              !jobApp.jobDescription.isEmpty else {
            Logger.warning("⚠️ [JobAppStore] Cannot re-run preprocessing: missing dependencies or empty job description", category: .ai)
            return
        }

        // Clear existing preprocessing data
        jobApp.extractedRequirements = nil
        jobApp.relevantCardIds = nil
        saveContext()

        preprocessor.preprocessInBackground(
            for: jobApp,
            allCards: resRefStore.resRefs,
            modelContext: modelContext
        )
        Logger.info("🔄 [JobAppStore] Re-running preprocessing for: \(jobApp.jobPosition)", category: .ai)
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

        // Trigger background preprocessing (requirements + relevant cards)
        if let preprocessor = preprocessor,
           let resRefStore = resRefStore,
           !jobApp.jobDescription.isEmpty {
            preprocessor.preprocessInBackground(
                for: jobApp,
                allCards: resRefStore.resRefs,
                modelContext: modelContext
            )
        }

        return jobApp
    }

    /// Creates a new blank job application for manual entry
    func createManualEntry() -> JobApp {
        let jobApp = JobApp()
        jobApp.jobPosition = "New Position"
        jobApp.companyName = "Company Name"
        jobApp.status = .new
        jobApp.identifiedDate = Date()
        jobApp.source = "Manual Entry"
        modelContext.insert(jobApp)
        saveContext()
        selectedApp = jobApp
        // Enable edit mode via form
        editWithForm()
        Logger.info("📝 [JobAppStore] Created manual entry job app", category: .data)
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

    // MARK: - Pipeline Queries

    /// All job apps sorted by creation date (newest first)
    var allJobAppsSorted: [JobApp] {
        let descriptor = FetchDescriptor<JobApp>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Active job apps (not in terminal stages)
    var activeJobApps: [JobApp] {
        allJobAppsSorted.filter { $0.isActive }
    }

    /// Job apps filtered by status
    func jobApps(forStatus status: Statuses) -> [JobApp] {
        allJobAppsSorted.filter { $0.status == status }
    }

    /// Find a job app by ID
    func jobApp(byId id: UUID) -> JobApp? {
        allJobAppsSorted.first { $0.id == id }
    }

    // MARK: - Pipeline Stats

    /// Count of job apps per status
    var pipelineStats: [Statuses: Int] {
        Dictionary(grouping: allJobAppsSorted) { $0.status }
            .mapValues { $0.count }
    }

    /// Count of active job apps
    var activeCount: Int {
        activeJobApps.count
    }

    /// Count of applications submitted this week
    var thisWeeksApplications: Int {
        let calendar = Calendar.current
        let weekStart = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        ) ?? Date()

        return allJobAppsSorted.filter {
            guard let appliedDate = $0.appliedDate else { return false }
            return appliedDate >= weekStart
        }.count
    }

    // MARK: - Pipeline CRUD

    /// Add a new job app to the pipeline
    func addToPipeline(_ jobApp: JobApp) {
        modelContext.insert(jobApp)
        saveContext()
    }

    /// Add multiple job apps to the pipeline
    func addMultipleToPipeline(_ jobApps: [JobApp]) {
        for jobApp in jobApps {
            modelContext.insert(jobApp)
        }
        saveContext()
    }

    /// Delete a job app from the pipeline
    func deleteFromPipeline(_ jobApp: JobApp) {
        modelContext.delete(jobApp)
        saveContext()
    }

    // MARK: - Status Management

    /// Advance a job app to the next status in the pipeline
    func advanceStatus(_ jobApp: JobApp) {
        guard let nextStatus = jobApp.status.next else { return }

        jobApp.status = nextStatus

        // Track dates
        switch nextStatus {
        case .submitted:
            jobApp.appliedDate = Date()
        case .interview:
            if jobApp.firstInterviewDate == nil {
                jobApp.firstInterviewDate = Date()
            }
            jobApp.lastInterviewDate = Date()
            jobApp.interviewCount += 1
        case .offer:
            jobApp.offerDate = Date()
        case .accepted, .rejected, .withdrawn:
            jobApp.closedDate = Date()
        default:
            break
        }

        saveContext()
    }

    /// Set a job app to a specific status
    func setStatus(_ jobApp: JobApp, to status: Statuses) {
        jobApp.status = status

        if status == .accepted || status == .rejected || status == .withdrawn {
            jobApp.closedDate = Date()
        }

        saveContext()
    }

    /// Mark a job app as rejected
    func reject(_ jobApp: JobApp, reason: String?) {
        jobApp.status = .rejected
        jobApp.rejectionReason = reason
        jobApp.closedDate = Date()
        saveContext()
    }

    /// Mark a job app as withdrawn
    func withdraw(_ jobApp: JobApp, reason: String?) {
        jobApp.status = .withdrawn
        jobApp.withdrawalReason = reason
        jobApp.closedDate = Date()
        saveContext()
    }

    /// Record an interview for a job app
    func recordInterview(_ jobApp: JobApp, notes: String?) {
        jobApp.interviewCount += 1
        jobApp.lastInterviewDate = Date()
        if jobApp.firstInterviewDate == nil {
            jobApp.firstInterviewDate = Date()
        }
        if let notes = notes {
            jobApp.lastInterviewNotes = notes
        }
        saveContext()
    }

    // MARK: - Priority Management

    /// Set the priority of a job app
    func setPriority(_ jobApp: JobApp, to priority: JobLeadPriority) {
        jobApp.priority = priority
        saveContext()
    }

    // MARK: - Pipeline Filtering

    /// High priority active job apps
    var highPriorityJobApps: [JobApp] {
        activeJobApps.filter { $0.priority == .high }
    }

    /// Job apps that need attention based on staleness
    var needsAction: [JobApp] {
        activeJobApps.filter { jobApp in
            switch jobApp.status {
            case .new:
                return (jobApp.daysSinceCreated ?? 0) > 3
            case .queued:
                return (jobApp.daysSinceCreated ?? 0) > 5
            case .inProgress:
                return (jobApp.daysSinceCreated ?? 0) > 7
            case .submitted:
                return (jobApp.daysSinceApplied ?? 0) > 14
            case .interview:
                if let lastInterview = jobApp.lastInterviewDate {
                    let days = Calendar.current.dateComponents([.day], from: lastInterview, to: Date()).day ?? 0
                    return days > 7
                }
                return false
            default:
                return false
            }
        }
    }

    // MARK: - Source Tracking

    /// Count of job apps by source
    func jobAppsBySource() -> [String: Int] {
        Dictionary(grouping: allJobAppsSorted) { $0.source ?? "Unknown" }
            .mapValues { $0.count }
    }

    /// Count of successful (accepted) job apps by source
    func successfulJobAppsBySource() -> [String: Int] {
        Dictionary(grouping: allJobAppsSorted.filter { $0.status == .accepted }) { $0.source ?? "Unknown" }
            .mapValues { $0.count }
    }
}
