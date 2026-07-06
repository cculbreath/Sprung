//
//  JobScoutLoopTests.swift
//  SprungTests
//
//  Pure halves of the Job Scout agent loop (JobScoutLoop), no LLMFacade
//  needed:
//
//  1. search_board validation: the board string must name a known board AND
//     one enabled for this run — anything else becomes the corrective
//     tool-result message the runner relays.
//  2. The recommend_jobs submission contract: valid payloads, explicit-null
//     emptyReason (strict tool use sends null, never absent), the honest
//     empty shape, malformed payloads, and the essentials/invalid-URL/
//     duplicate-URL rejections that feed the runner's corrective retry.
//

import XCTest
import SwiftOpenAI
@testable import Sprung

@MainActor
final class JobScoutLoopTests: XCTestCase {

    // MARK: - Helpers

    private func decodeToolUse(inputJSON: String) throws -> AnthropicToolUseResponseBlock {
        let json = #"{"type":"tool_use","id":"tu_1","name":"recommend_jobs","input":"# + inputJSON + "}"
        return try JSONDecoder().decode(AnthropicToolUseResponseBlock.self, from: Data(json.utf8))
    }

    // MARK: - 1. Board validation

    func testValidatedBoardAcceptsEnabledBoard() {
        let validation = JobScoutLoop.validatedBoard("dice", enabledBoards: [.dice, .linkedIn])
        XCTAssertEqual(validation, .valid(.dice))
    }

    func testValidatedBoardRejectsUnknownBoardNamingTheValidOnes() {
        let validation = JobScoutLoop.validatedBoard("monster", enabledBoards: [.dice])
        guard case .invalid(let message) = validation else {
            return XCTFail("unknown board must be invalid")
        }
        XCTAssertTrue(message.contains("monster"))
        XCTAssertTrue(message.contains("dice, zipRecruiter, linkedIn"),
                      "the corrective message teaches the valid board names")
    }

    func testValidatedBoardRejectsDisabledBoardNamingTheEnabledOnes() {
        let validation = JobScoutLoop.validatedBoard("linkedIn", enabledBoards: [.dice, .zipRecruiter])
        guard case .invalid(let message) = validation else {
            return XCTFail("a board outside this run's config must be invalid")
        }
        XCTAssertTrue(message.contains("LinkedIn is not enabled"))
        XCTAssertTrue(message.contains("dice"))
        XCTAssertTrue(message.contains("zipRecruiter"))
    }

    // MARK: - 2. Submission decoding

    func testDecodeSubmissionValidRecommendations() throws {
        let call = try decodeToolUse(inputJSON: #"""
        {"recommendations":[
          {"url":"https://www.dice.com/job-detail/abc","title":"Senior Medical Physicist",
           "company":"Acme Oncology","reasoning":"Their linac commissioning work lines up with the dossier."},
          {"url":"https://www.linkedin.com/jobs/view/4242/","title":"Physicist II",
           "company":"Beta Health","reasoning":"A close fit for the clinical QA background."}
        ],"emptyReason":null}
        """#)
        let submission = try JobScoutLoop.decodeSubmission(call)
        XCTAssertEqual(submission.recommendations.count, 2)
        XCTAssertEqual(submission.recommendations[0].title, "Senior Medical Physicist")
        XCTAssertNil(submission.emptyReason)
    }

    func testDecodeSubmissionHonestEmptyShape() throws {
        let call = try decodeToolUse(
            inputJSON: #"{"recommendations":[],"emptyReason":"Every board search failed."}"#
        )
        let submission = try JobScoutLoop.decodeSubmission(call)
        XCTAssertTrue(submission.recommendations.isEmpty)
        XCTAssertEqual(submission.emptyReason, "Every board search failed.")
    }

    func testDecodeSubmissionMalformedPayloadThrows() throws {
        let call = try decodeToolUse(inputJSON: #"{"jobs":["not the schema"]}"#)
        XCTAssertThrowsError(try JobScoutLoop.decodeSubmission(call)) { error in
            XCTAssertTrue("\(error)".contains("recommend_jobs"),
                          "the corrective message names the tool being retried")
        }
    }

    func testDecodeSubmissionRejectsMissingEssentials() throws {
        let call = try decodeToolUse(inputJSON: #"""
        {"recommendations":[
          {"url":"https://a.example.com/1","title":"Physicist","company":"  ","reasoning":"fit"}
        ],"emptyReason":null}
        """#)
        XCTAssertThrowsError(try JobScoutLoop.decodeSubmission(call)) { error in
            XCTAssertTrue("\(error)".contains("title, company, or reasoning"))
        }
    }

    func testDecodeSubmissionRejectsNonHTTPURLs() throws {
        let call = try decodeToolUse(inputJSON: #"""
        {"recommendations":[
          {"url":"ftp://boards.example.com/1","title":"Physicist","company":"Acme","reasoning":"fit"}
        ],"emptyReason":null}
        """#)
        XCTAssertThrowsError(try JobScoutLoop.decodeSubmission(call)) { error in
            XCTAssertTrue("\(error)".contains("invalid posting URLs"))
        }
    }

    func testDecodeSubmissionRejectsDuplicateURLs() throws {
        let call = try decodeToolUse(inputJSON: #"""
        {"recommendations":[
          {"url":"https://a.example.com/1","title":"Physicist","company":"Acme","reasoning":"fit"},
          {"url":"https://a.example.com/1","title":"Physicist (again)","company":"Acme","reasoning":"same"}
        ],"emptyReason":null}
        """#)
        XCTAssertThrowsError(try JobScoutLoop.decodeSubmission(call)) { error in
            XCTAssertTrue("\(error)".contains("exactly once"))
        }
    }
}
