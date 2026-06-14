//
//  ModelBusinessLogicTests.swift
//  SprungTests
//
//  Phase 3: SwiftData persistence — @Model business logic, relationships, and
//  cascade behavior, plus pure-struct decode rules (ExtractedRequirements).
//

import XCTest
import SwiftData
@testable import Sprung

@MainActor
final class ModelBusinessLogicTests: InMemoryStoreCase {

    // MARK: - JobApp relationships & selection

    /// Creates and inserts a job app with `count` resumes attached.
    @discardableResult
    private func insertJob(
        position: String = "Engineer",
        resumeCount: Int = 0
    ) -> JobApp {
        let job = JobApp(jobPosition: position, companyName: "Acme")
        insert(job)
        for _ in 0..<resumeCount {
            let resume = Resume(jobApp: job, enabledSources: [])
            insert(resume)
            job.resumes.append(resume)
        }
        saveContext()
        return job
    }

    func testSelectedResDefaultsToLastWhenUnset() throws {
        let job = insertJob(resumeCount: 2)
        // No explicit selectedResId — getter returns the last resume.
        XCTAssertNotNil(job.selectedRes)
        XCTAssertEqual(job.selectedRes?.persistentModelID, job.resumes.last?.persistentModelID)
    }

    func testSelectedResHonorsExplicitId() throws {
        let job = insertJob(resumeCount: 3)
        let target = job.resumes[1]
        job.selectedRes = target
        saveContext()
        XCTAssertEqual(job.selectedResId, target.id)
        XCTAssertEqual(job.selectedRes?.persistentModelID, target.persistentModelID)
    }

    func testSelectedCoverFallsBackToRelationshipAndHonorsExplicitSelection() throws {
        let job = insertJob()
        let a = CoverLetter(enabledRefs: [], jobApp: job)
        let b = CoverLetter(enabledRefs: [], jobApp: job)
        insert(a)
        insert(b)
        job.coverLetters.append(contentsOf: [a, b])
        saveContext()

        // With no explicit selection the getter falls back to `coverLetters.last`.
        // SwiftData to-many relationships are unordered, so we can only assert it
        // returns *some* member of the relationship — not a specific insertion order.
        let fallback = try XCTUnwrap(job.selectedCover)
        XCTAssertTrue(job.coverLetters.contains(where: { $0.id == fallback.id }),
                      "unset selection must resolve to a member of coverLetters")

        // Explicit selection is the deterministic contract.
        job.selectedCover = a
        XCTAssertEqual(job.selectedCover?.persistentModelID, a.persistentModelID)
    }

    func testAddResumeRecordsResumeAndSelectsIt() throws {
        let job = JobApp(jobPosition: "P")
        insert(job)
        XCTAssertEqual(job.status, .new)

        let resume = Resume(jobApp: job, enabledSources: [])
        insert(resume)
        job.addResume(resume)
        saveContext()

        // `Resume(jobApp:)` already links the inverse, so `addResume`'s uniqueness
        // guard short-circuits the status-advance branch (it only fires for a resume
        // not yet in `resumes`). The deterministic, observable outcome is that the job
        // now has a resume and it is selected.
        XCTAssertTrue(job.hasAnyRes)
        XCTAssertEqual(job.selectedRes?.persistentModelID, resume.persistentModelID)
    }

    func testDeletingJobAppCascadesToResumes() throws {
        let job = insertJob(resumeCount: 2)
        XCTAssertEqual(try fetchAll(Resume.self).count, 2)

        context.delete(job)
        saveContext()

        XCTAssertEqual(try fetchAll(JobApp.self).count, 0)
        XCTAssertEqual(try fetchAll(Resume.self).count, 0, "cascade delete must remove child resumes")
    }

    func testDeletingJobAppCascadesToCoverLetters() throws {
        let job = insertJob()
        let letter = CoverLetter(enabledRefs: [], jobApp: job)
        insert(letter)
        job.coverLetters.append(letter)
        saveContext()
        XCTAssertEqual(try fetchAll(CoverLetter.self).count, 1)

        context.delete(job)
        saveContext()
        XCTAssertEqual(try fetchAll(CoverLetter.self).count, 0, "cascade delete must remove child cover letters")
    }

