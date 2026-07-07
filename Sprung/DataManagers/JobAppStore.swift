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
final class JobAppStore: EntityStore {
    typealias Entity = JobApp
    // MARK: - Properties
    unowned let modelContext: ModelContext

    /// `@Observable` refresh counter (see EntityStore). `fetchAll()` reads it and
    /// every mutation persists via `persistChanges()`, so the pipeline columns
    /// re-render when a job is added, deleted, or changes status (this store
    /// previously had no such counter — its fetched lists could go stale).
    var changeVersion: Int = 0

    // Computed collection that always reflects the latest state stored in
    // `modelContext`. Routed through EntityStore.fetchAll so a view access
    // establishes a changeVersion dependency that mutations invalidate.
    var jobApps: [JobApp] { fetchAll() }
    var selectedApp: JobApp?
    var form = JobAppForm()
    var resStore: ResStore
    var coverLetterStore: CoverLetterStore

    // MARK: - Preprocessing
    private var preprocessor: JobAppPreprocessor?
    private weak var knowledgeCardStore: KnowledgeCardStore?

    /// Background full-posting fetch + deferred preprocessing for MCP-imported
    /// leads (Dice/ZipRecruiter). Owned by the store so enrichment outlives the
    /// search sheet that imported the lead; it calls back into this store to
    /// persist the fetched description and drive `rerunPreprocessing`. Defined
    /// alongside the import flow in JobMCPImportService.swift.
    let leadEnrichment: JobLeadEnrichmentService

    // MARK: - Initialiser
    init(context: ModelContext, resStore: ResStore, coverLetterStore: CoverLetterStore) {
        modelContext = context
        self.resStore = resStore
        self.coverLetterStore = coverLetterStore
        leadEnrichment = JobLeadEnrichmentService()
    }

    /// Set the preprocessor and KnowledgeCardStore for background job processing
    func setPreprocessor(_ preprocessor: JobAppPreprocessor, knowledgeCardStore: KnowledgeCardStore) {
        self.preprocessor = preprocessor
        self.knowledgeCardStore = knowledgeCardStore
    }

    /// Re-run preprocessing for a job (use when preprocessing failed or needs refresh)
    func rerunPreprocessing(for jobApp: JobApp) {
        guard let preprocessor = preprocessor,
              let knowledgeCardStore = knowledgeCardStore,
              !jobApp.jobDescription.isEmpty else {
            Logger.warning("⚠️ [JobAppStore] Cannot re-run preprocessing: missing dependencies or empty job description", category: .ai)
            return
        }

        // Clear existing preprocessing data
        jobApp.extractedRequirements = nil
        jobApp.relevantCardIds = nil
        persistChanges()

        preprocessor.preprocessInBackground(
            for: jobApp,
            allCards: knowledgeCardStore.knowledgeCards,
            modelContext: modelContext
        )
        Logger.info("🔄 [JobAppStore] Re-running preprocessing for: \(jobApp.jobPosition)", category: .ai)
    }

    /// Preprocess all jobs that are missing preprocessing data
    /// Returns the count of jobs queued for preprocessing
    @discardableResult
    func preprocessAllPendingJobs() -> Int {
        guard let preprocessor = preprocessor,
              let knowledgeCardStore = knowledgeCardStore else {
            Logger.warning("⚠️ [JobAppStore] Cannot preprocess jobs: preprocessor not configured", category: .ai)
            return 0
        }

        let jobsNeedingPreprocessing = jobApps.filter {
            !$0.jobDescription.isEmpty && !$0.hasPreprocessingComplete
        }

        guard !jobsNeedingPreprocessing.isEmpty else {
            Logger.info("✅ [JobAppStore] All jobs already preprocessed", category: .ai)
            return 0
        }

        let cards = knowledgeCardStore.knowledgeCards
        for jobApp in jobsNeedingPreprocessing {
            preprocessor.preprocessInBackground(
                for: jobApp,
                allCards: cards,
                modelContext: modelContext
            )
        }

        Logger.info("🚀 [JobAppStore] Queued \(jobsNeedingPreprocessing.count) jobs for preprocessing", category: .ai)
        return jobsNeedingPreprocessing.count
    }

