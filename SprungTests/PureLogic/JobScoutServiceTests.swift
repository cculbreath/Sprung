//
//  JobScoutServiceTests.swift
//  SprungTests
//
//  Pure halves of the Job Scout engine (JobScoutService), no LLMFacade and no
//  store needed:
//
//  1. Consent gate: LinkedIn without the accepted one-time risk consent is
//     dropped from the run's boards with a note — never bypassed.
//  2. ScoutRunConfig → per-board search-argument mapping: search_board args
//     onto Dice / ZipRecruiter queries (and their external snake_case tool
//     arguments) and the camelCase datePosted → LinkedIn facet map.
//  3. Board DTO → compact ScoutSearchResult mapping per board.
//  4. The run-local dedup seam: cross-board seen-URL filtering plus the
//     per-board pipeline-match rules (linkedIn = URL-match only; zipRecruiter
//     = title+company with url passed nil; dice = either).
//  5. Recommendation → JobApp lead mapping (source "Scout", priority .high).
//  6. Task-message assembly and report building (JobScoutRunState).
//

import XCTest
import SwiftOpenAI
@testable import Sprung

@MainActor
final class JobScoutServiceTests: XCTestCase {

    // MARK: - 1. Consent gate

    func testConsentGateDropsLinkedInWithoutConsent() {
        let (boards, note) = JobScoutService.boardsAfterConsentGate(
            [.dice, .zipRecruiter, .linkedIn],
            linkedInConsentAccepted: false
        )
        XCTAssertEqual(boards, [.dice, .zipRecruiter])
        XCTAssertNotNil(note, "the drop must surface in the report notes")
        XCTAssertTrue(note?.contains("LinkedIn") == true)
    }

    func testConsentGateKeepsLinkedInWithConsent() {
        let (boards, note) = JobScoutService.boardsAfterConsentGate(
            [.dice, .linkedIn],
            linkedInConsentAccepted: true
        )
        XCTAssertEqual(boards, [.dice, .linkedIn])
        XCTAssertNil(note)
    }

    func testConsentGateIgnoresConsentWhenLinkedInNotRequested() {
        let (boards, note) = JobScoutService.boardsAfterConsentGate(
            [.dice, .zipRecruiter],
            linkedInConsentAccepted: false
        )
        XCTAssertEqual(boards, [.dice, .zipRecruiter])
        XCTAssertNil(note, "no note when nothing was dropped")
    }

    // MARK: - 2. Search-argument mapping per board

    func testDiceQueryMapsKeywordsAndLocation() {
        let query = JobScoutService.diceQuery(keywords: "medical physicist", location: "Austin, TX")
        let arguments = query.toolArguments
        XCTAssertEqual(arguments["keyword"] as? String, "medical physicist")
        XCTAssertEqual(arguments["location"] as? String, "Austin, TX")
    }

    func testDiceQueryOmitsLocationWhenNull() {
        let arguments = JobScoutService.diceQuery(keywords: "physicist", location: nil).toolArguments
        XCTAssertNil(arguments["location"], "a null location must not become an empty-string facet")
    }

    func testZipRecruiterQueryMapsKeywordsAndLocation() {
        let query = JobScoutService.zipRecruiterQuery(keywords: "radiation physicist", location: "Dallas, TX")
        let arguments = query.toolArguments
        XCTAssertEqual(arguments["job_role"] as? String, "radiation physicist")
        XCTAssertEqual(arguments["location"] as? String, "Dallas, TX")
    }

    func testZipRecruiterQueryOmitsLocationWhenNull() {
        let arguments = JobScoutService.zipRecruiterQuery(keywords: "physicist", location: nil).toolArguments
        XCTAssertNil(arguments["location"])
    }

    func testLinkedInDatePostedMapsCamelCaseValues() {
        XCTAssertEqual(JobScoutService.linkedInDatePosted(from: "pastHour"), .pastHour)
        XCTAssertEqual(JobScoutService.linkedInDatePosted(from: "past24Hours"), .past24Hours)
        XCTAssertEqual(JobScoutService.linkedInDatePosted(from: "pastWeek"), .pastWeek)
        XCTAssertEqual(JobScoutService.linkedInDatePosted(from: "pastMonth"), .pastMonth)
    }

    func testLinkedInDatePostedUnknownOrNilMeansNoFilter() {
        XCTAssertNil(JobScoutService.linkedInDatePosted(from: nil))
        XCTAssertNil(JobScoutService.linkedInDatePosted(from: "past_week"),
                     "the snake_case wire value is NOT a tool value — the map is camelCase only")
        XCTAssertNil(JobScoutService.linkedInDatePosted(from: "yesterday"))
    }

    // MARK: - 3. Board DTO → ScoutSearchResult

    func testDiceResultMapsToCompactResult() throws {
        let json = """
        {
          "id": "1",
          "title": "Senior Medical Physicist",
          "summary": "Commission and QA linear accelerators.",
          "postedDate": "2026-06-01T00:00:00.000Z",
          "jobLocation": { "displayName": "Austin, TX" },
          "detailsPageUrl": "https://www.dice.com/job-detail/abc-123?utm_source=partner",
          "salary": "$180,000",
          "companyName": "Acme Oncology"
        }
        """
        let dice = try JSONDecoder().decode(DiceJobResult.self, from: Data(json.utf8))
        let result = try XCTUnwrap(JobScoutService.scoutResult(from: dice))
        XCTAssertEqual(result.title, "Senior Medical Physicist")
        XCTAssertEqual(result.company, "Acme Oncology")
        XCTAssertEqual(result.location, "Austin, TX")
        XCTAssertEqual(result.url, "https://www.dice.com/job-detail/abc-123",
                       "utm noise stripped — the stable identity the pipeline dedups on")
        XCTAssertEqual(result.snippet, "Commission and QA linear accelerators.")
        XCTAssertEqual(result.salary, "$180,000")
    }

