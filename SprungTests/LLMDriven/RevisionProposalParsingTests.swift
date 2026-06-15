//
//  RevisionProposalParsingTests.swift
//  SprungTests
//
//  Phase 5 (LLM-driven subsystem tests — pure units).
//
//  The revision agent's tool-call argument parsing and tool-result encoding are
//  pure JSON <-> value-type transforms — exactly the input/output halves of the
//  LLM seam that can be tested without a model:
//    - ProposeChangesTool.Parameters / ChangeDetail decode (snake_case wire keys,
//      evidence decoded optionally so a malformed call degrades gracefully)
//    - AskUserTool.Parameters decode
//    - ProposalResponse.toolResultJSON encode (accepted / rejected / modified /
//      itemized), which is what the agent feeds back to the model as a tool_result
//

import XCTest
import SwiftyJSON
@testable import Sprung

final class RevisionProposalParsingTests: XCTestCase {

    private let decoder = JSONDecoder()

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try decoder.decode(type, from: data)
    }

    // MARK: - ChangeDetail decode (snake_case keys)

    func testChangeDetailDecodesAllFieldsIncludingSnakeCase() throws {
        let json = """
        {
          "section": "summary",
          "type": "modify",
          "description": "Tighten the opener",
          "evidence": "existing resume content",
          "before_preview": "Results-driven engineer with...",
          "after_preview": "Research engineer focused on..."
        }
        """
        let change = try decode(ProposeChangesTool.ChangeDetail.self, json)
        XCTAssertEqual(change.section, "summary")
        XCTAssertEqual(change.type, "modify")
        XCTAssertEqual(change.description, "Tighten the opener")
        XCTAssertEqual(change.evidence, "existing resume content")
        XCTAssertEqual(change.beforePreview, "Results-driven engineer with...",
                       "before_preview wire key maps to beforePreview")
        XCTAssertEqual(change.afterPreview, "Research engineer focused on...",
                       "after_preview wire key maps to afterPreview")
    }

    func testChangeDetailDecodesWithMissingOptionalEvidence() throws {
        // evidence is required by the schema but decoded as optional, so a
        // malformed call (missing evidence) degrades to nil instead of failing.
        let json = """
        { "section": "skills", "type": "add", "description": "Add Rust" }
        """
        let change = try decode(ProposeChangesTool.ChangeDetail.self, json)
        XCTAssertEqual(change.section, "skills")
        XCTAssertNil(change.evidence, "missing evidence decodes to nil, not a thrown error")
        XCTAssertNil(change.beforePreview, "missing before_preview is nil (e.g. an add)")
        XCTAssertNil(change.afterPreview)
    }

    func testChangeDetailMissingRequiredKeyThrows() {
        // section/type/description are non-optional; omitting one is a decode error.
        let json = """
        { "type": "remove", "description": "drop a bullet" }
        """
        XCTAssertThrowsError(try decode(ProposeChangesTool.ChangeDetail.self, json),
                             "missing required 'section' must throw")
    }

    // MARK: - Parameters decode (summary + changes array)

    func testParametersDecodeFullProposal() throws {
        let json = """
        {
          "summary": "Tailor the resume to the platform role.",
          "changes": [
            { "section": "summary", "type": "modify", "description": "rewrite", "evidence": "card: Backend Lead" },
            { "section": "skills", "type": "add", "description": "add Kafka", "evidence": "skill-bank: Kafka",
              "before_preview": "", "after_preview": "Kafka" }
          ]
        }
        """
        let params = try decode(ProposeChangesTool.Parameters.self, json)
        XCTAssertEqual(params.summary, "Tailor the resume to the platform role.")
        XCTAssertEqual(params.changes.count, 2)
        XCTAssertEqual(params.changes[0].section, "summary")
        XCTAssertEqual(params.changes[1].afterPreview, "Kafka")
    }

    func testParametersDecodeEmptyChangesArray() throws {
        let json = #"{ "summary": "no-op", "changes": [] }"#
        let params = try decode(ProposeChangesTool.Parameters.self, json)
        XCTAssertEqual(params.summary, "no-op")
        XCTAssertTrue(params.changes.isEmpty)
    }

    // MARK: - AskUserTool.Parameters decode

    func testAskUserParametersDecode() throws {
        let json = #"{ "question": "Which seniority level should I target?" }"#
        let params = try decode(AskUserTool.Parameters.self, json)
        XCTAssertEqual(params.question, "Which seniority level should I target?")
    }

    func testAskUserParametersMissingQuestionThrows() {
        XCTAssertThrowsError(try decode(AskUserTool.Parameters.self, "{}"),
                             "ask_user without a question must throw")
    }

    // MARK: - Tool name / schema sanity

    func testToolNamesMatchWireContract() {
        XCTAssertEqual(ProposeChangesTool.name, "propose_changes")
        XCTAssertEqual(AskUserTool.name, "ask_user")
    }

    // MARK: - ProposalResponse.toolResultJSON encode

    func testAcceptedAndRejectedToolResultJSON() throws {
        let accepted = JSON(parseJSON: ProposalResponse.accepted.toolResultJSON)
        XCTAssertEqual(accepted["decision"].stringValue, "accepted")
        XCTAssertEqual(accepted["feedback"].stringValue, "")

        let rejected = JSON(parseJSON: ProposalResponse.rejected.toolResultJSON)
        XCTAssertEqual(rejected["decision"].stringValue, "rejected")
    }

    func testModifiedToolResultJSONCarriesFeedback() throws {
        let json = JSON(parseJSON: ProposalResponse.modified(feedback: "Shorten the summary").toolResultJSON)
        XCTAssertEqual(json["decision"].stringValue, "modified")
        XCTAssertEqual(json["feedback"].stringValue, "Shorten the summary")
    }

    func testItemizedToolResultJSONEncodesPerItemDecisions() throws {
        let items = [
            ItemDecision(index: 0, section: "summary", kind: .accept, feedback: nil, editedText: nil),
            ItemDecision(index: 1, section: "skills", kind: .reject, feedback: nil, editedText: nil),
            ItemDecision(index: 2, section: "work", kind: .feedback, feedback: "more impact", editedText: nil),
            ItemDecision(index: 3, section: "title", kind: .edit, feedback: nil, editedText: "Staff Engineer"),
        ]
        let json = JSON(parseJSON: ProposalResponse.itemized(items).toolResultJSON)
        XCTAssertEqual(json["decision"].stringValue, "itemized")
        let encoded = json["items"].arrayValue
        XCTAssertEqual(encoded.count, 4)

        // Index 0: plain accept — no feedback / edited_text keys.
        XCTAssertEqual(encoded[0]["index"].intValue, 0)
        XCTAssertEqual(encoded[0]["section"].stringValue, "summary")
        XCTAssertEqual(encoded[0]["decision"].stringValue, "accept")
        XCTAssertFalse(encoded[0].dictionaryValue.keys.contains("feedback"),
                       "no feedback key when feedback is nil")
        XCTAssertFalse(encoded[0].dictionaryValue.keys.contains("edited_text"))

        // Index 2: feedback carried under "feedback".
        XCTAssertEqual(encoded[2]["decision"].stringValue, "feedback")
        XCTAssertEqual(encoded[2]["feedback"].stringValue, "more impact")

        // Index 3: edited text carried under the snake_case "edited_text" key.
        XCTAssertEqual(encoded[3]["decision"].stringValue, "edit")
        XCTAssertEqual(encoded[3]["edited_text"].stringValue, "Staff Engineer")
    }

    func testItemDecisionKindRawValues() {
        XCTAssertEqual(ItemDecision.Kind.accept.rawValue, "accept")
        XCTAssertEqual(ItemDecision.Kind.reject.rawValue, "reject")
        XCTAssertEqual(ItemDecision.Kind.feedback.rawValue, "feedback")
        XCTAssertEqual(ItemDecision.Kind.edit.rawValue, "edit")
    }

    // MARK: - ChangeProposal.verification(at:) bounds safety

    func testChangeProposalVerificationIndexOutOfBoundsIsNotApplicable() {
        let proposal = ChangeProposal(summary: "s", changes: [], verifications: [.verified])
        guard case .verified = proposal.verification(at: 0) else {
            return XCTFail("index 0 should return the stored verification")
        }
        // Out-of-range index degrades to .notApplicable rather than crashing.
        guard case .notApplicable = proposal.verification(at: 5) else {
            return XCTFail("out-of-range verification index must be .notApplicable")
        }
    }
}
