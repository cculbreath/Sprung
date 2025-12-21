//
//  SearchOpsToolNames.swift
//  Sprung
//
//  Canonical tool names for SearchOps LLM tools.
//

import Foundation

enum SearchOpsToolName: String, CaseIterable {
    // Source Discovery
    case discoverJobSources = "discover_job_sources"

    // Daily Operations
    case generateDailyTasks = "generate_daily_tasks"
    case generateWeeklyReflection = "generate_weekly_reflection"

    // Networking Events
    case discoverNetworkingEvents = "discover_networking_events"
    case evaluateNetworkingEvent = "evaluate_networking_event"
    case prepareForEvent = "prepare_for_event"
    case debriefEvent = "debrief_event"

    // Networking Actions
    case suggestNetworkingActions = "suggest_networking_actions"
    case draftOutreachMessage = "draft_outreach_message"

    var description: String {
        switch self {
        case .discoverJobSources:
            return "Generate relevant job sources based on candidate's target sectors and location"
        case .generateDailyTasks:
            return "Generate today's action items based on current job search state"
        case .generateWeeklyReflection:
            return "Generate insightful weekly reflection with actionable guidance"
        case .discoverNetworkingEvents:
            return "Search for upcoming networking events relevant to candidate's sectors"
        case .evaluateNetworkingEvent:
            return "Analyze an event and provide attendance recommendation"
        case .prepareForEvent:
            return "Generate comprehensive event preparation materials"
        case .debriefEvent:
            return "Process post-event debrief and generate follow-up actions"
        case .suggestNetworkingActions:
            return "Suggest actions to maintain and strengthen relationships"
        case .draftOutreachMessage:
            return "Generate personalized outreach message for a contact"
        }
    }
}
