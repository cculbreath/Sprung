//
//  PreprocessingStatusTests.swift
//  SprungTests
//
//  Regression coverage for the persisted tri-state `JobApp.preprocessingStatus`
//  (pending / complete / failed). Before this, "Awaiting analysis" was inferred
//  from `extractedRequirements?.isValid`, which meant a completed pass that
//  legitimately found no requirements looked identical to one that never ran —
//  and both a failed pass and a never-run one rendered the same "pending" clock
//  forever. See plans/app-audit-2026-07-06-jobapp-shell.md sections 2.2 and 3.2.
//

import XCTest
import SwiftData
@testable import Sprung

@MainActor
final class PreprocessingStatusTests: InMemoryStoreCase {

    /// Builds the full store dependency chain bound to the test context.
    /// (Mirrors `DependentStoresTests.makeStores` — kept local since this file
    /// intentionally wires the preprocessor, which that suite avoids.)
    private func makeStores() -> (jobAppStore: JobAppStore, knowledgeCardStore: KnowledgeCardStore) {
        let templateStore = TemplateStore(context: context)
        let applicantProfileStore = ApplicantProfileStore(context: context)
        let experienceDefaultsStore = ExperienceDefaultsStore(context: context)
        let coverRefStore = CoverRefStore(context: context)

        let exportService = ResumeExportService(
            templateStore: templateStore,
            applicantProfileStore: applicantProfileStore
        )
        let exportCoordinator = ResumeExportCoordinator(exportService: exportService)
        let resStore = ResStore(
            context: context,
            exportCoordinator: exportCoordinator,
            experienceDefaultsStore: experienceDefaultsStore
        )
        let coverLetterStore = CoverLetterStore(
            context: context,
            refStore: coverRefStore,
            applicantProfileStore: applicantProfileStore
        )
        let jobAppStore = JobAppStore(
            context: context,
            resStore: resStore,
            coverLetterStore: coverLetterStore
        )
        let knowledgeCardStore = KnowledgeCardStore(context: context)
        return (jobAppStore, knowledgeCardStore)
    }

    // MARK: - Default state

    func testFreshJobAppDefaultsToPendingWithNoDate() {
        let job = JobApp(jobPosition: "Engineer")
        XCTAssertEqual(job.preprocessingStatus, .pending)
        XCTAssertFalse(job.hasPreprocessingComplete)
        XCTAssertNil(job.preprocessingStatusDate)
    }

    // MARK: - Completed-but-empty extraction must count as complete

    func testCompletedEmptyExtractionCountsAsCompleteNotPending() {
        let job = JobApp(jobPosition: "Engineer", jobDescription: "desc")
        // A real pass ran and legitimately found nothing (isValid == false),
        // but it DID complete — this must not read as "still pending".
        job.extractedRequirements = ExtractedRequirements(
            mustHave: [], strongSignal: [], preferred: [], cultural: [],
            atsKeywords: [], extractedAt: Date(), extractionModel: "test-model"
        )
        job.preprocessingStatus = .complete
        job.preprocessingStatusDate = Date()

        XCTAssertFalse(job.extractedRequirements!.isValid)
        XCTAssertTrue(job.hasPreprocessingComplete)
    }

    func testPreprocessAllPendingJobsExcludesCompletedEmptyAndFailedJobs() async throws {
        let stores = makeStores()
        let preprocessor = JobAppPreprocessor(llmFacade: nil)
        stores.jobAppStore.setPreprocessor(preprocessor, knowledgeCardStore: stores.knowledgeCardStore)

        let completedEmpty = JobApp(jobPosition: "CompletedEmpty", jobDescription: "desc")
        completedEmpty.extractedRequirements = ExtractedRequirements(
            mustHave: [], strongSignal: [], preferred: [], cultural: [],
            atsKeywords: [], extractedAt: Date(), extractionModel: "test-model"
        )
        completedEmpty.preprocessingStatus = .complete

        let failed = JobApp(jobPosition: "Failed", jobDescription: "desc")
        failed.preprocessingStatus = .failed
        failed.preprocessingStatusDate = Date()

        let neverRun = JobApp(jobPosition: "NeverRun", jobDescription: "desc")

        // Defer preprocessing on insert so only preprocessAllPendingJobs queues work.
        _ = stores.jobAppStore.addJobApp(completedEmpty, deferringPreprocessing: true)
        _ = stores.jobAppStore.addJobApp(failed, deferringPreprocessing: true)
        _ = stores.jobAppStore.addJobApp(neverRun, deferringPreprocessing: true)

        let queuedCount = stores.jobAppStore.preprocessAllPendingJobs()

        // Only the never-run job should be queued — the completed-but-empty
        // job must not be silently re-billed, and a failed job needs an
        // explicit retry rather than being swept up in bulk re-analysis.
        XCTAssertEqual(queuedCount, 1)

        // Let the queued (nil-facade) pass settle before the test tears the
        // in-memory container down, so nothing writes to it after teardown.
        for _ in 0..<50 {
            if neverRun.preprocessingStatus != .pending { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(neverRun.preprocessingStatus, .failed)
        XCTAssertEqual(completedEmpty.preprocessingStatus, .complete)
        XCTAssertEqual(failed.preprocessingStatus, .failed)
    }

    // MARK: - Failure path persists `.failed`, distinct from `.pending`

    func testPreprocessorMarksFailedWhenLLMFacadeUnavailable() async throws {
        let preprocessor = JobAppPreprocessor(llmFacade: nil)
        let job = JobApp(jobPosition: "Engineer", jobDescription: "We need a Swift engineer.")
        insert(job)
        saveContext()

        preprocessor.preprocessInBackground(for: job, allCards: [], modelContext: context)

        // The failure happens on a background Task; poll briefly for it to land.
        for _ in 0..<50 {
            if job.preprocessingStatus != .pending { break }
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertEqual(job.preprocessingStatus, .failed)
        XCTAssertNotNil(job.preprocessingStatusDate)
        XCTAssertFalse(job.hasPreprocessingComplete)
    }

    // MARK: - Reset transitions back to `.pending`

    func testRerunPreprocessingResetsFailedJobToPending() async throws {
        let stores = makeStores()
        let preprocessor = JobAppPreprocessor(llmFacade: nil)
        stores.jobAppStore.setPreprocessor(preprocessor, knowledgeCardStore: stores.knowledgeCardStore)

        let job = JobApp(jobPosition: "Engineer", jobDescription: "desc")
        job.preprocessingStatus = .failed
        job.preprocessingStatusDate = Date()
        _ = stores.jobAppStore.addJobApp(job, deferringPreprocessing: true)

        stores.jobAppStore.rerunPreprocessing(for: job)

        // The reset to `.pending` (and clearing of the stale blob) happens
        // synchronously before the background retry is queued.
        XCTAssertEqual(job.preprocessingStatus, .pending)
        XCTAssertNil(job.extractedRequirements)
        XCTAssertNil(job.relevantCardIds)

        // Let the retry's (nil-facade) background pass settle before the test
        // tears the in-memory container down.
        for _ in 0..<50 {
            if job.preprocessingStatus != .pending { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(job.preprocessingStatus, .failed)
    }
}
