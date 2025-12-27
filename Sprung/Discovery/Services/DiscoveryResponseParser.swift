//
//  DiscoveryResponseParser.swift
//  Sprung
//
//  Parses LLM JSON responses into typed result structures.
//

import Foundation
import SwiftyJSON

struct DiscoveryResponseParser {

    // MARK: - Public Parsing Methods

    func parseTasks(_ response: String) throws -> DailyTasksResult {
        let json = try extractAndParseJSON(from: response)
        var tasks: [GeneratedDailyTask] = []

        for taskJson in json["tasks"].arrayValue {
            let task = GeneratedDailyTask(
                taskType: taskJson["task_type"].stringValue,
                title: taskJson["title"].stringValue,
                description: taskJson["description"].string,
                priority: taskJson["priority"].intValue,
                relatedJobSourceId: taskJson["related_id"].string,
                relatedJobAppId: nil,
                relatedContactId: nil,
                relatedEventId: nil,
                estimatedMinutes: taskJson["estimated_minutes"].int
            )
            tasks.append(task)
        }

        return DailyTasksResult(tasks: tasks, summary: json["summary"].string)
    }

    func parseSources(_ response: String) throws -> JobSourcesResult {
        let json = try extractAndParseJSON(from: response)
        var sources: [GeneratedJobSource] = []

        for sourceJson in json["sources"].arrayValue {
            let source = GeneratedJobSource(
                name: sourceJson["name"].stringValue,
                url: sourceJson["url"].stringValue,
                category: sourceJson["category"].stringValue,
                relevanceReason: sourceJson["relevance_reason"].stringValue,
                recommendedCadenceDays: sourceJson["recommended_cadence_days"].int
            )
            sources.append(source)
        }

        return JobSourcesResult(sources: sources)
    }

    func parseEvents(_ response: String) throws -> NetworkingEventsResult {
        let json = try extractAndParseJSON(from: response)
        var events: [GeneratedNetworkingEvent] = []

        for eventJson in json["events"].arrayValue {
            let event = GeneratedNetworkingEvent(
                name: eventJson["name"].stringValue,
                date: eventJson["date"].stringValue,
                time: eventJson["time"].string,
                location: eventJson["location"].stringValue,
                url: eventJson["url"].stringValue,
                eventType: eventJson["event_type"].stringValue,
                organizer: eventJson["organizer"].string,
                estimatedAttendance: eventJson["estimated_attendance"].string,
                cost: eventJson["cost"].string,
                relevanceReason: eventJson["relevance_reason"].string
            )
            events.append(event)
        }

        return NetworkingEventsResult(events: events)
    }

    func parseEvaluation(_ response: String) throws -> EventEvaluationResult {
        let json = try extractAndParseJSON(from: response)

        return EventEvaluationResult(
            recommendation: json["recommendation"].stringValue,
            rationale: json["rationale"].stringValue,
            expectedValue: json["expected_value"].string,
            concerns: json["concerns"].arrayValue.map { $0.stringValue },
            preparationTips: json["preparation_tips"].arrayValue.map { $0.stringValue }
        )
    }

    func parsePrep(_ response: String) throws -> EventPrepResult {
        let json = try extractAndParseJSON(from: response)

        return EventPrepResult(
            goal: json["goal"].stringValue,
            pitchScript: json["pitch_script"].stringValue,
            talkingPoints: json["talking_points"].arrayValue.map {
                TalkingPointResult(
                    topic: $0["topic"].stringValue,
                    relevance: $0["relevance"].stringValue,
                    yourAngle: $0["your_angle"].stringValue
                )
            },
            targetCompanies: json["target_companies"].arrayValue.map {
                TargetCompanyResult(
                    company: $0["company"].stringValue,
                    whyRelevant: $0["why_relevant"].stringValue,
                    recentNews: $0["recent_news"].string,
                    openRoles: $0["open_roles"].arrayValue.map { $0.stringValue },
                    possibleOpeners: $0["possible_openers"].arrayValue.map { $0.stringValue }
                )
            },
            conversationStarters: json["conversation_starters"].arrayValue.map { $0.stringValue },
            thingsToAvoid: json["things_to_avoid"].arrayValue.map { $0.stringValue }
        )
    }