    func testDiceResultWithoutEssentialsDropped() throws {
        let json = #"{"id": "2", "summary": "No title or URL."}"#
        let dice = try JSONDecoder().decode(DiceJobResult.self, from: Data(json.utf8))
        XCTAssertNil(JobScoutService.scoutResult(from: dice))
    }

    func testZipRecruiterResultMapsSalaryAndRemoteLocation() throws {
        let json = """
        {
          "title": "Physicist",
          "company": "Beta Health",
          "location": "Dallas, TX",
          "is_remote": true,
          "salary": { "min_annual": 150000, "max_annual": 190000 },
          "job_redirect_url": "https://www.ziprecruiter.com/k/t/AAAA"
        }
        """
        let zip = try JSONDecoder().decode(JobMCPImportService.ZipRecruiterJobResult.self, from: Data(json.utf8))
        let result = try XCTUnwrap(JobScoutService.scoutResult(from: zip))
        XCTAssertEqual(result.title, "Physicist")
        XCTAssertEqual(result.company, "Beta Health")
        XCTAssertEqual(result.location, "Dallas, TX (Remote)")
        XCTAssertEqual(result.url, "https://www.ziprecruiter.com/k/t/AAAA")
        XCTAssertNil(result.snippet, "ZipRecruiter results carry no description")
        XCTAssertEqual(result.salary, "$150,000 – $190,000")
    }

    func testLinkedInLeadMapsTitleAndCanonicalURLOnly() {
        let lead = LinkedInJobLead(
            jobID: "4242",
            title: "Staff Physicist",
            canonicalURL: "https://www.linkedin.com/jobs/view/4242/"
        )
        let result = JobScoutService.scoutResult(from: lead)
        XCTAssertEqual(result.title, "Staff Physicist")
        XCTAssertEqual(result.url, "https://www.linkedin.com/jobs/view/4242/")
        XCTAssertNil(result.company, "company is unknown at LinkedIn search time — never guessed")
        XCTAssertNil(result.snippet)
    }

    // MARK: - 4. Run-local dedup seam

    private func result(url: String, title: String = "Physicist", company: String? = "Acme") -> JobScoutService.ScoutSearchResult {
        JobScoutService.ScoutSearchResult(
            title: title, company: company, location: nil,
            url: url, snippet: nil, salary: nil, postedDate: nil
        )
    }

    private func dismissedPosting(
        url: String,
        title: String = "Physicist",
        company: String = "Acme",
        reason: String? = nil
    ) -> JobScoutService.ScoutDismissedPosting {
        JobScoutService.ScoutDismissedPosting(
            url: url, title: title, company: company,
            dismissedAt: Date(timeIntervalSince1970: 1_780_000_000), reason: reason
        )
    }

    func testDedupDropsURLsAlreadySeenThisRunAcrossBoards() {
        var seen: Set<String> = ["https://example.com/job/1"]
        let (kept, dropped, dismissedDropped) = JobScoutService.dedupSearchResults(
            [result(url: "https://example.com/job/1"), result(url: "https://example.com/job/2")],
            board: .dice,
            seenURLs: &seen,
            dismissed: []
        ) { _, _, _ in nil }
        XCTAssertEqual(kept.map(\.url), ["https://example.com/job/2"])
        XCTAssertEqual(dropped, 1)
        XCTAssertEqual(dismissedDropped, 0)
        XCTAssertTrue(seen.contains("https://example.com/job/2"),
                      "kept URLs join the cross-board seen set")
    }

    func testDedupDropsWithinBatchRepeats() {
        var seen: Set<String> = []
        let (kept, dropped, _) = JobScoutService.dedupSearchResults(
            [result(url: "https://example.com/job/1"), result(url: "https://example.com/job/1")],
            board: .dice,
            seenURLs: &seen,
            dismissed: []
        ) { _, _, _ in nil }
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(dropped, 1)
    }

    func testDedupDiceDropsOnEitherPipelineMatchKind() {
        var seen: Set<String> = []
        var matchKinds: [JobScoutService.PipelineMatchKind?] = [.byURL, .byTitleCompany, nil]
        let (kept, dropped, _) = JobScoutService.dedupSearchResults(
            [result(url: "https://a"), result(url: "https://b"), result(url: "https://c")],
            board: .dice,
            seenURLs: &seen,
            dismissed: []
        ) { _, _, _ in matchKinds.removeFirst() }
        XCTAssertEqual(kept.map(\.url), ["https://c"])
        XCTAssertEqual(dropped, 2)
    }

    func testDedupLinkedInIgnoresTitleCompanyMatches() {
        // LinkedIn results carry no company; a title+empty-company fallback
        // hit would false-match unrelated postings, so only URL matches count.
        var seen: Set<String> = []
        var matchKinds: [JobScoutService.PipelineMatchKind?] = [.byTitleCompany, .byURL]
        let (kept, dropped, _) = JobScoutService.dedupSearchResults(
            [
                result(url: "https://www.linkedin.com/jobs/view/1/", company: nil),
                result(url: "https://www.linkedin.com/jobs/view/2/", company: nil)
            ],
            board: .linkedIn,
            seenURLs: &seen,
            dismissed: []
        ) { _, _, _ in matchKinds.removeFirst() }
        XCTAssertEqual(kept.map(\.url), ["https://www.linkedin.com/jobs/view/1/"])
        XCTAssertEqual(dropped, 1)
    }

