//
//  DisplayTimelineForReviewTool.swift
//  Sprung
//
//  Convenience tool to display the current skeleton timeline for user review.
//
import Foundation
import SwiftyJSON
import SwiftOpenAI
struct DisplayTimelineForReviewTool: InterviewTool {
    private static let schema: JSONSchema = {
        let properties: [String: JSONSchema] = [
            "summary": ValidationSchemas.timelineReviewSummary
        ]
        return JSONSchema(
            type: .object,
            description: "Activate timeline EDITOR UI. Call before create_timeline_card. Use submit_for_validation for final approval.",
            properties: properties,
            required: [],
            additionalProperties: false
        )
    }()
    private unowned let coordinator: OnboardingInterviewCoordinator
    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }
    var name: String { OnboardingToolName.displayTimelineEntriesForReview.rawValue }
    var description: String { "Activate timeline EDITOR UI before creating cards. User can edit/save changes. NOT final approval - use submit_for_validation afterward." }
    var parameters: JSONSchema { Self.schema }
    func execute(_ params: JSON) async throws -> ToolResult {
        // Get current timeline from coordinator (may be nil or empty - that's OK!)
        let timelineJSON = await coordinator.state.artifacts.skeletonTimeline ?? JSON()
        // Get optional summary message
        let summary = params["summary"].string ?? "Timeline review activated. Cards will appear here as you create them."
        // Build editor prompt - even if timeline is empty, we activate the UI
        // Cards created afterward will appear in this UI in real-time
        let validationPrompt = OnboardingValidationPrompt(
            dataType: "skeleton_timeline",
            payload: timelineJSON,
            message: summary,
            mode: .editor  // Editor mode: allows tools, shows Save button
        )
        // Emit UI request to show the validation prompt
        await coordinator.eventBus.publish(.validationPromptRequested(prompt: validationPrompt))
        // Return completed - the tool's job is to activate UI, which it has done
        // Timeline cards created afterward will appear in this UI automatically
        var response = JSON()
        response["message"].string = "Timeline review UI activated. Cards will appear as you create them."
        response["status"].string = "completed"
        return .immediate(response)
    }
}
