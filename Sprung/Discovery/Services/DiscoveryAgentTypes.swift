//
//  DiscoveryAgentTypes.swift
//  Sprung
//
//  Result types and generated data structures for Discovery LLM responses.
//

import Foundation

// MARK: - Result Types

struct DailyTasksResult: Codable {
    let tasks: [GeneratedDailyTask]
}

struct JobSourcesResult: Codable {
    let sources: [GeneratedJobSource]
}

struct NetworkingEventsResult: Codable {
    let events: [GeneratedNetworkingEvent]
}

struct JobSelectionsResult: Codable {
    let selections: [JobSelection]
    let overallAnalysis: String
    let considerations: [String]

    enum CodingKeys: String, CodingKey {
        case selections
        case overallAnalysis = "overall_analysis"
        case considerations
    }
}

struct JobSelection: Codable {
    let jobId: UUID
    let company: String
    let role: String
    let matchScore: Double
    let reasoning: String

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case company, role
        case matchScore = "match_score"
        case reasoning
    }
}

struct EventPrepResult: Codable {
    let goal: String
    let pitchScript: String
    let talkingPoints: [TalkingPointResult]
    let targetCompanies: [TargetCompanyResult]
    let conversationStarters: [String]
    let thingsToAvoid: [String]

    enum CodingKeys: String, CodingKey {
        case goal
        case pitchScript = "pitch_script"
        case talkingPoints = "talking_points"
        case targetCompanies = "target_companies"
        case conversationStarters = "conversation_starters"
        case thingsToAvoid = "things_to_avoid"
    }
}

struct DebriefOutcomesResult: Codable {
    let summary: String
    let keyTakeaways: [String]
    let followUpActions: [DebriefFollowUpAction]
    let opportunitiesIdentified: [String]
    let nextSteps: [String]

    enum CodingKeys: String, CodingKey {
        case summary
        case keyTakeaways = "key_takeaways"
        case followUpActions = "follow_up_actions"
        case opportunitiesIdentified = "opportunities_identified"
        case nextSteps = "next_steps"
    }
}

struct DebriefFollowUpAction: Codable {
    let contactName: String
    let action: String
    let deadline: String
    let priority: String

    enum CodingKeys: String, CodingKey {
        case contactName = "contact_name"
        case action, deadline, priority
    }
}

struct TalkingPointResult: Codable {
    let topic: String
    let relevance: String
    let yourAngle: String

    enum CodingKeys: String, CodingKey {
        case topic, relevance
        case yourAngle = "your_angle"
    }

    func toTalkingPoint() -> TalkingPoint {
        TalkingPoint(topic: topic, relevance: relevance, yourAngle: yourAngle)
    }
}

struct TargetCompanyResult: Codable {
    let company: String
    let whyRelevant: String
    let recentNews: String?
    let openRoles: [String]
    let possibleOpeners: [String]

    enum CodingKeys: String, CodingKey {
        case company
        case whyRelevant = "why_relevant"
        case recentNews = "recent_news"
        case openRoles = "open_roles"
        case possibleOpeners = "possible_openers"
    }

    func toTargetCompanyContext() -> TargetCompanyContext {
        TargetCompanyContext(
            company: company,
            whyRelevant: whyRelevant,
            recentNews: recentNews,
            openRoles: openRoles,
            possibleOpeners: possibleOpeners
        )
    }
}

// MARK: - Generated Types (from LLM responses)

struct GeneratedDailyTask: Codable {
    let taskType: String
    let title: String
    let description: String?
    let priority: Int
    let relatedId: String?
    let estimatedMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case taskType = "task_type"
        case title
        case description
        case priority
        case relatedId = "related_id"
        case estimatedMinutes = "estimated_minutes"
    }

    func toDailyTask() -> DailyTask {
        let task = DailyTask()
        task.title = title
        task.taskDescription = description
        task.priority = priority
        task.estimatedMinutes = estimatedMinutes
        task.isLLMGenerated = true

        let dailyTaskType: DailyTaskType
        switch taskType.lowercased() {
        case "gather": dailyTaskType = .gatherLeads
        case "customize": dailyTaskType = .customizeMaterials
        case "apply": dailyTaskType = .submitApplication
        case "follow_up": dailyTaskType = .followUp
        case "networking": dailyTaskType = .networking
        case "event_prep": dailyTaskType = .eventPrep
        case "debrief": dailyTaskType = .eventDebrief
        default: dailyTaskType = .gatherLeads
        }
        task.taskType = dailyTaskType

        if let relatedId = relatedId, let uuid = UUID(uuidString: relatedId) {
            switch dailyTaskType {
            case .gatherLeads:
                task.relatedJobSourceId = uuid
            case .customizeMaterials, .submitApplication, .followUp:
                task.relatedJobAppId = uuid
            case .networking:
                task.relatedContactId = uuid
            case .eventPrep, .eventDebrief:
                task.relatedEventId = uuid
            }
        }

        return task
    }
}