    /// Re-run preprocessing for all active jobs (pending, queued, in-progress).
    /// This is useful when knowledge cards are updated and need to be re-matched.
    /// Returns the count of jobs queued for reprocessing.
    @discardableResult
    func rerunPreprocessingForActiveJobs() -> Int {
        guard let preprocessor = preprocessor,
              let knowledgeCardStore = knowledgeCardStore else {
            Logger.warning("⚠️ [JobAppStore] Cannot rerun preprocessing: preprocessor not configured", category: .ai)
            return 0
        }

        // Active statuses that should be reprocessed
        let activeStatuses: [Statuses] = [.new, .queued, .inProgress]

        let activeJobs = jobApps.filter { job in
            !job.jobDescription.isEmpty && activeStatuses.contains(job.status)
        }

        guard !activeJobs.isEmpty else {
            Logger.info("✅ [JobAppStore] No active jobs to reprocess", category: .ai)
            return 0
        }

        let cards = knowledgeCardStore.knowledgeCards
        for jobApp in activeJobs {
            // Clear existing preprocessing to force re-run
            jobApp.extractedRequirements = nil
            jobApp.relevantCardIds = nil

            preprocessor.preprocessInBackground(
                for: jobApp,
                allCards: cards,
                modelContext: modelContext
            )
        }

        persistChanges()
        Logger.info("🔄 [JobAppStore] Queued \(activeJobs.count) active jobs for reprocessing", category: .ai)
        return activeJobs.count
    }
    // MARK: - Methods
    func updateJobAppStatus(_ jobApp: JobApp, to newStatus: Statuses) {
        jobApp.status = newStatus
        persistChanges()
        // Handle additional logic like notifying listeners as needed
    }
    /// Add a job app and (unless deferred) trigger background preprocessing.
    ///
    /// `deferringPreprocessing: true` is for lead imports whose stored
    /// description is a stand-in for a fuller one that arrives later — the MCP
    /// boards' truncated/absent summaries. The lead lands instantly and
    /// `JobLeadEnrichmentService` triggers preprocessing itself once the full
    /// posting is fetched (or on the summary as the fallback when the fetch
    /// fails), so preprocessing never runs on the truncated text first.
    func addJobApp(_ jobApp: JobApp, deferringPreprocessing: Bool = false) -> JobApp? {
        modelContext.insert(jobApp)
        persistChanges()
        selectedApp = jobApp

        // Trigger background preprocessing (requirements + relevant cards)
        if !deferringPreprocessing,
           let preprocessor = preprocessor,
           let knowledgeCardStore = knowledgeCardStore,
           !jobApp.jobDescription.isEmpty {
            preprocessor.preprocessInBackground(
                for: jobApp,
                allCards: knowledgeCardStore.knowledgeCards,
                modelContext: modelContext
            )
        }

        return jobApp
    }

    /// Find an existing job app that already represents a posting, so an
    /// import pipeline (Indeed scrape, Dice/ZipRecruiter MCP search) can treat
    /// it as a duplicate instead of inserting a copy.
    ///
    /// Checks `postingURL` equality first — skipped when `url` is `nil` or
    /// empty, which callers whose board issues unstable per-request redirect
    /// URLs (e.g. ZipRecruiter's `job_redirect_url` match-token links) should
    /// pass. Falls back to an exact title+company match.
    func findDuplicateJobApp(url: String?, title: String, company: String) -> JobApp? {
        if let url, !url.isEmpty, let existingByURL = jobApps.first(where: { $0.postingURL == url }) {
            return existingByURL
        }
        return jobApps.first { $0.jobPosition == title && $0.companyName == company }
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
        persistChanges()
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
        persistChanges()
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
        let jobDescriptionChanged = jobAppToSave.jobDescription != form.jobDescription
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
        jobAppToSave.salary = form.salary
        persistChanges()

        // Preprocessing results are derived from the job description — they
        // must never silently outlive an edit to it. Clear them first (even if
        // re-queueing is impossible), then re-queue when a description exists.
        if jobDescriptionChanged {
            jobAppToSave.extractedRequirements = nil
            jobAppToSave.relevantCardIds = nil
            persistChanges()
            Logger.info("🧹 [JobAppStore] Job description changed — cleared stale preprocessing for: \(jobAppToSave.jobPosition)", category: .ai)
            if !jobAppToSave.jobDescription.isEmpty {
                rerunPreprocessing(for: jobAppToSave)
            }
        }
    }
    func updateJobApp(_: JobApp) {
        // Persist the changes that should already be reflected on the entity
        // instance.
        persistChanges()
    }

    // MARK: - Pipeline Queries

    /// All job apps sorted by creation date (newest first)
    var allJobAppsSorted: [JobApp] {
        fetchAll(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
    }

    /// Job apps filtered by status
    func jobApps(forStatus status: Statuses) -> [JobApp] {
        allJobAppsSorted.filter { $0.status == status }
    }

    /// Find a job app by ID
    func jobApp(byId id: UUID) -> JobApp? {
        allJobAppsSorted.first { $0.id == id }
    }

    // MARK: - Pipeline CRUD

    /// Add a new job app to the pipeline
    func addToPipeline(_ jobApp: JobApp) {
        add(jobApp)
    }

    // MARK: - Status Management

    /// Advance a job app to the next status in the pipeline
    func advanceStatus(_ jobApp: JobApp) {
        guard let nextStatus = jobApp.status.next else { return }
        setStatus(jobApp, to: nextStatus)
    }

    /// Set a job app to a specific status, stamping the dates that stage
    /// implies (non-linear moves from the pipeline card menu stamp the same
    /// milestones a step-by-step advance would).
    func setStatus(_ jobApp: JobApp, to status: Statuses) {
        jobApp.status = status

        switch status {
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

        persistChanges()
    }

    /// Mark a job app as rejected
    func reject(_ jobApp: JobApp, reason: String?) {
        jobApp.status = .rejected
        jobApp.rejectionReason = reason
        jobApp.closedDate = Date()
        persistChanges()
    }
}
