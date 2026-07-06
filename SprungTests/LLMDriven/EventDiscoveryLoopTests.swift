//
//  EventDiscoveryLoopTests.swift
//  SprungTests
//
//  Pure halves of the networking-event discovery agent (EventDiscoveryLoop +
//  EventDiscoveryToolSchemas), no LLMFacade needed:
//
//  1. The strict submit_events schema: camelCase keys we control, every
//     object closed (additionalProperties:false) with every property
//     required — the strict-tool-use compatibility contract — and the
//     server-tool declarations carrying their budgets.
//  2. The DiscoveredEvent submission contract: valid payloads, explicit-null
//     optionals (strict tool use sends null, not absent), malformed payloads,
//     and the unparseable-date rejection that feeds the runner's corrective
//     retry.
//  3. Assistant-echo assembly: the runner's own echo drops server-tool
//     blocks, so the delegate's echo must preserve EVERY response content
//     block verbatim (including encrypted_content) — and the conversation
//     reconciliation must substitute those full echoes for the runner's
//     lossy ones in order.
//

import XCTest
import SwiftOpenAI
@testable import Sprung

@MainActor
final class EventDiscoveryLoopTests: XCTestCase {

    // MARK: - Helpers

    private func decodeToolUse(inputJSON: String) throws -> AnthropicToolUseResponseBlock {
        let json = #"{"type":"tool_use","id":"tu_1","name":"submit_events","input":"# + inputJSON + "}"
        return try JSONDecoder().decode(AnthropicToolUseResponseBlock.self, from: Data(json.utf8))
    }

    private func decodeResponse(_ json: String) throws -> AnthropicMessageResponse {
        try JSONDecoder().decode(AnthropicMessageResponse.self, from: Data(json.utf8))
    }

    private func encodedJSON<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    /// Recursively assert strict-tool-use compatibility: every object schema is
    /// closed and requires every property, and every property key is camelCase.
    private func assertStrictObject(_ schema: [String: Any], path: String) {
        let isObject = (schema["type"] as? String) == "object" || schema["properties"] != nil
        guard isObject else { return }

        XCTAssertEqual(schema["additionalProperties"] as? Bool, false,
                       "\(path): every object needs additionalProperties:false")
        let properties = schema["properties"] as? [String: [String: Any]] ?? [:]
        let required = Set(schema["required"] as? [String] ?? [])
        XCTAssertEqual(Set(properties.keys), required,
                       "\(path): strict tool use requires every property in required")

        for (key, subSchema) in properties {
            XCTAssertFalse(key.contains("_"),
                           "\(path).\(key): schema keys we control must be camelCase")
            assertStrictObject(subSchema, path: "\(path).\(key)")
            if let items = subSchema["items"] as? [String: Any] {
                assertStrictObject(items, path: "\(path).\(key).items")
            }
        }
    }

    // MARK: - 1. Tool schema shape

    func testSubmitEventsSchemaIsStrictCompatibleAndCamelCase() {
        assertStrictObject(EventDiscoveryToolSchemas.submitEventsSchema, path: "submitEvents")
    }

    func testSubmitEventsSchemaPinsVerificationFields() throws {
        let schema = EventDiscoveryToolSchemas.submitEventsSchema
        let events = try XCTUnwrap(schema["properties"] as? [String: [String: Any]])["events"]
        let items = try XCTUnwrap(events?["items"] as? [String: Any])
        let keys = Set(try XCTUnwrap(items["properties"] as? [String: Any]).keys)
        XCTAssertTrue(keys.isSuperset(of: ["name", "date", "time", "location", "format", "organizer", "url"]),
                      "page-verified fields must all be present in the event schema")
    }

