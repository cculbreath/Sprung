//
//  DiscoveryAgentTypes.swift
//  Sprung
//
//  Result types and generated data structures for Discovery LLM responses.
//
//  Wire-key note: the job-selection and event-discovery contracts are
//  camelCase (keys we control; event discovery is pinned by the strict
//  submit_events tool schema in EventDiscoveryToolSchemas). The event-prep
//  and debrief DTOs keep snake_case CodingKeys because their contracts are
//  pinned by the corresponding prompt templates in Resources/Prompts. The
//  daily-task contract lives in DailyTaskGenerator.
//

import Foundation

// MARK: - Result Types

/// Payload of the strict `submit_events` completion tool (camelCase keys we
/// control — see EventDiscoveryToolSchemas.submitEventsSchema).
struct EventDiscoverySubmission: Codable {
    let events: [DiscoveredEvent]
}

/// One previously attended (or debriefed) event, fed to the event-discovery
/// agent as a taste signal — evidence of what the user actually shows up to.
/// Built most-recent-first by DiscoveryCoordinator; capped and formatted by
/// `DiscoveryAgentService.attendedHistoryContext`.
struct AttendedEventRecord {
    let name: String
    let eventType: String
    let organizer: String?
    /// User rating 1–5 (`EventRating.rawValue`) where the debrief recorded one.
    let rating: Int?
}

struct JobSelectionsResult: Codable {
    let selections: [JobSelection]
    let overallAnalysis: String
    let considerations: [String]
}

struct JobSelection: Codable {
    let jobId: UUID
    let company: String
    let role: String
    let matchScore: Double
    let reasoning: String
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

/// One page-verified networking event, as submitted by the discovery agent
/// through the strict `submit_events` tool. All keys camelCase; nullable
/// fields arrive as explicit JSON null under strict tool use.
struct DiscoveredEvent: Codable {
    let name: String
    let date: String
    let time: String?
    let location: String
    let format: String
    let organizer: String
    let url: String
    let eventType: String
    let cost: String?
    let estimatedAttendance: String?
    let relevanceReason: String

    /// The page-verified date, parsed. Nil for malformed dates —
    /// `parseCompletion` rejects submissions containing any, so a nil here
    /// after a successful loop indicates a programming error, not bad data.
    var parsedDate: Date? { Self.parseEventDate(date) }

    /// Nil when the date cannot be parsed — the caller drops the event rather
    /// than persisting one pinned to a fabricated date.
    func toNetworkingEventOpportunity() -> NetworkingEventOpportunity? {
        guard let parsedDate else {
            Logger.warning("Dropping discovered event with unparseable date '\(date)': \(name)", category: .ai)
            return nil
        }
        let event = NetworkingEventOpportunity()
        event.name = name
        event.date = parsedDate
        event.time = time
        event.location = location
        event.isVirtual = format == "virtual"
        event.url = url
        event.eventType = Self.parseEventType(eventType)
        event.organizer = organizer
        event.estimatedAttendance = Self.parseAttendanceSize(estimatedAttendance)
        event.cost = cost
        event.relevanceReason = relevanceReason
        event.discoveredVia = .webSearch
        return event
    }

    static func parseEventDate(_ dateString: String) -> Date? {
        // Primary contract: YYYY-MM-DD (pinned by the submit_events schema).
        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateOnlyFormatter.timeZone = TimeZone.current
        dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
        if let date = dateOnlyFormatter.date(from: dateString) {
            return date
        }
        // Tolerate a full ISO8601 timestamp.
        return ISO8601DateFormatter().date(from: dateString)
    }

    private static func parseEventType(_ type: String) -> NetworkingEventType {
        NetworkingEventType(rawValue: type.replacingOccurrences(of: "_", with: " ").capitalized) ?? .other
    }

    private static func parseAttendanceSize(_ size: String?) -> AttendanceSize {
        guard let size else { return .medium }
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
    case promptTemplateMissing(String)

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
        case .promptTemplateMissing(let name):
            return "A required prompt template (\(name)) is missing — the app may need to be reinstalled."
        }
    }
}
