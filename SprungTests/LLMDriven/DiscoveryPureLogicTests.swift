//
//  DiscoveryPureLogicTests.swift
//  SprungTests
//
//  Phase 5 (LLM-driven subsystem tests — pure units).
//
//  The Discovery agent's LLM responses decode into the Codable DTOs in
//  DiscoveryAgentTypes.swift (and DailyTaskGenerator.swift for the daily-task
//  generation contract). Phase 1's DiscoveryResponseParserTests exercises the
//  top-level Result wrappers through the text-extraction parser;
//  EventDiscoveryLoopTests covers the strict submit_events event-discovery
//  contract. This file covers the per-item response DTOs directly — the
//  wire-key mapping (camelCase for the daily-task/job-selection contracts we
//  control; snake_case where the prompt templates pin it) and optional-field
//  handling — plus the two value-type mappers (TalkingPointResult /
//  TargetCompanyResult), which are pure. The remaining `to*()` mapper builds
//  a SwiftData @Model object (NetworkingEventOpportunity) and is out of scope
//  for a pure unit.
//

import XCTest
@testable import Sprung

final class DiscoveryPureLogicTests: XCTestCase {

    private let decoder = JSONDecoder()

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try decoder.decode(type, from: data)
    }

    // MARK: - DailyTaskGenerationResponse (camelCase keys — the single task-gen contract)

    func testDailyTaskGenerationResponseDecodesAllSections() throws {
        let json = """
        {
          "newTasks": [
            {
              "taskType": "follow_up",
              "title": "Email Dana",
              "description": "Thank-you note",
              "priority": 2,
              "estimatedMinutes": 15,
              "relatedId": "B6A1..."
            }
          ],
          "carryOver": ["9C0FBB2E-2455-4B37-BB9F-6F13BF3B1F14"],
          "retired": [
            { "taskId": "1B7B33F0-8F44-4B57-9111-31E9B76C6F60", "reason": "Event passed on Friday" }
          ],
          "summary": "Follow-ups first, then one application."
        }
        """
        let response = try decode(DailyTaskGenerationResponse.self, json)
        XCTAssertEqual(response.newTasks.count, 1)
        XCTAssertEqual(response.newTasks[0].taskType, "follow_up",
                       "taskType decodes (values like follow_up stay snake_case)")
        XCTAssertEqual(response.newTasks[0].estimatedMinutes, 15, "estimatedMinutes decodes")
        XCTAssertEqual(response.newTasks[0].relatedId, "B6A1...", "relatedId decodes")
        XCTAssertEqual(response.carryOver, ["9C0FBB2E-2455-4B37-BB9F-6F13BF3B1F14"])
        XCTAssertEqual(response.retired.count, 1)
        XCTAssertEqual(response.retired[0].reason, "Event passed on Friday",
                       "retirement reasons are part of the wire contract — they're shown to the user")
        XCTAssertEqual(response.summary, "Follow-ups first, then one application.")
    }

    func testDailyTaskGenerationEntryNullRelatedIdDecodesToNil() throws {
        let json = """
        {
          "taskType": "gather",
          "title": "Scan boards",
          "description": "Check the two due sources",
          "priority": 1,
          "estimatedMinutes": 30,
          "relatedId": null
        }
        """
        let entry = try decode(DailyTaskGenerationEntry.self, json)
        XCTAssertNil(entry.relatedId, "explicit null relatedId decodes to nil")
    }

    // MARK: - JobSelection / JobSelectionsResult

    func testJobSelectionDecodesUUIDAndScore() throws {
        let uuid = UUID()
        let json = """
        {
          "jobId": "\(uuid.uuidString)",
          "company": "Globex",
          "role": "Platform Engineer",
          "matchScore": 0.82,
          "reasoning": "Strong infra overlap"
        }
        """
        let selection = try decode(JobSelection.self, json)
        XCTAssertEqual(selection.jobId, uuid, "jobId decodes into a UUID")
        XCTAssertEqual(selection.company, "Globex")
        XCTAssertEqual(selection.matchScore, 0.82, accuracy: 0.0001, "matchScore decodes")
    }

    func testJobSelectionsResultDecodesWrapperFields() throws {
        let json = """
        {
          "selections": [],
          "overallAnalysis": "Two strong fits this week.",
          "considerations": ["Location", "Comp"]
        }
        """
        let result = try decode(JobSelectionsResult.self, json)
        XCTAssertEqual(result.overallAnalysis, "Two strong fits this week.",
                       "overallAnalysis decodes")
        XCTAssertEqual(result.considerations, ["Location", "Comp"])
        XCTAssertTrue(result.selections.isEmpty)
    }

    // MARK: - EventPrepResult + value-type mappers

    func testEventPrepResultDecodesNestedSnakeCase() throws {
        let json = """
        {
          "goal": "Land an intro",
          "pitch_script": "Hi, I work on...",
          "talking_points": [
            { "topic": "Scaling", "relevance": "They scaled 10x", "your_angle": "I did similar" }
          ],
          "target_companies": [
            { "company": "Initech", "why_relevant": "Hiring", "recent_news": "Series B",
              "open_roles": ["SRE"], "possible_openers": ["Saw your Series B"] }
          ],
          "conversation_starters": ["Nice talk!"],
          "things_to_avoid": ["Salary talk"]
        }
        """
        let result = try decode(EventPrepResult.self, json)
        XCTAssertEqual(result.pitchScript, "Hi, I work on...", "pitch_script -> pitchScript")
        XCTAssertEqual(result.talkingPoints.count, 1)
        XCTAssertEqual(result.talkingPoints[0].yourAngle, "I did similar", "your_angle -> yourAngle")
        XCTAssertEqual(result.targetCompanies[0].whyRelevant, "Hiring", "why_relevant -> whyRelevant")
        XCTAssertEqual(result.conversationStarters, ["Nice talk!"])
        XCTAssertEqual(result.thingsToAvoid, ["Salary talk"])
    }

    func testTalkingPointResultMapsToValueType() throws {
        let dto = try decode(TalkingPointResult.self, """
        { "topic": "Latency", "relevance": "Core metric", "your_angle": "Cut p99" }
        """)
        let point = dto.toTalkingPoint()
        XCTAssertEqual(point.topic, "Latency")
        XCTAssertEqual(point.relevance, "Core metric")
        XCTAssertEqual(point.yourAngle, "Cut p99", "the mapper carries your_angle through")
    }

    func testTargetCompanyResultMapsToContextPreservingOptionalNews() throws {
        let withNews = try decode(TargetCompanyResult.self, """
        { "company": "Hooli", "why_relevant": "Hiring", "recent_news": "Funding round",
          "open_roles": ["Eng"], "possible_openers": ["Congrats on the round"] }
        """)
        let ctx = withNews.toTargetCompanyContext()
        XCTAssertEqual(ctx.company, "Hooli")
        XCTAssertEqual(ctx.whyRelevant, "Hiring")
        XCTAssertEqual(ctx.recentNews, "Funding round")
        XCTAssertEqual(ctx.openRoles, ["Eng"])
        XCTAssertEqual(ctx.possibleOpeners, ["Congrats on the round"])

        let withoutNews = try decode(TargetCompanyResult.self, """
        { "company": "Pied Piper", "why_relevant": "Compression", "open_roles": [], "possible_openers": [] }
        """)
        XCTAssertNil(withoutNews.toTargetCompanyContext().recentNews,
                     "missing recent_news decodes and maps to nil")
    }

    // MARK: - DebriefOutcomesResult (camelCase keys — pinned by discovery_debrief_outcomes.txt)

    func testDebriefOutcomesResultDecodesCamelCaseContract() throws {
        let json = """
        {
          "summary": "Good event.",
          "keyTakeaways": ["Met 3 leads"],
          "followUpActions": [
            { "contactName": "Dana", "action": "Email resume", "deadline": "tomorrow", "priority": "high" }
          ],
          "opportunitiesIdentified": ["Referral"],
          "nextSteps": ["Send notes"]
        }
        """
        let result = try decode(DebriefOutcomesResult.self, json)
        XCTAssertEqual(result.keyTakeaways, ["Met 3 leads"])
        XCTAssertEqual(result.followUpActions.count, 1)
        XCTAssertEqual(result.followUpActions[0].contactName, "Dana")
        XCTAssertEqual(result.followUpActions[0].priority, "high")
        XCTAssertEqual(result.nextSteps, ["Send notes"])
    }

    // MARK: - DebriefFollowUpAction.dueDate (deadline text -> concrete date)

    private func makeAction(deadline: String) -> DebriefFollowUpAction {
        DebriefFollowUpAction(contactName: "Dana", action: "Email", deadline: deadline, priority: "high")
    }

    private func days(from reference: Date, to date: Date) -> Int? {
        Calendar.current.dateComponents([.day], from: reference, to: date).day
    }

    func testDueDateParsesHoursWeeksAndBareNumbers() throws {
        let reference = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-06T12:00:00Z"))

        XCTAssertEqual(days(from: reference, to: makeAction(deadline: "within 24 hours").dueDate(from: reference)), 1)
        XCTAssertEqual(days(from: reference, to: makeAction(deadline: "within 48 hours").dueDate(from: reference)), 2,
                       "hour quantities round up to whole days")
        XCTAssertEqual(days(from: reference, to: makeAction(deadline: "within 2 weeks").dueDate(from: reference)), 14)
        XCTAssertEqual(days(from: reference, to: makeAction(deadline: "within 3 days").dueDate(from: reference)), 3)
    }

    func testDueDateHandlesWordOnlyDeadlines() throws {
        let reference = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-06T12:00:00Z"))

        XCTAssertEqual(days(from: reference, to: makeAction(deadline: "tomorrow").dueDate(from: reference)), 1)
        XCTAssertEqual(days(from: reference, to: makeAction(deadline: "this week").dueDate(from: reference)), 7)
        XCTAssertEqual(days(from: reference, to: makeAction(deadline: "no rush").dueDate(from: reference)), 3,
                       "an unreadable timeframe lands three days out — the follow-up stays alive")
    }
}
