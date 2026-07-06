//
//  DiscoveryPureLogicTests.swift
//  SprungTests
//
//  Phase 5 (LLM-driven subsystem tests — pure units).
//
//  The Discovery agent's LLM responses decode into the Codable DTOs in
//  DiscoveryAgentTypes.swift. Phase 1's DiscoveryResponseParserTests exercises
//  the three top-level Result wrappers (tasks/sources/events) through the
//  text-extraction parser; this file covers the per-item response DTOs directly
//  — the wire-key mapping (camelCase for the daily-task/job-selection contracts
//  we control; snake_case where the prompt templates pin it) and optional-field
//  handling — plus the two value-type mappers (TalkingPointResult /
//  TargetCompanyResult), which are pure. The remaining `to*()` mappers build
//  SwiftData @Model objects (DailyTask, JobSource, NetworkingEventOpportunity)
//  and are out of scope for a pure unit.
//

import XCTest
@testable import Sprung

final class DiscoveryPureLogicTests: XCTestCase {

    private let decoder = JSONDecoder()

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try decoder.decode(type, from: data)
    }

    // MARK: - GeneratedDailyTask (camelCase keys, optionals)

    func testGeneratedDailyTaskDecodesCamelCaseAndOptionals() throws {
        let json = """
        {
          "taskType": "follow_up",
          "title": "Email Dana",
          "description": "Thank-you note",
          "priority": 2,
          "relatedId": "B6A1...",
          "estimatedMinutes": 15
        }
        """
        let task = try decode(GeneratedDailyTask.self, json)
        XCTAssertEqual(task.taskType, "follow_up", "taskType decodes (values like follow_up stay snake_case)")
        XCTAssertEqual(task.title, "Email Dana")
        XCTAssertEqual(task.priority, 2)
        XCTAssertEqual(task.relatedId, "B6A1...", "relatedId decodes")
        XCTAssertEqual(task.estimatedMinutes, 15, "estimatedMinutes decodes")
    }

    func testGeneratedDailyTaskMissingOptionalsDecodeToNil() throws {
        let json = #"{ "taskType": "gather", "title": "Scan boards", "priority": 1 }"#
        let task = try decode(GeneratedDailyTask.self, json)
        XCTAssertNil(task.description)
        XCTAssertNil(task.relatedId)
        XCTAssertNil(task.estimatedMinutes)
    }

    func testDailyTasksResultWrapsArray() throws {
        let json = """
        { "tasks": [
          { "taskType": "apply", "title": "Submit X", "priority": 1 },
          { "taskType": "networking", "title": "DM Y", "priority": 3 }
        ] }
        """
        let result = try decode(DailyTasksResult.self, json)
        XCTAssertEqual(result.tasks.count, 2)
        XCTAssertEqual(result.tasks[1].taskType, "networking")
    }

    // MARK: - GeneratedJobSource

    func testGeneratedJobSourceDecodesWithAndWithoutCadence() throws {
        let withCadence = try decode(GeneratedJobSource.self, """
        { "name": "ACME Careers", "url": "https://acme.example/jobs", "category": "company_direct",
          "relevance_reason": "Hiring backend", "recommended_cadence_days": 7 }
        """)
        XCTAssertEqual(withCadence.name, "ACME Careers")
        XCTAssertEqual(withCadence.relevanceReason, "Hiring backend", "relevance_reason -> relevanceReason")
        XCTAssertEqual(withCadence.recommendedCadenceDays, 7)

        let withoutCadence = try decode(GeneratedJobSource.self, """
        { "name": "Board", "url": "https://b.example", "category": "aggregator",
          "relevance_reason": "Broad coverage" }
        """)
        XCTAssertNil(withoutCadence.recommendedCadenceDays,
                     "missing recommended_cadence_days decodes to nil")
    }

    // MARK: - GeneratedNetworkingEvent

    func testGeneratedNetworkingEventDecodesSnakeCaseAndOptionals() throws {
        let json = """
        {
          "name": "SwiftConf",
          "date": "2026-09-01",
          "time": "09:00",
          "location": "Berlin",
          "url": "https://swiftconf.example",
          "event_type": "conference",
          "organizer": "Swift GmbH",
          "estimated_attendance": "large",
          "cost": "€200",
          "relevance_reason": "Core stack"
        }
        """
        let event = try decode(GeneratedNetworkingEvent.self, json)
        XCTAssertEqual(event.name, "SwiftConf")
        XCTAssertEqual(event.eventType, "conference", "event_type -> eventType")
        XCTAssertEqual(event.estimatedAttendance, "large", "estimated_attendance -> estimatedAttendance")
        XCTAssertEqual(event.relevanceReason, "Core stack")
    }

    func testGeneratedNetworkingEventOmitsAllOptionals() throws {
        let json = """
        { "name": "Meetup", "date": "2026-01-01", "location": "Online",
          "url": "https://m.example", "event_type": "meetup" }
        """
        let event = try decode(GeneratedNetworkingEvent.self, json)
        XCTAssertNil(event.time)
        XCTAssertNil(event.organizer)
        XCTAssertNil(event.estimatedAttendance)
        XCTAssertNil(event.cost)
        XCTAssertNil(event.relevanceReason)
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

    // MARK: - DebriefOutcomesResult

    func testDebriefOutcomesResultDecodesFollowUpActions() throws {
        let json = """
        {
          "summary": "Good event.",
          "key_takeaways": ["Met 3 leads"],
          "follow_up_actions": [
            { "contact_name": "Dana", "action": "Email resume", "deadline": "tomorrow", "priority": "high" }
          ],
          "opportunities_identified": ["Referral"],
          "next_steps": ["Send notes"]
        }
        """
        let result = try decode(DebriefOutcomesResult.self, json)
        XCTAssertEqual(result.keyTakeaways, ["Met 3 leads"], "key_takeaways -> keyTakeaways")
        XCTAssertEqual(result.followUpActions.count, 1)
        XCTAssertEqual(result.followUpActions[0].contactName, "Dana", "contact_name -> contactName")
        XCTAssertEqual(result.followUpActions[0].priority, "high")
        XCTAssertEqual(result.nextSteps, ["Send notes"], "next_steps -> nextSteps")
    }
}
