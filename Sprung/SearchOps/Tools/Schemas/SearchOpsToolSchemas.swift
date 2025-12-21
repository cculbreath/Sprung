//
//  SearchOpsToolSchemas.swift
//  Sprung
//
//  JSON schemas for SearchOps LLM tools.
//

import Foundation
import SwiftOpenAI

enum SearchOpsToolSchemas {
    // MARK: - Discover Job Sources Tool

    static let discoverJobSourcesSchema = JSONSchema(
        type: .object,
        description: """
            Generate a list of job sources relevant to the candidate's target sectors and location. \
            Returns URLs for job boards, company career pages, and industry-specific resources.
            """,
        properties: [
            "sectors": JSONSchema(
                type: .array,
                description: "Target sectors to find sources for (e.g., 'Robotics', 'Aerospace', 'Semiconductors')",
                items: JSONSchema(type: .string)
            ),
            "location": JSONSchema(
                type: .string,
                description: "Primary location for job search (e.g., 'Austin, TX')"
            ),
            "include_remote": JSONSchema(
                type: .boolean,
                description: "Include remote job sources"
            ),
            "exclude_categories": JSONSchema(
                type: .array,
                description: "Categories to exclude (e.g., 'staffing')",
                items: JSONSchema(type: .string)
            )
        ],
        required: ["sectors", "location"],
        additionalProperties: false
    )

    static let jobSourceOutputSchema = JSONSchema(
        type: .object,
        properties: [
            "name": JSONSchema(type: .string, description: "Source name (e.g., 'Built In Austin')"),
            "url": JSONSchema(type: .string, description: "Source URL"),
            "category": JSONSchema(
                type: .string,
                description: "Category: 'local', 'industry', 'company_direct', 'aggregator', 'startup', 'staffing', 'networking'",
                enum: ["local", "industry", "company_direct", "aggregator", "startup", "staffing", "networking"]
            ),
            "relevance_reason": JSONSchema(type: .string, description: "Why this source is relevant"),
            "recommended_cadence_days": JSONSchema(type: .integer, description: "How often to check (days)")
        ],
        required: ["name", "url", "category", "relevance_reason"]
    )

    // MARK: - Generate Daily Tasks Tool

    static let generateDailyTasksSchema = JSONSchema(
        type: .object,
        description: """
            Generate today's action items based on the current state of the job search: \
            pending applications, follow-ups needed, sources due for checking, and networking tasks.
            """,
        properties: [
            "pending_applications": JSONSchema(
                type: .array,
                description: "Applications in progress that need attention",
                items: JSONSchema(
                    type: .object,
                    properties: [
                        "job_app_id": JSONSchema(type: .string),
                        "company": JSONSchema(type: .string),
                        "position": JSONSchema(type: .string),
                        "status": JSONSchema(type: .string)
                    ]
                )
            ),
            "due_sources": JSONSchema(
                type: .array,
                description: "Job sources that are due for checking",
                items: JSONSchema(
                    type: .object,
                    properties: [
                        "source_id": JSONSchema(type: .string),
                        "name": JSONSchema(type: .string),
                        "days_since_visit": JSONSchema(type: .integer)
                    ]
                )
            ),
            "follow_ups_needed": JSONSchema(
                type: .array,
                description: "Applications needing follow-up",
                items: JSONSchema(
                    type: .object,
                    properties: [
                        "job_app_id": JSONSchema(type: .string),
                        "company": JSONSchema(type: .string),
                        "days_since_applied": JSONSchema(type: .integer)
                    ]
                )
            ),
            "upcoming_events": JSONSchema(
                type: .array,
                description: "Networking events coming up",
                items: JSONSchema(
                    type: .object,
                    properties: [
                        "event_id": JSONSchema(type: .string),
                        "name": JSONSchema(type: .string),
                        "days_until": JSONSchema(type: .integer)
                    ]
                )
            ),
            "contacts_needing_attention": JSONSchema(
                type: .array,
                description: "Contacts with decaying relationships",
                items: JSONSchema(
                    type: .object,
                    properties: [
                        "contact_id": JSONSchema(type: .string),
                        "name": JSONSchema(type: .string),
                        "days_since_contact": JSONSchema(type: .integer)
                    ]
                )
            ),
            "weekly_progress": JSONSchema(
                type: .object,
                description: "Progress toward weekly goals",
                properties: [
                    "applications_target": JSONSchema(type: .integer),
                    "applications_actual": JSONSchema(type: .integer),
                    "networking_events_target": JSONSchema(type: .integer),
                    "networking_events_actual": JSONSchema(type: .integer)
                ]
            )
        ],
        required: ["pending_applications", "due_sources", "follow_ups_needed"]
    )

