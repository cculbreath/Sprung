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
        // Activate the timeline editor in the Timeline tab
        // The Timeline tab will auto-switch and show in editor mode
        await MainActor.run {
            coordinator.ui.isTimelineEditorActive = true
        }
        // Emit event for session persistence
        await coordinator.eventBus.publish(.timelineEditorActiveChanged(true))

        // Mark timeline enrichment objective as in_progress
        // This gates submit_for_validation(skeleton_timeline) - it can only be called after the editor is displayed
        await coordinator.eventBus.publish(.objectiveStatusUpdateRequested(
            id: OnboardingObjectiveId.timelineEnriched.rawValue,
            status: "in_progress",
            source: "display_timeline_tool",
            notes: "Timeline editor activated",
            details: nil
        ))

        // Return completed - the tool's job is to activate UI, which it has done
        // Timeline cards created afterward will appear in the Timeline tab automatically
        var response = JSON()
        response["message"].string = "Timeline editor activated. User can now edit cards in the Timeline tab. Call submit_for_validation(skeleton_timeline) when user clicks 'Done with Timeline'."
        response["status"].string = "completed"
        return .immediate(response)
    }
}
