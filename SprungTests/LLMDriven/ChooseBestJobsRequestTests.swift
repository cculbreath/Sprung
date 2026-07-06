//
//  ChooseBestJobsRequestTests.swift
//  SprungTests
//
//  Request-build pure half of the unified Choose Best Jobs selection call
//  (`DiscoveryAgentService.chooseBestJobsUserMessage`). Both consumers — the
//  Choose Best Jobs UI flow (toolbar + pipeline header) and the coaching
//  `choose_best_jobs` tool — funnel through this one builder on the Discovery
//  Anthropic model. The response half is covered by
//  DiscoveryResponseParserTests (parseJobSelections extraction shapes) and
//  DiscoveryPureLogicTests (JobSelection/JobSelectionsResult DTO decode).
//

import XCTest
@testable import Sprung

@MainActor
final class ChooseBestJobsRequestTests: XCTestCase {

    func testUserMessageCarriesCountAndContextSections() {
        let message = DiscoveryAgentService.chooseBestJobsUserMessage(
            jobs: [],
            knowledgeContext: "KNOWLEDGE-BLOCK",
            dossierContext: "DOSSIER-BLOCK",
            count: 3
        )

        XCTAssertTrue(message.hasPrefix("Please select the top 3 jobs"),
                      "requested selection count leads the task message")
        XCTAssertTrue(message.contains("## CANDIDATE KNOWLEDGE CARDS\nKNOWLEDGE-BLOCK"),
                      "knowledge context lands under its section header")
        XCTAssertTrue(message.contains("## CANDIDATE DOSSIER\nDOSSIER-BLOCK"),
                      "dossier context lands under its section header")
        XCTAssertTrue(message.contains("## JOB OPPORTUNITIES"),
                      "job list section is always present, even when empty")
    }

    func testUserMessageListsEveryJobWithItsUUID() {
        let first = UUID()
        let second = UUID()
        let message = DiscoveryAgentService.chooseBestJobsUserMessage(
            jobs: [
                (id: first, company: "Globex", role: "Platform Engineer", description: "Infra role"),
                (id: second, company: "Initech", role: "SRE", description: "On-call heavy")
            ],
            knowledgeContext: "",
            dossierContext: "",
            count: 5
        )

        // The model echoes these UUIDs back as `jobId` — that round-trip is
        // how selections are matched to JobApp records, so every job must be
        // listed with its uppercase uuidString.
        XCTAssertTrue(message.contains("ID: \(first.uuidString)"))
        XCTAssertTrue(message.contains("ID: \(second.uuidString)"))
        XCTAssertTrue(message.contains("Company: Globex"))
        XCTAssertTrue(message.contains("Role: Platform Engineer"))
        XCTAssertTrue(message.contains("Description: Infra role"))
        XCTAssertTrue(message.contains("Company: Initech"))
        XCTAssertTrue(message.contains("Role: SRE"))
        XCTAssertTrue(message.contains("Description: On-call heavy"))
    }
}