    func testResumeDeletePrepReassignsSelection() throws {
        let job = insertJob(resumeCount: 2)
        let first = job.resumes[0]
        let second = job.resumes[1]
        job.selectedRes = second

        job.resumeDeletePrep(candidate: second)
        // Selection should fall to the remaining resume.
        XCTAssertEqual(job.selectedResId, first.id)
    }

    func testJobListingStringIncludesPopulatedFields() throws {
        let job = JobApp(
            jobPosition: "Staff Engineer",
            jobLocation: "Remote",
            companyName: "Acme",
            jobDescription: "Build platforms."
        )
        let listing = job.jobListingString
        XCTAssertTrue(listing.contains("Job Position: Staff Engineer"))
        XCTAssertTrue(listing.contains("Company Name: Acme"))
        XCTAssertTrue(listing.contains("Job Description: Build platforms."))
    }

    // MARK: - Statuses pipeline progression (model-level, not the enum table)

    func testStatusNextProgression() {
        XCTAssertEqual(Statuses.new.next, .queued)
        XCTAssertEqual(Statuses.queued.next, .inProgress)
        XCTAssertNil(Statuses.accepted.next)
        XCTAssertTrue(Statuses.rejected.isTerminal)
        XCTAssertFalse(Statuses.inProgress.isTerminal)
    }

    // MARK: - CoverLetter naming & selection logic

    func testCoverLetterOptionLetterExtraction() throws {
        let letter = CoverLetter(enabledRefs: [], jobApp: nil)
        letter.name = "Option B: Draft Revision"
        XCTAssertEqual(letter.optionLetter, "B")
        XCTAssertEqual(letter.editableName, "Draft Revision")
    }

    func testCoverLetterSetEditableNamePreservesPrefix() throws {
        let letter = CoverLetter(enabledRefs: [], jobApp: nil)
        letter.name = "Option C: Old"
        letter.setEditableName("New Body")
        XCTAssertEqual(letter.name, "Option C: New Body")
    }

    func testCoverLetterLetterLabelMapping() {
        XCTAssertEqual(CoverLetter.letterLabel(for: 1), "A")
        XCTAssertEqual(CoverLetter.letterLabel(for: 26), "Z")
        XCTAssertEqual(CoverLetter.letterLabel(for: 27), "AA")
        XCTAssertEqual(CoverLetter.letterLabel(for: 0), "")
    }

    func testCoverLetterSequenceNumberWithinJob() throws {
        let job = JobApp(jobPosition: "P")
        insert(job)
        let a = CoverLetter(enabledRefs: [], jobApp: job)
        a.createdDate = Date(timeIntervalSince1970: 100)
        let b = CoverLetter(enabledRefs: [], jobApp: job)
        b.createdDate = Date(timeIntervalSince1970: 200)
        insert(a)
        insert(b)
        job.coverLetters.append(contentsOf: [a, b])
        saveContext()

        XCTAssertEqual(a.sequenceNumber, 1)
        XCTAssertEqual(b.sequenceNumber, 2)
    }

    func testCoverLetterKnowledgeCardInclusionDefaultsToAll() throws {
        let letter = CoverLetter(enabledRefs: [], jobApp: nil)
        XCTAssertEqual(letter.knowledgeCardInclusion, .all)
        letter.knowledgeCardInclusion = .none
        XCTAssertEqual(letter.knowledgeCardInclusionRaw, KnowledgeCardInclusion.none.rawValue)
    }

    func testMarkAsChosenSubmissionDraftClearsOthers() throws {
        let job = JobApp(jobPosition: "P")
        insert(job)
        let a = CoverLetter(enabledRefs: [], jobApp: job)
        let b = CoverLetter(enabledRefs: [], jobApp: job)
        a.isChosenSubmissionDraft = true
        insert(a)
        insert(b)
        job.coverLetters.append(contentsOf: [a, b])
        saveContext()

        b.markAsChosenSubmissionDraft()
        XCTAssertTrue(b.isChosenSubmissionDraft)
        XCTAssertFalse(a.isChosenSubmissionDraft)
    }

    // MARK: - CoverRef voice profile accessor

    func testCoverRefVoiceProfileNilForWritingSample() throws {
        let ref = CoverRef(name: "S", content: "c", type: .writingSample, voicePrimerJSON: "{}")
        XCTAssertNil(ref.voiceProfile, "voiceProfile only resolves for .voicePrimer type")
    }