struct GeneratedJobSource: Codable {
    let name: String
    let url: String
    let category: String
    let relevanceReason: String
    let recommendedCadenceDays: Int?

    enum CodingKeys: String, CodingKey {
        case name, url, category
        case relevanceReason = "relevance_reason"
        case recommendedCadenceDays = "recommended_cadence_days"
    }

    func toJobSource() -> JobSource {
        let source = JobSource()
        source.name = name
        source.url = url
        source.notes = relevanceReason
        source.isLLMGenerated = true

        switch category.lowercased() {
        case "local": source.category = .local
        case "industry": source.category = .industry
        case "company_direct": source.category = .companyDirect
        case "aggregator": source.category = .aggregator
        case "startup": source.category = .startup
        case "staffing": source.category = .staffing
        case "networking": source.category = .networking
        default: source.category = .aggregator
        }

        if let days = recommendedCadenceDays {
            source.recommendedCadenceDays = days
        } else {
            source.recommendedCadenceDays = source.category.defaultCadenceDays
        }

        return source
    }
}

struct GeneratedNetworkingEvent: Codable {
    let name: String
    let date: String
    let time: String?
    let location: String
    let url: String
    let eventType: String
    let organizer: String?
    let estimatedAttendance: String?
    let cost: String?
    let relevanceReason: String?

    enum CodingKeys: String, CodingKey {
        case name, date, time, location, url
        case eventType = "event_type"
        case organizer
        case estimatedAttendance = "estimated_attendance"
        case cost
        case relevanceReason = "relevance_reason"
    }

    func toNetworkingEventOpportunity() -> NetworkingEventOpportunity {
        let event = NetworkingEventOpportunity()
        event.name = name
        event.date = parseEventDate(date) ?? Date()
        event.time = time
        event.location = location
        event.url = url
        event.eventType = parseEventType(eventType)
        event.organizer = organizer
        event.estimatedAttendance = parseAttendanceSize(estimatedAttendance)
        event.cost = cost
        event.relevanceReason = relevanceReason
        event.discoveredVia = .webSearch
        return event
    }

    private func parseEventDate(_ dateString: String) -> Date? {
        let iso8601Formatter = ISO8601DateFormatter()
        if let date = iso8601Formatter.date(from: dateString) {
            return date
        }

        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.timeZone = TimeZone.current

        // Try date-only format (YYYY-MM-DD)
        dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
        if let date = dateOnlyFormatter.date(from: dateString) {
            return date
        }

        // Try common US format (MM/DD/YYYY)
        dateOnlyFormatter.dateFormat = "MM/dd/yyyy"
        if let date = dateOnlyFormatter.date(from: dateString) {
            return date
        }

        // Try natural language formats (e.g., "January 6, 2026")
        dateOnlyFormatter.dateFormat = "MMMM d, yyyy"
        if let date = dateOnlyFormatter.date(from: dateString) {
            return date
        }

        Logger.warning("Could not parse event date: \(dateString)", category: .ai)
        return nil
    }

    private func parseEventType(_ type: String) -> NetworkingEventType {
        NetworkingEventType(rawValue: type.replacingOccurrences(of: "_", with: " ").capitalized) ?? .meetup
    }

    private func parseAttendanceSize(_ size: String?) -> AttendanceSize {
        guard let size = size else { return .medium }
        switch size.lowercased() {
        case "intimate": return .intimate
        case "small": return .small
        case "medium": return .medium
        case "large": return .large
        case "massive": return .massive
        default: return .medium
        }
    }
}

// MARK: - Errors

enum DiscoveryAgentError: Error, LocalizedError {
    case noResponse
    case toolLoopExceeded
    case invalidResponse
    case toolExecutionFailed(String)
    case llmError(String)

    var errorDescription: String? {
        switch self {
        case .noResponse:
            return "No response from LLM"
        case .toolLoopExceeded:
            return "Tool call loop exceeded maximum iterations"
        case .invalidResponse:
            return "Could not parse LLM response"
        case .toolExecutionFailed(let reason):
            return "Tool execution failed: \(reason)"
        case .llmError(let reason):
            return "LLM error: \(reason)"
        }
    }
}