    func testDedupZipRecruiterPassesNilURLToPipelineLookup() {
        // ZipRecruiter redirect tokens are unstable — never a pipeline dedup
        // key. The lookup must receive nil so it falls to title+company only.
        var seen: Set<String> = []
        var receivedURLs: [String?] = []
        _ = JobScoutService.dedupSearchResults(
            [result(url: "https://www.ziprecruiter.com/k/t/AAAA")],
            board: .zipRecruiter,
            seenURLs: &seen,
            dismissed: []
        ) { url, _, _ in
            receivedURLs.append(url)
            return .byTitleCompany
        }
        XCTAssertEqual(receivedURLs, [nil])
    }

    func testDedupDiceAndLinkedInPassResultURLToPipelineLookup() {
        var seen: Set<String> = []
        var receivedURLs: [String?] = []
        _ = JobScoutService.dedupSearchResults(
            [result(url: "https://www.dice.com/job-detail/abc")],
            board: .dice,
            seenURLs: &seen,
            dismissed: []
        ) { url, _, _ in
            receivedURLs.append(url)
            return nil
        }
        XCTAssertEqual(receivedURLs, ["https://www.dice.com/job-detail/abc"])
    }

    // MARK: - 4b. Cross-run dismissed memory

    func testIsDismissedMatchesByURL() {
        let dismissed = [dismissedPosting(url: "https://www.dice.com/job-detail/abc", title: "X", company: "Y")]
        XCTAssertTrue(JobScoutService.isDismissed(
            result(url: "https://www.dice.com/job-detail/abc", title: "Totally", company: "Different"),
            in: dismissed
        ), "a URL match dismisses regardless of title/company drift")
    }

    func testIsDismissedMatchesByTitleCompanyCaseInsensitive() {
        // Same posting, unstable URL (ZipRecruiter redirect) — the title+company
        // arm must still recognize it.
        let dismissed = [dismissedPosting(url: "https://www.ziprecruiter.com/k/t/OLD", title: "Medical Physicist", company: "Acme Oncology")]
        XCTAssertTrue(JobScoutService.isDismissed(
            result(url: "https://www.ziprecruiter.com/k/t/NEW", title: "medical physicist", company: "acme oncology"),
            in: dismissed
        ))
    }

    func testIsDismissedRequiresBothTitleAndCompanyForFallback() {
        // A dismissed LinkedIn posting stored with empty company must not
        // title-only match an unrelated posting that shares the title.
        let dismissed = [dismissedPosting(url: "https://www.linkedin.com/jobs/view/1/", title: "Physicist", company: "")]
        XCTAssertFalse(JobScoutService.isDismissed(
            result(url: "https://www.linkedin.com/jobs/view/2/", title: "Physicist", company: "Acme"),
            in: dismissed
        ), "empty company blocks the title-only fallback — never false-match unrelated postings")
        // And a result with no company can't title-match either.
        let dismissed2 = [dismissedPosting(url: "https://old", title: "Physicist", company: "Acme")]
        XCTAssertFalse(JobScoutService.isDismissed(
            result(url: "https://new", title: "Physicist", company: nil),
            in: dismissed2
        ))
    }

    func testDedupDropsDismissedPostingsSeparatelyFromPipelineDuplicates() {
        var seen: Set<String> = []
        let dismissed = [dismissedPosting(url: "https://b", title: "X", company: "Y")]
        // Only https://a and https://c reach the pipeline lookup — https://b is
        // dismissed and short-circuits before it, so it never consumes a kind.
        var matchKinds: [JobScoutService.PipelineMatchKind?] = [nil, .byURL]
        let (kept, dropped, dismissedDropped) = JobScoutService.dedupSearchResults(
            [result(url: "https://a"), result(url: "https://b"), result(url: "https://c")],
            board: .dice,
            seenURLs: &seen,
            dismissed: dismissed
        ) { _, _, _ in matchKinds.removeFirst() }
        XCTAssertEqual(kept.map(\.url), ["https://a"], "https://c is a pipeline dup, https://b was dismissed")
        XCTAssertEqual(dismissedDropped, 1)
        XCTAssertEqual(dropped, 1)
        XCTAssertEqual(matchKinds, [], "the dismissed result short-circuits before its pipeline check")
    }

    func testDedupDismissedFilterUsesTitleCompanyForZipRecruiter() {
        var seen: Set<String> = []
        let dismissed = [dismissedPosting(url: "https://old-token", title: "Physicist", company: "Acme")]
        let (kept, _, dismissedDropped) = JobScoutService.dedupSearchResults(
            [result(url: "https://new-token", title: "Physicist", company: "Acme")],
            board: .zipRecruiter,
            seenURLs: &seen,
            dismissed: dismissed
        ) { _, _, _ in nil }
        XCTAssertTrue(kept.isEmpty)
        XCTAssertEqual(dismissedDropped, 1)
    }

    // MARK: - Search tool output

