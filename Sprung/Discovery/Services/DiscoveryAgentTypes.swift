//
//  DiscoveryAgentTypes.swift
//  Sprung
//
//  Result types and generated data structures for Discovery LLM responses.
//

import Foundation

// MARK: - Result Types

struct DailyTasksResult {
    let tasks: [GeneratedDailyTask]
}

struct JobSourcesResult {
    let sources: [GeneratedJobSource]
}

struct NetworkingEventsResult {
    let events: [GeneratedNetworkingEvent]
}

struct JobSelectionsResult {
    let selections: [JobSelection]
    let overallAnalysis: String
    let considerations: [String]
}

struct JobSelection {
    let jobId: UUID
    let company: String
    let role: String
    let matchScore: Double
    let reasoning: String
}

struct EventPrepResult {
    let goal: String
    let pitchScript: String
    let talkingPoints: [TalkingPointResult]
    let targetCompanies: [TargetCompanyResult]
    let conversationStarters: [String]
    let thingsToAvoid: [String]
}

struct DebriefOutcomesResult {
    let summary: String
    let keyTakeaways: [String]
    let followUpActions: [DebriefFollowUpAction]
    let opportunitiesIdentified: [String]
    let nextSteps: [String]
}

struct DebriefFollowUpAction {
    let contactName: String
    let action: String
    let deadline: String
    let priority: String
}

struct TalkingPointResult {
    let topic: String
    let relevance: String
    let yourAngle: String

    func toTalkingPoint() -> TalkingPoint {
        TalkingPoint(topic: topic, relevance: relevance, yourAngle: yourAngle)
    }
}

struct TargetCompanyResult {
    let company: String
    let whyRelevant: String
    let recentNews: String?
    let openRoles: [String]
    let possibleOpeners: [String]

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
    let relatedJobSourceId: String?
    let relatedJobAppId: String?
    let relatedContactId: String?
    let relatedEventId: String?
    let estimatedMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case taskType = "task_type"
        case title
        case description
        case priority
        case relatedJobSourceId = "related_job_source_id"
        case relatedJobAppId = "related_job_app_id"
        case relatedContactId = "related_contact_id"
        case relatedEventId = "related_event_id"
        case estimatedMinutes = "estimated_minutes"
    }

    func toDailyTask() -> DailyTask {
        let task = DailyTask()
        task.title = title
        task.taskDescription = description
        task.priority = priority
        task.estimatedMinutes = estimatedMinutes
        task.isLLMGenerated = true

        switch taskType.lowercased() {
        case "gather": task.taskType = .gatherLeads
        case "customize": task.taskType = .customizeMaterials
        case "apply": task.taskType = .submitApplication
        case "follow_up": task.taskType = .followUp
        case "networking": task.taskType = .networking
        case "event_prep": task.taskType = .eventPrep
        case "debrief": task.taskType = .eventDebrief
        default: task.taskType = .gatherLeads
        }

        if let sourceId = relatedJobSourceId, let uuid = UUID(uuidString: sourceId) {
            task.relatedJobSourceId = uuid
        }
        if let jobAppId = relatedJobAppId, let uuid = UUID(uuidString: jobAppId) {
            task.relatedJobAppId = uuid
        }
        if let contactId = relatedContactId, let uuid = UUID(uuidString: contactId) {
            task.relatedContactId = uuid
        }
        if let eventId = relatedEventId, let uuid = UUID(uuidString: eventId) {
            task.relatedEventId = uuid
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

struct GeneratedNetworkingEvent {
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
