//
//  ResumeExportCoordinatorCallbackTests.swift
//  SprungTests
//
//  Pins the debounceExport callback contract (app-audit 2026-07-06, resume-editor #5):
//  when the render fails, `onFailure` fires and `onFinish` does NOT — so callers
//  like ExportFileService.exportResumePDF/exportResumeText can no longer fall
//  through to writing the previous (stale) pdfData/textResume under a success
//  toast. Before the fix, `onFinish` ran in a `defer` and fired even after a
//  failed render.
//
//  The failure here is deterministic and UI-free: the resume has no template and
//  the TemplateStore is empty, so ResumeExportService.ensureTemplate throws
//  `.noTemplatesConfigured` before any PDF work starts.
//

import XCTest
import SwiftData
@testable import Sprung

@MainActor
final class ResumeExportCoordinatorCallbackTests: InMemoryStoreCase {

    func testOnFinishSkippedAndOnFailureFiredWhenRenderFails() async throws {
        let templateStore = TemplateStore(context: context)
        let applicantProfileStore = ApplicantProfileStore(context: context)
        let exportService = ResumeExportService(
            templateStore: templateStore,
            applicantProfileStore: applicantProfileStore
        )
        let coordinator = ResumeExportCoordinator(exportService: exportService, debounceInterval: 0)

        let job = JobApp(jobPosition: "P")
        insert(job)
        let resume = Resume(jobApp: job, enabledSources: [])
        insert(resume)
        job.addResume(resume)
        saveContext()

        let failed = expectation(description: "onFailure fires on render failure")
        coordinator.debounceExport(
            resume: resume,
            onFinish: { XCTFail("onFinish must not fire when the render fails") },
            onFailure: { error in
                XCTAssertTrue(error is ResumeExportError, "expected the deterministic noTemplatesConfigured failure, got \(error)")
                failed.fulfill()
            }
        )
        await fulfillment(of: [failed], timeout: 5)
        XCTAssertFalse(coordinator.isExporting(resume), "exporting flag must clear after a failed render")
    }
}