    static let dailyTaskOutputSchema = JSONSchema(
        type: .object,
        properties: [
            "task_type": JSONSchema(
                type: .string,
                description: "Task type",
                enum: ["gather", "customize", "apply", "follow_up", "networking", "event_prep", "debrief"]
            ),
            "title": JSONSchema(type: .string, description: "Short task title"),
            "description": JSONSchema(type: .string, description: "Task description"),
            "priority": JSONSchema(type: .integer, description: "Priority (0=low, 1=medium, 2=high)"),
            "related_job_source_id": JSONSchema(type: .string, description: "Related source ID if applicable"),
            "related_job_app_id": JSONSchema(type: .string, description: "Related application ID if applicable"),
            "related_contact_id": JSONSchema(type: .string, description: "Related contact ID if applicable"),
            "related_event_id": JSONSchema(type: .string, description: "Related event ID if applicable"),
            "estimated_minutes": JSONSchema(type: .integer, description: "Estimated time in minutes")
        ],
        required: ["task_type", "title", "priority"]
    )

    // MARK: - Generate Weekly Reflection Tool

    static let generateWeeklyReflectionSchema = JSONSchema(
        type: .object,
        description: """
            Generate an insightful weekly reflection based on the week's job search activities, \
            progress toward goals, and outcomes. Provide actionable guidance for the next week.
            """,
        properties: [
            "week_start": JSONSchema(type: .string, description: "Week start date (ISO format)"),
            "applications_submitted": JSONSchema(type: .integer),
            "applications_target": JSONSchema(type: .integer),
            "events_attended": JSONSchema(type: .integer),
            "events_target": JSONSchema(type: .integer),
            "new_contacts": JSONSchema(type: .integer),
            "contacts_target": JSONSchema(type: .integer),
            "follow_ups_sent": JSONSchema(type: .integer),
            "follow_ups_target": JSONSchema(type: .integer),
            "time_spent_minutes": JSONSchema(type: .integer),
            "notable_outcomes": JSONSchema(
                type: .array,
                description: "Notable events like interviews, referrals, responses",
                items: JSONSchema(type: .string)
            ),
            "sources_used": JSONSchema(
                type: .array,
                description: "Job sources used this week with visit counts",
                items: JSONSchema(
                    type: .object,
                    properties: [
                        "name": JSONSchema(type: .string),
                        "visits": JSONSchema(type: .integer),
                        "leads_captured": JSONSchema(type: .integer)
                    ]
                )
            )
        ],
        required: ["week_start", "applications_submitted", "applications_target"]
    )

    // MARK: - Discover Networking Events Tool

    static let discoverNetworkingEventsSchema = JSONSchema(
        type: .object,
        description: """
            Search the web for upcoming networking events, meetups, conferences, \
            and professional gatherings relevant to candidate's target sectors and location.
            """,
        properties: [
            "sectors": JSONSchema(
                type: .array,
                description: "Target sectors to find events for",
                items: JSONSchema(type: .string)
            ),
            "location": JSONSchema(
                type: .string,
                description: "Location for local events"
            ),
            "days_ahead": JSONSchema(
                type: .integer,
                description: "How many days ahead to search (default: 14)"
            ),
            "include_virtual": JSONSchema(
                type: .boolean,
                description: "Include virtual events (default: true)"
            ),
            "exclude_event_types": JSONSchema(
                type: .array,
                description: "Event types to exclude (e.g., 'career_fair')",
                items: JSONSchema(type: .string)
            )
        ],
        required: ["sectors", "location"]
    )

    static let networkingEventOutputSchema = JSONSchema(
        type: .object,
        properties: [
            "name": JSONSchema(type: .string, description: "Event name"),
            "description": JSONSchema(type: .string, description: "Event description"),
            "date": JSONSchema(type: .string, description: "Event date (ISO format)"),
            "time": JSONSchema(type: .string, description: "Start time"),
            "location": JSONSchema(type: .string, description: "Venue name or 'Virtual'"),
            "is_virtual": JSONSchema(type: .boolean),
            "url": JSONSchema(type: .string, description: "Event page URL"),
            "organizer": JSONSchema(type: .string, description: "Organizing group/company"),
            "event_type": JSONSchema(
                type: .string,
                enum: ["meetup", "happy_hour", "conference", "workshop", "tech_talk",
                             "open_house", "career_fair", "panel_discussion", "hackathon",
                             "virtual_event", "coffee_chat", "other"]
            ),
            "estimated_attendance": JSONSchema(
                type: .string,
                enum: ["intimate", "small", "medium", "large", "massive"]
            ),
            "cost": JSONSchema(type: .string, description: "Cost (e.g., 'Free', '$25')"),
            "relevance_reason": JSONSchema(type: .string, description: "Why this event is relevant"),
            "target_companies_likely": JSONSchema(
                type: .array,
                description: "Companies likely to have attendees",
                items: JSONSchema(type: .string)
            )
        ],
        required: ["name", "date", "location", "url", "event_type", "relevance_reason"]
    )

