//
//  EventDiscoveryToolSchemas.swift
//  Sprung
//
//  Tool definitions for the networking-event discovery agent loop:
//  Anthropic server-side web_search + web_fetch (executed on Anthropic's
//  infrastructure) plus the strict `submit_events` completion tool.
//  Input-schema keys are camelCase (keys we control); tool names stay
//  snake_case per the app-wide Anthropic tool naming convention.
//

import Foundation
import SwiftOpenAI

enum EventDiscoveryToolSchemas {
    // MARK: - Tool Names

    /// Completion tool: the agent submits its verified event list through this
    /// tool, which terminates the shared `AnthropicToolLoopRunner` loop.
    static let submitEventsToolName = "submit_events"

    // MARK: - Budgets

    /// Server-side web_search invocations per request. The loop runs about
    /// weekly, so depth is worth more than latency.
    static let webSearchMaxUses = 12

    /// Server-side web_fetch invocations per request — one per candidate page
    /// verified in Phase B. Generous on purpose: fetch budget is what caps how
    /// many candidates survive verification, and the loop only runs ~weekly.
    static let webFetchMaxUses = 25

    /// Token cap per fetched page. Event pages are small; verifying
    /// date/venue/format/registration never needs a whole conference site.
    static let webFetchMaxContentTokens = 8000

    // MARK: - Complete Tool Definitions

    /// All event-discovery tools: both server-side web tools plus the strict
    /// completion tool.
    static var allTools: [AnthropicTool] {
        [
            .serverTool(.webSearch(maxUses: webSearchMaxUses)),
            .serverTool(.webFetch(maxUses: webFetchMaxUses, maxContentTokens: webFetchMaxContentTokens)),
            .function(AnthropicFunctionTool(
                name: submitEventsToolName,
                description: """
                    Submit the final list of page-verified networking events. Call exactly once, \
                    when Phase B verification is complete. Every event must carry details verified \
                    by fetching its event page — never submit an event on a search snippet alone. \
                    Submit an empty list if nothing survived verification.
                    """,
                inputSchema: submitEventsSchema,
                strict: true
            ))
        ]
    }

    // MARK: - submit_events Schema (strict: every object closed, every property required)

    static var submitEventsSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "events": [
                    "type": "array",
                    "description": "Every event verified in Phase B. Empty if nothing survived verification.",
                    "items": eventSchema
                ]
            ],
            "required": ["events"],
            "additionalProperties": false
        ]
    }

    private static var eventSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "name": [
                    "type": "string",
                    "description": "Event name as shown on the event page"
                ],
                "date": [
                    "type": "string",
                    "description": "Page-verified event date, formatted YYYY-MM-DD"
                ],
                "time": [
                    "type": ["string", "null"],
                    "description": "Page-verified start time (e.g. \"6:00 PM\"); null if the page shows none"
                ],
                "location": [
                    "type": "string",
                    "description": "Venue and city, or \"Virtual\""
                ],
                "format": [
                    "type": "string",
                    "enum": ["in_person", "virtual", "hybrid"],
                    "description": "Page-verified format"
                ],
                "organizer": [
                    "type": "string",
                    "description": "Page-verified organizer"
                ],
                "url": [
                    "type": "string",
                    "description": "Registration or event-page URL that was fetched and verified"
                ],
                "eventType": [
                    "type": "string",
                    "enum": [
                        "meetup", "happy_hour", "conference", "workshop", "tech_talk",
                        "open_house", "career_fair", "panel_discussion", "hackathon",
                        "virtual_event", "coffee_chat", "other"
                    ],
                    "description": "Best-fit event category"
                ],
                "cost": [
                    "type": ["string", "null"],
                    "description": "\"Free\" or the page-listed cost; null if the page does not state one"
                ],
                "estimatedAttendance": [
                    "type": ["string", "null"],
                    "description": "One of: intimate, small, medium, large, massive; null if unknown"
                ],
                "relevanceReason": [
                    "type": "string",
                    "description": "One concrete sentence tying this event to the candidate's background. Plain language, no buzzwords."
                ]
            ],
            "required": [
                "name", "date", "time", "location", "format", "organizer",
                "url", "eventType", "cost", "estimatedAttendance", "relevanceReason"
            ],
            "additionalProperties": false
        ]
    }
}
