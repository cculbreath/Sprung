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

    static let discoverJobSourcesSchema = SchemaLoader.loadSchema(resourceName: "discover_job_sources")

    static let jobSourceOutputSchema = SchemaLoader.loadSchema(resourceName: "job_source_output")

    // MARK: - Generate Daily Tasks Tool

    static let generateDailyTasksSchema = SchemaLoader.loadSchema(resourceName: "generate_daily_tasks")

    static let dailyTaskOutputSchema = SchemaLoader.loadSchema(resourceName: "daily_task_output")

    // MARK: - Generate Weekly Reflection Tool

    static let generateWeeklyReflectionSchema = SchemaLoader.loadSchema(resourceName: "generate_weekly_reflection")

    // MARK: - Discover Networking Events Tool

    static let discoverNetworkingEventsSchema = SchemaLoader.loadSchema(resourceName: "discover_networking_events")

    static let networkingEventOutputSchema = SchemaLoader.loadSchema(resourceName: "networking_event_output")

    // MARK: - Evaluate Networking Event Tool

    static let evaluateNetworkingEventSchema = SchemaLoader.loadSchema(resourceName: "evaluate_networking_event")

    static let eventEvaluationOutputSchema = SchemaLoader.loadSchema(resourceName: "event_evaluation_output")

    // MARK: - Prepare For Event Tool

    static let prepareForEventSchema = SchemaLoader.loadSchema(resourceName: "prepare_for_event")

    static let eventPrepOutputSchema = SchemaLoader.loadSchema(resourceName: "event_prep_output")

    // MARK: - Suggest Networking Actions Tool

    static let suggestNetworkingActionsSchema = SchemaLoader.loadSchema(resourceName: "suggest_networking_actions")

    static let networkingActionOutputSchema = SchemaLoader.loadSchema(resourceName: "networking_action_output")

    // MARK: - Draft Outreach Message Tool

    static let draftOutreachMessageSchema = SchemaLoader.loadSchema(resourceName: "draft_outreach_message")

    static let outreachMessageOutputSchema = SchemaLoader.loadSchema(resourceName: "outreach_message_output")
}