    // MARK: - Evaluate Networking Event Tool

    static let evaluateNetworkingEventSchema = JSONSchema(
        type: .object,
        description: """
            Analyze a networking event and provide attendance recommendation with rationale.
            """,
        properties: [
            "event": JSONSchema(
                type: .object,
                description: "Event details to evaluate",
                properties: [
                    "name": JSONSchema(type: .string),
                    "description": JSONSchema(type: .string),
                    "date": JSONSchema(type: .string),
                    "location": JSONSchema(type: .string),
                    "event_type": JSONSchema(type: .string),
                    "estimated_attendance": JSONSchema(type: .string),
                    "organizer": JSONSchema(type: .string),
                    "cost": JSONSchema(type: .string),
                    "target_companies_likely": JSONSchema(type: .array, items: JSONSchema(type: .string))
                ]
            ),
            "candidate_sectors": JSONSchema(type: .array, items: JSONSchema(type: .string)),
            "target_companies": JSONSchema(type: .array, items: JSONSchema(type: .string)),
            "past_event_feedback": JSONSchema(
                type: .array,
                description: "Aggregated feedback from similar events",
                items: JSONSchema(
                    type: .object,
                    properties: [
                        "event_type": JSONSchema(type: .string),
                        "organizer": JSONSchema(type: .string),
                        "average_rating": JSONSchema(type: .number),
                        "average_contacts_made": JSONSchema(type: .number)
                    ]
                )
            ),
            "calendar_conflict": JSONSchema(type: .boolean),
            "conflict_description": JSONSchema(type: .string)
        ],
        required: ["event", "candidate_sectors"]
    )

    static let eventEvaluationOutputSchema = JSONSchema(
        type: .object,
        properties: [
            "recommendation": JSONSchema(
                type: .string,
                enum: ["strong_yes", "yes", "maybe", "skip"]
            ),
            "confidence_score": JSONSchema(type: .number, description: "0.0-1.0"),
            "rationale": JSONSchema(type: .string),
            "expected_value": JSONSchema(type: .string, description: "What you might gain"),
            "concerns": JSONSchema(type: .array, items: JSONSchema(type: .string)),
            "suggested_goal": JSONSchema(type: .string, description: "Specific goal for attending"),
            "preparation_needed": JSONSchema(type: .string)
        ],
        required: ["recommendation", "rationale", "expected_value"]
    )

    // MARK: - Prepare For Event Tool

    static let prepareForEventSchema = JSONSchema(
        type: .object,
        description: """
            Generate comprehensive preparation materials for an upcoming networking event.
            """,
        properties: [
            "event_name": JSONSchema(type: .string),
            "event_type": JSONSchema(type: .string),
            "event_description": JSONSchema(type: .string),
            "expected_attendees": JSONSchema(type: .string, description: "Who typically attends"),
            "candidate_background": JSONSchema(type: .string, description: "Candidate's professional summary"),
            "target_companies": JSONSchema(type: .array, items: JSONSchema(type: .string)),
            "candidate_sectors": JSONSchema(type: .array, items: JSONSchema(type: .string))
        ],
        required: ["event_name", "event_type", "candidate_background"]
    )