    // MARK: - CandidateDossier validation

    func testCandidateDossierIsCompleteRequiresMinimumLengths() throws {
        let dossier = CandidateDossier(
            jobSearchContext: String(repeating: "x", count: 250),
            strengthsToEmphasize: String(repeating: "s", count: 600),
            pitfallsToAvoid: String(repeating: "p", count: 600)
        )
        XCTAssertTrue(dossier.isComplete)
        XCTAssertTrue(dossier.validationErrors.isEmpty)
    }

    func testCandidateDossierIncompleteReportsErrors() throws {
        let dossier = CandidateDossier(jobSearchContext: "too short")
        XCTAssertFalse(dossier.isComplete)
        XCTAssertFalse(dossier.validationErrors.isEmpty)
    }

    func testCandidateDossierExportForCoverLetterExcludesPrivateFields() throws {
        let dossier = CandidateDossier(
            jobSearchContext: "Context here",
            strengthsToEmphasize: "My strengths",
            uniqueCircumstances: "Visa needed",
            interviewerNotes: "Private notes"
        )
        let export = dossier.exportForCoverLetter()
        XCTAssertTrue(export.contains("Context here"))
        XCTAssertTrue(export.contains("My strengths"))
        XCTAssertFalse(export.contains("Visa needed"))
        XCTAssertFalse(export.contains("Private notes"))
    }

    // MARK: - ExtractedRequirements decode rules

    func testExtractedRequirementsIsValid() {
        let valid = ExtractedRequirements(
            mustHave: ["Swift"], strongSignal: [], preferred: [], cultural: [],
            atsKeywords: [], extractedAt: Date(), extractionModel: nil
        )
        XCTAssertTrue(valid.isValid)

        let invalid = ExtractedRequirements(
            mustHave: [], strongSignal: [], preferred: ["nice"], cultural: [],
            atsKeywords: [], extractedAt: Date(), extractionModel: nil
        )
        XCTAssertFalse(invalid.isValid)
    }

    func testExtractedRequirementsDecodesLegacyJSONMissingOptionalFields() throws {
        // Older payloads predate skillRecommendations / skillEvidence / matchedSkillIds.
        let legacyJSON = """
        {
            "mustHave": ["Swift"],
            "strongSignal": ["Concurrency"],
            "preferred": [],
            "cultural": [],
            "atsKeywords": ["swift"],
            "extractedAt": 700000000,
            "extractionModel": "legacy"
        }
        """
        let data = Data(legacyJSON.utf8)
        let decoded = try JSONDecoder().decode(ExtractedRequirements.self, from: data)
        XCTAssertEqual(decoded.mustHave, ["Swift"])
        XCTAssertTrue(decoded.matchedSkillIds.isEmpty)
        XCTAssertTrue(decoded.skillRecommendations.isEmpty)
        XCTAssertTrue(decoded.skillEvidence.isEmpty)
        XCTAssertTrue(decoded.isValid)
    }

    func testExtractedRequirementsFullRoundTrip() throws {
        let original = ExtractedRequirements(
            mustHave: ["A"], strongSignal: ["B"], preferred: ["C"], cultural: ["D"],
            atsKeywords: ["e"], extractedAt: Date(timeIntervalSince1970: 1_000_000),
            extractionModel: "m",
            matchedSkillIds: ["s1"],
            skillRecommendations: [
                SkillRecommendation(
                    skillName: "Flame Cutting", category: "Fabrication",
                    confidence: "high", reason: "adjacent", relatedUserSkills: ["Welding"],
                    sourceCardIds: ["c1"]
                )
            ],
            skillEvidence: [
                JobSkillEvidence(
                    skillName: "Welding", category: .matched,
                    evidenceSpans: [TextSpan(start: 0, end: 7, text: "Welding")],
                    matchedSkillId: "s1"
                )
            ]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ExtractedRequirements.self, from: data)
        XCTAssertEqual(decoded.skillRecommendations.count, 1)
        XCTAssertEqual(decoded.skillRecommendations.first?.skillName, "Flame Cutting")
        XCTAssertEqual(decoded.skillEvidence.first?.category, .matched)
        XCTAssertEqual(decoded.skillEvidence.first?.evidenceSpans.first?.text, "Welding")
    }
}