    func parseDebriefOutcomes(_ response: String) throws -> DebriefOutcomesResult {
        let json = try extractAndParseJSON(from: response)

        return DebriefOutcomesResult(
            summary: json["summary"].stringValue,
            keyTakeaways: json["key_takeaways"].arrayValue.map { $0.stringValue },
            followUpActions: json["follow_up_actions"].arrayValue.map {
                DebriefFollowUpAction(
                    contactName: $0["contact_name"].stringValue,
                    action: $0["action"].stringValue,
                    deadline: $0["deadline"].stringValue,
                    priority: $0["priority"].stringValue
                )
            },
            opportunitiesIdentified: json["opportunities_identified"].arrayValue.map { $0.stringValue },
            nextSteps: json["next_steps"].arrayValue.map { $0.stringValue }
        )
    }

    func parseActions(_ response: String) throws -> NetworkingActionsResult {
        let json = try extractAndParseJSON(from: response)

        return NetworkingActionsResult(
            actions: json["actions"].arrayValue.map {
                NetworkingActionItem(
                    contactName: $0["contact_name"].stringValue,
                    contactId: $0["contact_id"].string,
                    actionType: $0["action_type"].stringValue,
                    actionDescription: $0["action_description"].stringValue,
                    urgency: $0["urgency"].stringValue,
                    suggestedOpener: $0["suggested_opener"].string
                )
            }
        )
    }

    func parseOutreach(_ response: String) throws -> OutreachMessageResult {
        let json = try extractAndParseJSON(from: response)

        return OutreachMessageResult(
            subject: json["subject"].string,
            message: json["message"].stringValue,
            notes: json["notes"].string
        )
    }

    func parseJobSelections(_ response: String) throws -> JobSelectionsResult {
        let json = try extractAndParseJSON(from: response)
        var selections: [JobSelection] = []

        for selectionJson in json["selections"].arrayValue {
            guard let jobId = UUID(uuidString: selectionJson["job_id"].stringValue) else {
                continue
            }
            let selection = JobSelection(
                jobId: jobId,
                company: selectionJson["company"].stringValue,
                role: selectionJson["role"].stringValue,
                matchScore: selectionJson["match_score"].doubleValue,
                reasoning: selectionJson["reasoning"].stringValue
            )
            selections.append(selection)
        }

        return JobSelectionsResult(
            selections: selections,
            overallAnalysis: json["overall_analysis"].stringValue,
            considerations: json["considerations"].arrayValue.map { $0.stringValue }
        )
    }

    // MARK: - JSON Extraction

    private func extractAndParseJSON(from response: String) throws -> JSON {
        guard let jsonString = extractJSON(from: response),
              let data = jsonString.data(using: .utf8) else {
            throw DiscoveryAgentError.invalidResponse
        }
        return try JSON(data: data)
    }

    private func extractJSON(from response: String) -> String? {
        // Try to find JSON in code blocks first
        if let jsonMatch = response.range(of: "```json\\s*(.+?)```", options: .regularExpression) {
            var extracted = String(response[jsonMatch])
            extracted = extracted.replacingOccurrences(of: "```json", with: "")
            extracted = extracted.replacingOccurrences(of: "```", with: "")
            return extracted.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Try to find raw JSON (starts with { or [)
        if let jsonStart = response.firstIndex(of: "{"),
           let jsonEnd = response.lastIndex(of: "}") {
            return String(response[jsonStart...jsonEnd])
        }

        if let jsonStart = response.firstIndex(of: "["),
           let jsonEnd = response.lastIndex(of: "]") {
            return String(response[jsonStart...jsonEnd])
        }

        return nil
    }
}