    func testSearchToolOutputEncodesCamelCasePayload() throws {
        let output = JobScoutService.searchToolOutput(
            board: .dice,
            kept: [result(url: "https://www.dice.com/job-detail/abc")],
            droppedDuplicates: 3
        )
        XCTAssertFalse(output.isError)
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(output.content.utf8)) as? [String: Any]
        )
        XCTAssertEqual(payload["board"] as? String, "dice")
        XCTAssertEqual(payload["droppedDuplicates"] as? Int, 3)
        let results = try XCTUnwrap(payload["results"] as? [[String: Any]])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0]["url"] as? String, "https://www.dice.com/job-detail/abc")
        XCTAssertNil(results[0]["snippet"], "nil fields are omitted, not encoded as null noise")
    }

    // MARK: - Board failure explanation

    func testLinkedInAuthFailureUsesTheOneDoctrineString() {
        let authError = MCPClientError.toolError("AuthenticationError: Session expired or invalid")
        let explanation = JobScoutService.boardFailureExplanation(board: .linkedIn, error: authError)
        XCTAssertTrue(explanation.contains(LinkedInMCPImportService.noSessionMessage),
                      "auth failures surface as the single doctrine string, no variants")
    }

    func testOtherBoardFailuresKeepTheirOwnDescription() {
        let error = JobMCPImportError.emptyResult
        let explanation = JobScoutService.boardFailureExplanation(board: .dice, error: error)
        XCTAssertTrue(explanation.contains("Dice"))
        XCTAssertFalse(explanation.contains(LinkedInMCPImportService.noSessionMessage))
    }

    // MARK: - Match-assessment fixtures + verdict sort

    private func matchFixture(_ verdict: JobScoutMatchAssessment.Verdict = .strong) -> JobScoutMatchAssessment {
        JobScoutMatchAssessment(
            skills: .strong, seniority: .strong, locationFit: .moderate,
            compensation: .unknown, verdict: verdict
        )
    }

    private func draft(
        url: String,
        title: String = "Physicist",
        company: String = "Acme",
        reasoning: String = "fit",
        verdict: JobScoutMatchAssessment.Verdict = .strong
    ) -> JobScoutRecommendationDraft {
        JobScoutRecommendationDraft(
            url: url, title: title, company: company, reasoning: reasoning, match: matchFixture(verdict)
        )
    }

    func testSortedByVerdictOrdersStrongestFirst() {
        let sorted = JobScoutService.sortedByVerdict([
            draft(url: "https://marginal", verdict: .marginal),
            draft(url: "https://strong", verdict: .strong),
            draft(url: "https://promising", verdict: .promising)
        ])
        XCTAssertEqual(sorted.map(\.url), ["https://strong", "https://promising", "https://marginal"])
    }

    func testSortedByVerdictIsStableWithinATier() {
        // Two picks share a verdict — the agent's original order is preserved.
        let sorted = JobScoutService.sortedByVerdict([
            draft(url: "https://a", verdict: .promising),
            draft(url: "https://strong", verdict: .strong),
            draft(url: "https://b", verdict: .promising)
        ])
        XCTAssertEqual(sorted.map(\.url), ["https://strong", "https://a", "https://b"],
                       "ties keep the agent's submission order, never reshuffle")
    }

    // MARK: - Disposition + review helpers

    private func recommendation(
        url: String = "https://a",
        disposition: JobScoutService.ScoutRecommendation.Disposition = .pending
    ) -> JobScoutService.ScoutRecommendation {
        JobScoutService.ScoutRecommendation(
            url: url, title: "T", company: "C", reasoning: "R", match: matchFixture(), disposition: disposition
        )
    }

    private func reportFixture(
        startedAt: Date = Date(timeIntervalSince1970: 1_782_000_000),
        urls: [String]? = nil,
        dispositions: [JobScoutService.ScoutRecommendation.Disposition]
    ) -> JobScoutService.ScoutRunReport {
        let recs = dispositions.enumerated().map { index, disposition in
            recommendation(url: urls?[index] ?? "https://\(index)", disposition: disposition)
        }
        return JobScoutService.ScoutRunReport(
            startedAt: startedAt, boardsSearched: ["Dice"], resultsFound: 10,
            duplicatesDropped: 0, previouslyDismissedDropped: 0, recommendations: recs, notes: []
        )
    }

    func testInitialDispositionDuplicateIsAlreadyInPipeline() {
        XCTAssertEqual(
            JobScoutService.initialDisposition(isDuplicate: true, verdict: .strong, autoImportStrong: true),
            .alreadyInPipeline,
            "a duplicate is never re-imported, not even a strong one with auto-import on"
        )
    }

    func testInitialDispositionAutoImportsStrongOnlyWhenEnabled() {
        XCTAssertEqual(
            JobScoutService.initialDisposition(isDuplicate: false, verdict: .strong, autoImportStrong: true),
            .imported
        )
        XCTAssertEqual(
            JobScoutService.initialDisposition(isDuplicate: false, verdict: .strong, autoImportStrong: false),
            .pending,
            "curation is the default — a strong match still waits when auto-import is off"
        )
    }

    func testInitialDispositionNonStrongVerdictsStayPending() {
        for verdict in [JobScoutMatchAssessment.Verdict.promising, .marginal] {
            XCTAssertEqual(
                JobScoutService.initialDisposition(isDuplicate: false, verdict: verdict, autoImportStrong: true),
                .pending,
                "auto-import only ever brings in a strong verdict, never promising/marginal"
            )
        }
    }

    func testPendingCountCountsOnlyPending() {
        let report = reportFixture(dispositions: [.pending, .imported, .pending, .dismissed, .alreadyInPipeline])
        XCTAssertEqual(JobScoutService.pendingCount(in: report), 2)
        XCTAssertEqual(JobScoutService.pendingCount(in: nil), 0)
    }

    func testSettingDispositionUpdatesTheMatchingRecommendation() {
        let started = Date(timeIntervalSince1970: 1_782_000_000)
        let report = reportFixture(startedAt: started, urls: ["https://a", "https://b"], dispositions: [.pending, .pending])
        let updated = JobScoutService.settingDisposition(.imported, forURL: "https://b", runStartedAt: started, in: [report])
        XCTAssertEqual(updated[0].recommendations[0].disposition, .pending, "the other pick is untouched")
        XCTAssertEqual(updated[0].recommendations[1].disposition, .imported)
    }

    func testSettingDispositionIsANoOpWhenRunOrURLNotFound() {
        let started = Date(timeIntervalSince1970: 1_782_000_000)
        let report = reportFixture(startedAt: started, urls: ["https://a"], dispositions: [.pending])
        let unknownURL = JobScoutService.settingDisposition(.imported, forURL: "https://missing", runStartedAt: started, in: [report])
        XCTAssertEqual(unknownURL[0].recommendations[0].disposition, .pending)
        let unknownRun = JobScoutService.settingDisposition(.imported, forURL: "https://a", runStartedAt: Date(timeIntervalSince1970: 1), in: [report])
        XCTAssertEqual(unknownRun[0].recommendations[0].disposition, .pending)
    }

    // MARK: - 5. Recommendation → JobApp

    func testMakeJobAppSetsScoutSourceAndHighPriority() throws {
        let jobApp = try XCTUnwrap(JobScoutService.makeJobApp(from: draft(
            url: "https://www.dice.com/job-detail/abc",
            title: "Senior Medical Physicist",
            company: "Acme Oncology",
            reasoning: "Strong fit."
        )))
        XCTAssertEqual(jobApp.jobPosition, "Senior Medical Physicist")
        XCTAssertEqual(jobApp.companyName, "Acme Oncology")
        XCTAssertEqual(jobApp.postingURL, "https://www.dice.com/job-detail/abc")
        XCTAssertEqual(jobApp.jobApplyLink, "https://www.dice.com/job-detail/abc")
        XCTAssertEqual(jobApp.status, .new)
        XCTAssertEqual(jobApp.source, "Scout")
        XCTAssertEqual(jobApp.priority, .high)
        XCTAssertTrue(jobApp.jobDescription.isEmpty,
                      "the description arrives via background enrichment, never from the agent")
    }

    func testMakeJobAppRejectsMissingEssentials() {
        XCTAssertNil(JobScoutService.makeJobApp(from: draft(url: "https://a", title: "  ", company: "Acme")))
        XCTAssertNil(JobScoutService.makeJobApp(from: draft(url: "https://a", title: "Physicist", company: "")))
        XCTAssertNil(JobScoutService.makeJobApp(from: draft(url: "", title: "Physicist", company: "Acme")))
    }

    // MARK: - 6. Task-message assembly

    func testScoutUserMessageCarriesRunParametersAndContexts() {
        var preferences = SearchPreferences()
        preferences.preferredArrangement = .hybrid
        preferences.remoteAcceptable = true

        let message = JobScoutService.scoutUserMessage(
            boards: [.dice, .linkedIn],
            keywords: ["Medical Physicist", "Radiation Physicist"],
            location: "Austin, TX",
            preferences: preferences,
            recommendationCount: 4,
            guidance: "favor clinical roles",
            knowledgeContext: "[experience] Linac Commissioning:\nDid the work.",
            dossierContext: "Seeking senior clinical roles.",
            learnedPreferences: "",
            outcomeContext: "",
            today: Date(timeIntervalSince1970: 1_782_000_000)
        )

        XCTAssertTrue(message.contains("ENABLED BOARDS: dice, linkedIn"),
                      "boards render in stable allCases order")
        XCTAssertTrue(message.contains("ROLE KEYWORDS: Medical Physicist, Radiation Physicist"))
        XCTAssertTrue(message.contains("LOCATION: Austin, TX"))
        XCTAssertTrue(message.contains("Hybrid (remote acceptable)"))
        XCTAssertTrue(message.contains("RECOMMENDATION LIMIT: 4"))
        XCTAssertTrue(message.contains("## CANDIDATE KNOWLEDGE CARDS"))
        XCTAssertTrue(message.contains("## CANDIDATE DOSSIER"))
        XCTAssertTrue(message.contains("## GUIDANCE FROM THE USER\nfavor clinical roles"))
    }

    func testScoutUserMessageOmitsEmptyOptionalBlocks() {
        let message = JobScoutService.scoutUserMessage(
            boards: [.zipRecruiter],
            keywords: ["Physicist"],
            location: "",
            preferences: SearchPreferences(),
            recommendationCount: 5,
            guidance: "   ",
            knowledgeContext: "",
            dossierContext: "",
            learnedPreferences: "   ",
            outcomeContext: "",
            today: Date()
        )
        XCTAssertFalse(message.contains("## GUIDANCE FROM THE USER"))
        XCTAssertFalse(message.contains("## CANDIDATE KNOWLEDGE CARDS"))
        XCTAssertFalse(message.contains("## CANDIDATE DOSSIER"))
        XCTAssertFalse(message.contains("## RECENT SCOUT OUTCOMES"))
        XCTAssertFalse(message.contains("## LEARNED PREFERENCES"),
                       "a whitespace-only profile is omitted, not rendered as an empty block")
    }

    func testScoutUserMessageIncludesOutcomeBlockWhenPresent() {
        let message = JobScoutService.scoutUserMessage(
            boards: [.dice],
            keywords: ["Physicist"],
            location: "Austin, TX",
            preferences: SearchPreferences(),
            recommendationCount: 5,
            guidance: "",
            knowledgeContext: "",
            dossierContext: "",
            learnedPreferences: "",
            outcomeContext: "Applied to or advanced — the strongest signal:\n- Staff Physicist — Acme (Submitted)",
            today: Date()
        )
        XCTAssertTrue(message.contains("## RECENT SCOUT OUTCOMES"))
        XCTAssertTrue(message.contains("Staff Physicist — Acme (Submitted)"))
    }

    func testScoutUserMessageIncludesLearnedPreferencesWhenPresent() {
        let message = JobScoutService.scoutUserMessage(
            boards: [.dice],
            keywords: ["Physicist"],
            location: "Austin, TX",
            preferences: SearchPreferences(),
            recommendationCount: 5,
            guidance: "",
            knowledgeContext: "",
            dossierContext: "",
            learnedPreferences: "Pursues clinical medical-physics roles; dismisses anything requiring relocation.",
            outcomeContext: "",
            today: Date()
        )
        XCTAssertTrue(message.contains("## LEARNED PREFERENCES (distilled from your past decisions)"))
        XCTAssertTrue(message.contains("Pursues clinical medical-physics roles; dismisses anything requiring relocation."))
    }

    // MARK: - Outcome-feedback context builder

    func testOutcomeFeedbackContextOrdersTiersAndKeepsReasons() {
        let context = JobScoutService.outcomeFeedbackContext(
            appliedOrBeyond: [JobScoutService.ScoutOutcomePick(title: "Staff Physicist", company: "Acme", statusLabel: "Submitted")],
            importedPending: [JobScoutService.ScoutOutcomePick(title: "Physicist II", company: "Beta", statusLabel: nil)],
            dismissed: [dismissedPosting(url: "https://x", title: "Contract QA", company: "Gamma", reason: "contract, not permanent")]
        )
        // Applied section comes first, imported second, dismissed last.
        let appliedIndex = try? XCTUnwrap(context.range(of: "Applied to or advanced"))
        let importedIndex = try? XCTUnwrap(context.range(of: "Imported, not yet acted on"))
        let dismissedIndex = try? XCTUnwrap(context.range(of: "Dismissed"))
        XCTAssertNotNil(appliedIndex)
        XCTAssertNotNil(importedIndex)
        XCTAssertNotNil(dismissedIndex)
        if let a = appliedIndex, let i = importedIndex, let d = dismissedIndex {
            XCTAssertTrue(a.lowerBound < i.lowerBound)
            XCTAssertTrue(i.lowerBound < d.lowerBound)
        }
        XCTAssertTrue(context.contains("Staff Physicist — Acme (Submitted)"))
        XCTAssertTrue(context.contains("Physicist II — Beta"),
                      "an imported-not-acted pick carries no status suffix")
        XCTAssertFalse(context.contains("Physicist II — Beta ("), "no status parenthetical when statusLabel is nil")
        XCTAssertTrue(context.contains("Contract QA — Gamma — reason: contract, not permanent"))
    }

    func testOutcomeFeedbackContextOmitsEmptySectionsAndReturnsEmptyWhenNothing() {
        XCTAssertEqual(
            JobScoutService.outcomeFeedbackContext(appliedOrBeyond: [], importedPending: [], dismissed: []),
            "",
            "no history → empty string so the caller drops the block entirely"
        )
        let onlyDismissed = JobScoutService.outcomeFeedbackContext(
            appliedOrBeyond: [],
            importedPending: [],
            dismissed: [dismissedPosting(url: "https://x", title: "T", company: "C", reason: nil)]
        )
        XCTAssertFalse(onlyDismissed.contains("Applied to or advanced"))
        XCTAssertFalse(onlyDismissed.contains("Imported, not yet acted on"))
        XCTAssertTrue(onlyDismissed.contains("Dismissed"))
        XCTAssertTrue(onlyDismissed.contains("- T — C"), "a dismissal with no reason still lists the posting")
        XCTAssertFalse(onlyDismissed.contains("reason:"), "no reason clause when none was given")
    }

    // MARK: - Taste-profile synthesis (pure halves)

    func testTasteProfileUserMessageWithPreviousProfile() {
        let message = JobScoutService.tasteProfileUserMessage(
            previousProfile: "Pursues clinical roles.",
            outcomeSummary: "Applied to: Staff Physicist — Acme"
        )
        XCTAssertTrue(message.contains("Previous taste profile:\nPursues clinical roles."))
        XCTAssertTrue(message.contains("Applied to: Staff Physicist — Acme"))
        XCTAssertTrue(message.contains("Write the updated taste profile now."))
    }

    func testTasteProfileUserMessageWithNoPreviousProfile() {
        let message = JobScoutService.tasteProfileUserMessage(
            previousProfile: "   ",
            outcomeSummary: "Dismissed: Contract QA — Gamma"
        )
        XCTAssertTrue(message.contains("There is no previous taste profile yet."))
        XCTAssertFalse(message.contains("Previous taste profile:"))
    }

    func testParseTasteProfileExtractsAndTrimsText() throws {
        let json = """
        {"id":"msg_1","type":"message","role":"assistant","model":"claude-x",
         "content":[{"type":"text","text":"  Pursues clinical medical-physics roles.  "}],
         "stop_reason":"end_turn","stop_sequence":null,"usage":{"input_tokens":1,"output_tokens":1}}
        """
        let response = try JSONDecoder().decode(AnthropicMessageResponse.self, from: Data(json.utf8))
        XCTAssertEqual(JobScoutService.parseTasteProfile(from: response), "Pursues clinical medical-physics roles.")
    }

    func testParseTasteProfileReturnsNilForEmptyText() throws {
        let json = """
        {"id":"msg_1","type":"message","role":"assistant","model":"claude-x",
         "content":[{"type":"text","text":"   \\n  "}],
         "stop_reason":"end_turn","stop_sequence":null,"usage":{"input_tokens":1,"output_tokens":1}}
        """
        let response = try JSONDecoder().decode(AnthropicMessageResponse.self, from: Data(json.utf8))
        XCTAssertNil(JobScoutService.parseTasteProfile(from: response),
                     "an all-whitespace response yields no profile, never an empty-string overwrite")
    }

    // MARK: - Report building (JobScoutRunState)

    func testRunStateAccumulatesSearchesNotesAndBuildsReport() {
        let state = JobScoutRunState()
        state.recordSearch(board: .dice, found: 20, duplicatesDropped: 5, previouslyDismissedDropped: 3)
        state.recordSearch(board: .linkedIn, found: 10, duplicatesDropped: 2)
        state.recordSearch(board: .dice, found: 8, duplicatesDropped: 1, previouslyDismissedDropped: 1)
        state.addNote("LinkedIn call limit reached")

        let startedAt = Date(timeIntervalSince1970: 1_782_000_000)
        let recommendation = JobScoutService.ScoutRecommendation(
            url: "https://a", title: "T", company: "C", reasoning: "R", match: matchFixture(), disposition: .imported
        )
        let report = state.makeReport(startedAt: startedAt, recommendations: [recommendation])

        XCTAssertEqual(report.startedAt, startedAt)
        XCTAssertEqual(report.boardsSearched, ["Dice", "LinkedIn"],
                       "boards appear once each, in first-search order")
        XCTAssertEqual(report.resultsFound, 38)
        XCTAssertEqual(report.duplicatesDropped, 8)
        XCTAssertEqual(report.previouslyDismissedDropped, 4,
                       "dismissed drops accumulate apart from pipeline duplicates")
        XCTAssertEqual(report.recommendations.count, 1)
        XCTAssertEqual(report.notes, ["LinkedIn call limit reached"])
    }

    // MARK: - ScoutBoard contract surface

    func testScoutBoardRawValuesAndDisplayNamesAreStable() {
        XCTAssertEqual(JobScoutService.ScoutBoard.allCases.map(\.rawValue),
                       ["dice", "zipRecruiter", "linkedIn", "jsearch", "serpApi", "indeed"])
        XCTAssertEqual(JobScoutService.ScoutBoard.dice.displayName, "Dice")
        XCTAssertEqual(JobScoutService.ScoutBoard.zipRecruiter.displayName, "ZipRecruiter")
        XCTAssertEqual(JobScoutService.ScoutBoard.linkedIn.displayName, "LinkedIn")
        XCTAssertEqual(JobScoutService.ScoutBoard.jsearch.displayName, "JSearch")
        XCTAssertEqual(JobScoutService.ScoutBoard.serpApi.displayName, "SerpApi")
        XCTAssertEqual(JobScoutService.ScoutBoard.indeed.displayName, "Indeed")
    }

    func testOnlyAggregatorBoardsRequireAnAPIKey() {
        for board in [JobScoutService.ScoutBoard.jsearch, .serpApi, .indeed] {
            XCTAssertTrue(board.requiresAPIKey, "\(board.rawValue) is a BYO-key aggregator")
        }
        for board in [JobScoutService.ScoutBoard.dice, .zipRecruiter, .linkedIn] {
            XCTAssertFalse(board.requiresAPIKey, "\(board.rawValue) works without a user key")
        }
    }

    // MARK: - Aggregator key gate

    func testKeyGateDropsAggregatorsWithoutKeys() {
        let (boards, notes) = JobScoutService.boardsAfterKeyGate(
            [.dice, .jsearch, .serpApi, .indeed],
            rapidApiKeyPresent: false,
            serpApiKeyPresent: false
        )
        XCTAssertEqual(boards, [.dice])
        XCTAssertEqual(notes.count, 3, "one note per dropped aggregator")
        XCTAssertTrue(notes.contains { $0.contains("JSearch") })
        XCTAssertTrue(notes.contains { $0.contains("SerpApi") })
        XCTAssertTrue(notes.contains { $0.contains("Indeed") })
    }

    func testKeyGateSharesRapidApiKeyBetweenJSearchAndIndeed() {
        // The shared RapidAPI key gates both; SerpApi has its own key present.
        let (boards, notes) = JobScoutService.boardsAfterKeyGate(
            [.jsearch, .indeed, .serpApi],
            rapidApiKeyPresent: false,
            serpApiKeyPresent: true
        )
        XCTAssertEqual(boards, [.serpApi], "no RapidAPI key drops both JSearch and Indeed")
        XCTAssertEqual(notes.count, 2)
    }

    func testKeyGateKeepsAggregatorsWithKeys() {
        let (boards, notes) = JobScoutService.boardsAfterKeyGate(
            [.jsearch, .serpApi, .indeed],
            rapidApiKeyPresent: true,
            serpApiKeyPresent: true
        )
        XCTAssertEqual(boards, [.jsearch, .serpApi, .indeed])
        XCTAssertTrue(notes.isEmpty)
    }

    func testKeyGateIgnoresAggregatorsNotRequested() {
        let (boards, notes) = JobScoutService.boardsAfterKeyGate(
            [.dice, .zipRecruiter],
            rapidApiKeyPresent: false,
            serpApiKeyPresent: false
        )
        XCTAssertEqual(boards, [.dice, .zipRecruiter], "no key needed for boards not in the run")
        XCTAssertTrue(notes.isEmpty)
    }

    // MARK: - Aggregator DTO → ScoutSearchResult

    func testJSearchResultMapsFieldsAndRemoteLocation() throws {
        let json = """
        {
          "job_title": "Senior Medical Physicist",
          "employer_name": "Acme Oncology",
          "job_city": "Austin", "job_state": "TX", "job_country": "US",
          "job_apply_link": "https://acme.com/careers/123?utm_source=google_jobs",
          "job_description": "Commission and QA linear accelerators.",
          "job_is_remote": true,
          "job_min_salary": 150000, "job_max_salary": 190000, "job_salary_period": "YEAR",
          "job_posted_at_datetime_utc": "2026-06-01T00:00:00.000Z"
        }
        """
        let result = try JSONDecoder().decode(JSearchJobResult.self, from: Data(json.utf8))
        let scout = try XCTUnwrap(JobScoutService.scoutResult(from: result))
        XCTAssertEqual(scout.title, "Senior Medical Physicist")
        XCTAssertEqual(scout.company, "Acme Oncology")
        XCTAssertEqual(scout.location, "Austin, TX (Remote)")
        XCTAssertEqual(scout.url, "https://acme.com/careers/123",
                       "utm noise stripped for stable dedup identity")
        XCTAssertEqual(scout.snippet, "Commission and QA linear accelerators.")
        XCTAssertEqual(scout.salary, "$150,000 – $190,000/year")
    }

    func testJSearchResultWithoutEssentialsDropped() throws {
        let json = #"{"job_title": "Physicist"}"#   // no apply link
        let result = try JSONDecoder().decode(JSearchJobResult.self, from: Data(json.utf8))
        XCTAssertNil(JobScoutService.scoutResult(from: result))
    }

    func testSerpApiResultUsesFirstApplyLinkAndDetectedExtensions() throws {
        let json = """
        {
          "title": "Radiation Physicist",
          "company_name": "Beta Health",
          "location": "Dallas, TX",
          "description": "Clinical QA role.",
          "apply_options": [
            {"title": "LinkedIn", "link": "https://www.linkedin.com/jobs/view/999/"},
            {"title": "Indeed", "link": "https://indeed.com/viewjob?jk=abc"}
          ],
          "share_link": "https://www.google.com/search?q=share",
          "detected_extensions": {"posted_at": "3 days ago", "work_from_home": false, "salary": "$160K–$200K a year"}
        }
        """
        let result = try JSONDecoder().decode(SerpApiJobResult.self, from: Data(json.utf8))
        let scout = try XCTUnwrap(JobScoutService.scoutResult(from: result))
        XCTAssertEqual(scout.title, "Radiation Physicist")
        XCTAssertEqual(scout.company, "Beta Health")
        XCTAssertEqual(scout.location, "Dallas, TX")
        XCTAssertEqual(scout.url, "https://www.linkedin.com/jobs/view/999/",
                       "the first apply link wins over the share link")
        XCTAssertEqual(scout.snippet, "Clinical QA role.")
        XCTAssertEqual(scout.salary, "$160K–$200K a year")
        XCTAssertEqual(scout.postedDate, "3 days ago")
    }

    func testSerpApiResultFallsBackToShareLinkAndDropsWhenNoURL() throws {
        // No apply_options → share_link is the URL.
        let withShare = try JSONDecoder().decode(SerpApiJobResult.self, from: Data("""
        {"title": "Physicist", "company_name": "Gamma", "share_link": "https://share.example/x"}
        """.utf8))
        XCTAssertEqual(JobScoutService.scoutResult(from: withShare)?.url, "https://share.example/x")

        // No links at all → dropped.
        let noURL = try JSONDecoder().decode(SerpApiJobResult.self, from: Data(
            #"{"title": "Physicist", "company_name": "Gamma"}"#.utf8))
        XCTAssertNil(JobScoutService.scoutResult(from: noURL))
    }

    func testAggregatorSalaryFormatting() {
        XCTAssertEqual(JobScoutService.aggregatorSalary(min: 150000, max: 190000, period: "YEAR"), "$150,000 – $190,000/year")
        XCTAssertEqual(JobScoutService.aggregatorSalary(min: 120000, max: nil, period: nil), "From $120,000")
        XCTAssertEqual(JobScoutService.aggregatorSalary(min: nil, max: 90000, period: "hour"), "Up to $90,000/hour")
        XCTAssertNil(JobScoutService.aggregatorSalary(min: nil, max: nil, period: "YEAR"))
    }

    func testIndeedResultMapsNestedCompanyLocationAndDescription() throws {
        let json = """
        {
          "title": "Java Software Engineer III",
          "company": {"name": "Lockheed Martin", "image": "https://logo", "addresses": ["Bethesda, MD"]},
          "location": {"country": "United States", "countryCode": "US", "location": "King of Prussia, PA"},
          "applyUrl": "https://click.appcast.io/t/abc?utm_source=x",
          "description": "Job ID: 691465BR. Design spacecraft software.",
          "id": "56a1b7550fa78bba"
        }
        """
        let result = try JSONDecoder().decode(IndeedJobResult.self, from: Data(json.utf8))
        let scout = try XCTUnwrap(JobScoutService.scoutResult(from: result))
        XCTAssertEqual(scout.title, "Java Software Engineer III")
        XCTAssertEqual(scout.company, "Lockheed Martin", "company comes from the nested company.name")
        XCTAssertEqual(scout.location, "King of Prussia, PA", "location from the nested location.location")
        XCTAssertEqual(scout.url, "https://click.appcast.io/t/abc", "tracking params stripped")
        XCTAssertEqual(scout.snippet, "Job ID: 691465BR. Design spacecraft software.")
        XCTAssertNil(scout.salary, "Indeed search carries no reliable salary")
        XCTAssertNil(scout.postedDate, "the API's date timestamps are unusable — omitted")
    }

    func testIndeedResultWithoutURLOrTitleDropped() throws {
        let noURL = try JSONDecoder().decode(IndeedJobResult.self, from: Data(
            #"{"title": "Engineer", "company": {"name": "Acme"}}"#.utf8))
        XCTAssertNil(JobScoutService.scoutResult(from: noURL))
        let noTitle = try JSONDecoder().decode(IndeedJobResult.self, from: Data(
            #"{"applyUrl": "https://a/1", "company": {"name": "Acme"}}"#.utf8))
        XCTAssertNil(JobScoutService.scoutResult(from: noTitle))
    }
}
