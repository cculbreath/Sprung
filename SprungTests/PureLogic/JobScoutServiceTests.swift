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
            today: Date()
        )
        XCTAssertFalse(message.contains("## GUIDANCE FROM THE USER"))
        XCTAssertFalse(message.contains("## CANDIDATE KNOWLEDGE CARDS"))
        XCTAssertFalse(message.contains("## CANDIDATE DOSSIER"))
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
            url: "https://a", title: "T", company: "C", reasoning: "R", match: matchFixture(), imported: true
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
                       ["dice", "zipRecruiter", "linkedIn"])
        XCTAssertEqual(JobScoutService.ScoutBoard.dice.displayName, "Dice")
        XCTAssertEqual(JobScoutService.ScoutBoard.zipRecruiter.displayName, "ZipRecruiter")
        XCTAssertEqual(JobScoutService.ScoutBoard.linkedIn.displayName, "LinkedIn")
    }
}