    func testToolsArrayDeclaresServerToolsWithBudgetsAndStrictCompletion() throws {
        let json = try encodedJSON(EventDiscoveryToolSchemas.allTools)

        // web_search: 20260209 variant with the search budget.
        XCTAssertTrue(json.contains(#""type":"web_search_20260209""#))
        XCTAssertTrue(json.contains(#""max_uses":12"#))

        // web_fetch: 20260209 variant with fetch budget and content-token bound.
        XCTAssertTrue(json.contains(#""type":"web_fetch_20260209""#))
        XCTAssertTrue(json.contains(#""max_uses":10"#))
        XCTAssertTrue(json.contains(#""max_content_tokens":8000"#))

        // Completion tool: strict.
        XCTAssertTrue(json.contains(#""name":"submit_events""#))
        XCTAssertTrue(json.contains(#""strict":true"#))
    }

    // MARK: - 2. Submission decoding

    func testDecodeSubmissionValidEvents() throws {
        let call = try decodeToolUse(inputJSON: #"""
        {"events":[
          {"name":"Huntsville Tech Mixer","date":"2026-07-21","time":"6:00 PM",
           "location":"Stovehouse, Huntsville, AL","format":"in_person",
           "organizer":"TechHSV","url":"https://example.com/mixer",
           "eventType":"meetup","cost":"Free","estimatedAttendance":"medium",
           "relevanceReason":"Local embedded-systems crowd."},
          {"name":"Optics Society Webinar","date":"2026-08-02","time":null,
           "location":"Virtual","format":"virtual",
           "organizer":"Optica","url":"https://example.com/webinar",
           "eventType":"virtual_event","cost":null,"estimatedAttendance":null,
           "relevanceReason":"Photonics background."}
        ]}
        """#)

        let events = try EventDiscoveryLoop.decodeSubmission(call)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].name, "Huntsville Tech Mixer")
        XCTAssertEqual(events[0].format, "in_person")
        XCTAssertNotNil(events[0].parsedDate)
        XCTAssertNil(events[1].time, "explicit JSON null decodes to nil")
        XCTAssertNil(events[1].cost)
        XCTAssertNil(events[1].estimatedAttendance)
    }

    func testDecodeSubmissionEmptyListIsValid() throws {
        let call = try decodeToolUse(inputJSON: #"{"events":[]}"#)
        XCTAssertTrue(try EventDiscoveryLoop.decodeSubmission(call).isEmpty,
                      "nothing surviving verification is a legitimate outcome")
    }

    func testDecodeSubmissionMissingRequiredFieldThrows() throws {
        // No "name" — decode must fail with a corrective, retryable error.
        let call = try decodeToolUse(inputJSON: #"""
        {"events":[{"date":"2026-07-21","time":null,"location":"HSV","format":"in_person",
         "organizer":"X","url":"https://example.com","eventType":"meetup",
         "cost":null,"estimatedAttendance":null,"relevanceReason":"r"}]}
        """#)
        XCTAssertThrowsError(try EventDiscoveryLoop.decodeSubmission(call)) { error in
            guard case DiscoveryAgentError.llmError(let message) = error else {
                return XCTFail("expected .llmError, got \(error)")
            }
            XCTAssertTrue(message.contains("failed to decode"))
        }
    }

    func testDecodeSubmissionUnparseableDateThrowsCorrectiveError() throws {
        let call = try decodeToolUse(inputJSON: #"""
        {"events":[{"name":"Bad Date Gala","date":"July 21st","time":null,"location":"HSV",
         "format":"in_person","organizer":"X","url":"https://example.com","eventType":"meetup",
         "cost":null,"estimatedAttendance":null,"relevanceReason":"r"}]}
        """#)
        XCTAssertThrowsError(try EventDiscoveryLoop.decodeSubmission(call)) { error in
            guard case DiscoveryAgentError.llmError(let message) = error else {
                return XCTFail("expected .llmError, got \(error)")
            }
            XCTAssertTrue(message.contains("YYYY-MM-DD"), "corrective message must name the expected format")
            XCTAssertTrue(message.contains("Bad Date Gala"), "corrective message must name the offending event")
        }
    }

    func testParseEventDateAcceptsContractAndISOFormats() {
        XCTAssertNotNil(DiscoveredEvent.parseEventDate("2026-07-21"))
        XCTAssertNotNil(DiscoveredEvent.parseEventDate("2026-07-21T18:00:00Z"))
        XCTAssertNil(DiscoveredEvent.parseEventDate("July 21, 2026"))
        XCTAssertNil(DiscoveredEvent.parseEventDate("soon"))
    }

    // MARK: - 3. Assistant echo (server-tool block preservation)

    /// A response mid-research: text + web_search round-trip + web_fetch
    /// round-trip + a client tool call, stopped with pause_turn.
    private let researchResponseJSON = #"""
    {"id":"msg_01","type":"message","role":"assistant","model":"claude-x","content":[
      {"type":"text","text":"Searching for events."},
      {"type":"server_tool_use","id":"srvtoolu_01","name":"web_search","input":{"query":"huntsville tech meetups"}},
      {"type":"web_search_tool_result","tool_use_id":"srvtoolu_01","content":[
        {"type":"web_search_result","url":"https://example.com/events","title":"Tech Mixers","encrypted_content":"OPAQUE_SEARCH_1","page_age":"July 1, 2026"}]},
      {"type":"server_tool_use","id":"srvtoolu_02","name":"web_fetch","input":{"url":"https://example.com/event/42"}},
      {"type":"web_fetch_tool_result","tool_use_id":"srvtoolu_02","content":{
        "type":"web_fetch_result","url":"https://example.com/event/42",
        "content":{"type":"document","source":{"type":"text","media_type":"text/plain","data":"Doors at 6pm. RSVP required."},"title":"Event 42"},
        "retrieved_at":"2026-07-06T12:00:00Z"}},
      {"type":"tool_use","id":"tu_1","name":"submit_events","input":{"events":[]}}
    ],"stop_reason":"pause_turn","stop_sequence":null,
    "usage":{"input_tokens":100,"output_tokens":50,"server_tool_use":{"web_search_requests":1,"web_fetch_requests":1}}}
    """#

    func testAssistantEchoPreservesAllBlocksInOrder() throws {
        let response = try decodeResponse(researchResponseJSON)
        XCTAssertEqual(response.stopReason, "pause_turn", "pause_turn must pass through undamaged")

        let echo = EventDiscoveryLoop.assistantEcho(from: response)
        XCTAssertEqual(echo.role, "assistant")

        guard case .blocks(let blocks) = echo.content else {
            return XCTFail("expected block content")
        }
        XCTAssertEqual(blocks.count, 6, "every response block must survive the echo")

        guard case .text(let text) = blocks[0],
              case .serverToolUse(let search) = blocks[1],
              case .webSearchToolResult(let searchResult) = blocks[2],
              case .serverToolUse(let fetch) = blocks[3],
              case .webFetchToolResult(let fetchResult) = blocks[4],
              case .toolUse(let toolUse) = blocks[5] else {
            return XCTFail("echo blocks out of order or wrong type: \(blocks)")
        }
        XCTAssertEqual(text.text, "Searching for events.")
        XCTAssertEqual(search.name, "web_search")
        XCTAssertEqual(search.input["query"]?.value as? String, "huntsville tech meetups")
        XCTAssertEqual(searchResult.toolUseId, "srvtoolu_01")
        XCTAssertEqual(fetch.name, "web_fetch")
        XCTAssertEqual(fetchResult.toolUseId, "srvtoolu_02")
        XCTAssertEqual(toolUse.name, "submit_events")
    }

    func testAssistantEchoReencodesServerToolPayloadsVerbatim() throws {
        let response = try decodeResponse(researchResponseJSON)
        let echo = EventDiscoveryLoop.assistantEcho(from: response)
        let json = try encodedJSON(echo)

        // The opaque search payload — what lets the model keep citing pages
        // across turns — must survive re-encoding exactly.
        XCTAssertTrue(json.contains(#""encrypted_content":"OPAQUE_SEARCH_1""#))
        XCTAssertTrue(json.contains(#""page_age":"July 1, 2026""#))
        // The fetched document and its retrieval metadata must survive too.
        XCTAssertTrue(json.contains("Doors at 6pm. RSVP required."))
        XCTAssertTrue(json.contains(#""retrieved_at":"2026-07-06T12:00:00Z""#))
        // Wire type tags intact.
        XCTAssertTrue(json.contains(#""type":"server_tool_use""#))
        XCTAssertTrue(json.contains(#""type":"web_search_tool_result""#))
        XCTAssertTrue(json.contains(#""type":"web_fetch_tool_result""#))
    }

    func testAssistantEchoDropsWhitespaceTextAndPlaceholdersEmptyTurn() throws {
        let response = try decodeResponse(#"""
        {"id":"msg_02","type":"message","role":"assistant","model":"claude-x",
         "content":[{"type":"text","text":"   \n  "}],
         "stop_reason":"end_turn","stop_sequence":null,
         "usage":{"input_tokens":1,"output_tokens":1}}
        """#)
        let echo = EventDiscoveryLoop.assistantEcho(from: response)
        guard case .blocks(let blocks) = echo.content, case .text(let text) = blocks.first else {
            return XCTFail("expected a single text block")
        }
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(text.text, "(continuing)", "the API rejects empty assistant messages")
    }

    // MARK: - 3b. Conversation reconciliation

    func testReconciledSubstitutesFullEchoesForLossyAssistantTurns() {
        // Runner history: task, lossy echo 1, nudge, lossy echo 2, tool results.
        let messages: [AnthropicMessage] = [
            .user("find events"),
            .assistant("lossy turn 1"),
            .user("nudge"),
            .assistant("lossy turn 2"),
            AnthropicMessage(role: "user", content: .blocks([
                .toolResult(AnthropicToolResultBlock(toolUseId: "tu_1", content: "err", isError: true))
            ]))
        ]
        // Turn 1 paused once (two full-echo segments); turn 2 was a single segment.
        let turnEchoes: [[AnthropicMessage]] = [
            [.assistant("full 1a"), .assistant("full 1b")],
            [.assistant("full 2")]
        ]

        let reconciled = EventDiscoveryLoop.reconciled(messages, turnEchoes: turnEchoes)

        XCTAssertEqual(reconciled.count, 6, "turn 1's pause segment adds one message")
        XCTAssertEqual(texts(of: reconciled), [
            "find events", "full 1a", "full 1b", "nudge", "full 2", nil
        ], "assistant turns replaced in order; user messages pass through")
        XCTAssertEqual(reconciled.map(\.role), ["user", "assistant", "assistant", "user", "assistant", "user"])
    }

    func testReconciledPassesThroughWhenNoEchoesStashed() {
        let messages: [AnthropicMessage] = [.user("find events")]
        let reconciled = EventDiscoveryLoop.reconciled(messages, turnEchoes: [])
        XCTAssertEqual(reconciled.count, 1)
        XCTAssertEqual(texts(of: reconciled), ["find events"])
    }

    /// Text of each message when it is simple `.text` content; nil for block content.
    private func texts(of messages: [AnthropicMessage]) -> [String?] {
        messages.map { message in
            if case .text(let text) = message.content { return text }
            return nil
        }
    }

    // MARK: - 4. Task-message assembly (7-day focus, taste signal, guidance)

    /// Midnight local on a fixed date, through the same parser that pins the
    /// submission date contract.
    private var fixedToday: Date {
        DiscoveredEvent.parseEventDate("2026-07-06")!
    }

    private func userMessage(
        candidateContext: String = "",
        knownEventsContext: String = "",
        attendedHistoryContext: String = "",
        operatorGuidance: String = "",
        daysAhead: Int = 42
    ) -> String {
        DiscoveryAgentService.eventDiscoveryUserMessage(
            sectors: ["Photonics", "Embedded Systems"],
            location: "Huntsville, AL",
            candidateContext: candidateContext,
            knownEventsContext: knownEventsContext,
            attendedHistoryContext: attendedHistoryContext,
            operatorGuidance: operatorGuidance,
            today: fixedToday,
            daysAhead: daysAhead
        )
    }

    func testUserMessageCarriesTodayPriorityAndFullWindows() {
        let message = userMessage()
        XCTAssertTrue(message.contains("Today: 2026-07-06"))
        XCTAssertTrue(message.contains("PRIORITY WINDOW (next 7 days): 2026-07-06 through 2026-07-13"),
                      "the next-7-days window is the core deliverable of a weekly run")
        XCTAssertTrue(message.contains("FULL WINDOW: 2026-07-06 through 2026-08-17"),
                      "42-day forward sweep window")
        XCTAssertTrue(message.contains("Target sectors: Photonics, Embedded Systems"))
        XCTAssertTrue(message.contains("Location: Huntsville, AL"))
    }

    func testUserMessageGuidanceBlockPresentOnlyWhenProvided() {
        let plain = userMessage()
        XCTAssertFalse(plain.contains("OPERATOR GUIDANCE"), "empty guidance = plain run")

        let whitespace = userMessage(operatorGuidance: "  \n ")
        XCTAssertFalse(whitespace.contains("OPERATOR GUIDANCE"), "whitespace-only guidance = plain run")

        let steered = userMessage(operatorGuidance: "Virtual events only this week.")
        XCTAssertTrue(steered.contains("## OPERATOR GUIDANCE FOR THIS RUN\nVirtual events only this week."),
                      "guidance arrives as a clearly delimited steering block")
    }

    func testUserMessageKeepsTasteSignalDistinctFromKnownEvents() throws {
        let message = userMessage(
            knownEventsContext: "- Rocket City Mixer — 2026-07-09",
            attendedHistoryContext: "- Optics Symposium — Conference, rated 5/5"
        )
        let historyRange = try XCTUnwrap(
            message.range(of: "## ATTENDED EVENT HISTORY (what the user actually shows up to)")
        )
        let knownRange = try XCTUnwrap(message.range(of: "## ALREADY KNOWN EVENTS (do not resubmit)"))
        XCTAssertLessThan(historyRange.lowerBound, knownRange.lowerBound,
                          "taste signal and do-not-resubmit list are separate, distinctly framed blocks")
        XCTAssertTrue(message.contains("- Optics Symposium — Conference, rated 5/5"))
        XCTAssertTrue(message.contains("- Rocket City Mixer — 2026-07-09"))
    }

    func testAttendedHistoryContextCapsAtTenMostRecent() {
        let records = (1...12).map { index in
            AttendedEventRecord(name: "Event \(index)", eventType: "Meetup", organizer: nil, rating: nil)
        }
        let context = DiscoveryAgentService.attendedHistoryContext(records)
        let lines = context.split(separator: "\n")
        XCTAssertEqual(lines.count, 10, "history is capped at the 10 most recent records")
        XCTAssertTrue(context.contains("- Event 1 — Meetup"), "caller orders most-recent-first; cap keeps the head")
        XCTAssertTrue(context.contains("- Event 10 — Meetup"))
        XCTAssertFalse(context.contains("Event 11"))
        XCTAssertFalse(context.contains("Event 12"))
    }

    func testAttendedHistoryContextFormatsOrganizerAndRating() {
        let context = DiscoveryAgentService.attendedHistoryContext([
            AttendedEventRecord(name: "Photonics West", eventType: "Conference", organizer: "SPIE", rating: 5),
            AttendedEventRecord(name: "Hardware Meetup", eventType: "Meetup", organizer: nil, rating: nil),
            AttendedEventRecord(name: "Career Fair", eventType: "Career Fair", organizer: "", rating: 2)
        ])
        let lines = context.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines, [
            "- Photonics West — Conference, organizer: SPIE, rated 5/5",
            "- Hardware Meetup — Meetup",
            "- Career Fair — Career Fair, rated 2/5"
        ], "organizer and rating render only when present; empty organizer is omitted")
    }

    func testAttendedHistoryContextEmptyWithNoRecords() {
        XCTAssertEqual(DiscoveryAgentService.attendedHistoryContext([]), "",
                       "no history means no taste-signal block in the task message")
    }
}