    static let eventPrepOutputSchema = JSONSchema(
        type: .object,
        properties: [
            "suggested_goal": JSONSchema(type: .string, description: "Specific, measurable goal"),
            "pitch_30_seconds": JSONSchema(type: .string, description: "30-second intro pitch"),
            "pitch_60_seconds": JSONSchema(type: .string, description: "60-second detailed pitch"),
            "talking_points": JSONSchema(
                type: .array,
                items: JSONSchema(
                    type: .object,
                    properties: [
                        "topic": JSONSchema(type: .string),
                        "relevance": JSONSchema(type: .string),
                        "your_angle": JSONSchema(type: .string),
                        "transition_phrase": JSONSchema(type: .string)
                    ]
                )
            ),
            "target_company_context": JSONSchema(
                type: .array,
                items: JSONSchema(
                    type: .object,
                    properties: [
                        "company": JSONSchema(type: .string),
                        "why_relevant": JSONSchema(type: .string),
                        "recent_news": JSONSchema(type: .string),
                        "currently_hiring": JSONSchema(type: .array, items: JSONSchema(type: .string)),
                        "possible_openers": JSONSchema(type: .array, items: JSONSchema(type: .string))
                    ]
                )
            ),
            "conversation_starters": JSONSchema(type: .array, items: JSONSchema(type: .string)),
            "questions_to_ask": JSONSchema(type: .array, items: JSONSchema(type: .string)),
            "things_to_avoid": JSONSchema(type: .array, items: JSONSchema(type: .string)),
            "logistics_notes": JSONSchema(type: .string)
        ],
        required: ["suggested_goal", "pitch_30_seconds", "conversation_starters"]
    )

    // MARK: - Suggest Networking Actions Tool

    static let suggestNetworkingActionsSchema = JSONSchema(
        type: .object,
        description: """
            Analyze network health and suggest specific actions to maintain and strengthen relationships.
            """,
        properties: [
            "contacts": JSONSchema(
                type: .array,
                description: "Current contacts with relationship status",
                items: JSONSchema(
                    type: .object,
                    properties: [
                        "contact_id": JSONSchema(type: .string),
                        "name": JSONSchema(type: .string),
                        "company": JSONSchema(type: .string),
                        "warmth": JSONSchema(type: .string, enum: ["hot", "warm", "cold", "dormant"]),
                        "days_since_contact": JSONSchema(type: .integer),
                        "has_offered_help": JSONSchema(type: .boolean),
                        "is_at_target_company": JSONSchema(type: .boolean)
                    ]
                )
            ),
            "target_companies": JSONSchema(type: .array, items: JSONSchema(type: .string)),
            "upcoming_events": JSONSchema(
                type: .array,
                items: JSONSchema(
                    type: .object,
                    properties: [
                        "event_id": JSONSchema(type: .string),
                        "name": JSONSchema(type: .string),
                        "date": JSONSchema(type: .string)
                    ]
                )
            )
        ],
        required: ["contacts"]
    )

    static let networkingActionOutputSchema = JSONSchema(
        type: .object,
        properties: [
            "contact_id": JSONSchema(type: .string),
            "contact_name": JSONSchema(type: .string),
            "action_type": JSONSchema(
                type: .string,
                enum: ["reconnect", "follow_up", "congratulate", "share_content",
                             "ask_for_intro", "offer_help", "check_in"]
            ),
            "suggestion": JSONSchema(type: .string, description: "What to do"),
            "rationale": JSONSchema(type: .string, description: "Why this action"),
            "draft_message": JSONSchema(type: .string, description: "Optional message draft"),
            "priority": JSONSchema(type: .string, enum: ["urgent", "high", "medium", "low"]),
            "estimated_time_minutes": JSONSchema(type: .integer)
        ],
        required: ["contact_id", "contact_name", "action_type", "suggestion", "priority"]
    )

    // MARK: - Draft Outreach Message Tool

    static let draftOutreachMessageSchema = JSONSchema(
        type: .object,
        description: """
            Generate a personalized outreach message for a networking contact.
            """,
        properties: [
            "contact_name": JSONSchema(type: .string),
            "contact_company": JSONSchema(type: .string),
            "contact_title": JSONSchema(type: .string),
            "relationship_context": JSONSchema(type: .string, description: "How you know them"),
            "message_type": JSONSchema(
                type: .string,
                enum: ["linkedin_connection", "follow_up", "thank_you",
                             "ask_for_intro", "check_in", "congratulate", "share_content"]
            ),
            "desired_outcome": JSONSchema(type: .string, description: "What you want from this"),
            "additional_context": JSONSchema(type: .string, description: "Any extra context to include")
        ],
        required: ["contact_name", "message_type"]
    )

    static let outreachMessageOutputSchema = JSONSchema(
        type: .object,
        properties: [
            "subject": JSONSchema(type: .string, description: "Email subject (if applicable)"),
            "message": JSONSchema(type: .string, description: "The message body"),
            "alternative_versions": JSONSchema(
                type: .array,
                description: "Alternative message options",
                items: JSONSchema(type: .string)
            ),
            "sending_tips": JSONSchema(type: .string, description: "Tips for effective sending")
        ],
        required: ["message"]
    )
}
