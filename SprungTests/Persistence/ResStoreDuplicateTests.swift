//
//  ResStoreDuplicateTests.swift
//  SprungTests
//
//  Pins the ResStore.duplicate copy contract (app-audit 2026-07-06, resume-editor #4):
//  duplicating a resume must carry `sectionVisibilityOverrides` — the Styling-drawer
//  section toggles consumed at render via ResumeDetailVM.sectionVisibilityValue —
//  alongside the other per-resume settings (keyLabels, importedEditorKeys).
//  Before the fix, the copy silently rendered hidden sections back on.
//

import XCTest
import SwiftData
@testable import Sprung

@MainActor
final class ResStoreDuplicateTests: InMemoryStoreCase {

    /// Builds a ResStore bound to the test context (mirrors the store chain
    /// in DependentStoresTests / JobAppDedupTests).
    private func makeResStore() -> ResStore {
        let templateStore = TemplateStore(context: context)
        let applicantProfileStore = ApplicantProfileStore(context: context)
        let experienceDefaultsStore = ExperienceDefaultsStore(context: context)
        let exportService = ResumeExportService(
            templateStore: templateStore,
            applicantProfileStore: applicantProfileStore
        )
        let exportCoordinator = ResumeExportCoordinator(exportService: exportService)
        return ResStore(
            context: context,
            exportCoordinator: exportCoordinator,
            experienceDefaultsStore: experienceDefaultsStore
        )
    }

    func testDuplicateCarriesSectionVisibilityOverrides() async throws {
        let resStore = makeResStore()
        let job = JobApp(jobPosition: "Optical Engineer")
        insert(job)
        let original = Resume(jobApp: job)
        insert(original)
        job.addResume(original)
        original.sectionVisibilityOverrides = ["projects": false, "volunteer": true]
        original.keyLabels = ["work": "Employment"]
        original.importedEditorKeys = ["custom.objective"]
        saveContext()

        let copy = try XCTUnwrap(resStore.duplicate(original))
        // Pre-empt the duplicate's fire-and-forget re-render before yielding the
        // main actor: ensureFreshRenderedText short-circuits on non-empty textResume,
        // so the async task settles without touching the (template-less) render path.
        copy.textResume = "rendered"

        XCTAssertEqual(
            copy.sectionVisibilityOverrides,
            ["projects": false, "volunteer": true],
            "duplicate must carry section-visibility overrides"
        )
        XCTAssertEqual(copy.keyLabels, ["work": "Employment"])
        XCTAssertEqual(copy.importedEditorKeys, ["custom.objective"])
        XCTAssertNotEqual(copy.id, original.id)

        // Let the fire-and-forget render task run (and early-return) before the
        // in-memory container is torn down.
        await Task.yield()
        await Task.yield()
    }
}
