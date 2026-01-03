//
//  OpenDocumentCollectionTool.swift
//  Sprung
//
//  Tool that opens the document collection UI in Phase 2.
//  Part of the mandatory tool chain: start_phase_two → open_document_collection
//
import Foundation
import SwiftyJSON

/// Tool that opens the document collection UI for Phase 2 evidence gathering.
/// Displays the KC plan, large dropzone, and "Done with Uploads" button.
struct OpenDocumentCollectionTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: """
                Open the document collection UI for Phase 2 evidence gathering.

                MANDATORY TOOL CHAIN:
                1. start_phase_two → get timeline entries
                2. open_document_collection (THIS TOOL) → show dropzone for uploads

                This tool displays:
                - Large dropzone for file uploads
                - Git repository selector
                - "Done with Uploads" button

                After calling this tool, WAIT for the user to:
                - Upload documents (each file becomes a separate artifact)
                - Select git repositories for analysis
                - Click "Done with Uploads" when finished

                When user clicks "Done with Uploads":
                1. System automatically merges card inventories across all documents
                2. You receive a chat message with merged card summary and any documentation gaps
                3. User can review/exclude cards in the sidebar, then click "Approve & Create"
                4. Card generation is handled by the UI, not LLM tools
                """,
            properties: [
                "message": UserInteractionSchemas.documentCollectionMessage,
                "suggested_doc_types": UserInteractionSchemas.suggestedDocTypes
            ],
            required: [],
            additionalProperties: false
        )
    }()

    private unowned let coordinator: OnboardingInterviewCoordinator

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { OnboardingToolName.openDocumentCollection.rawValue }
    var description: String { "Open the document collection UI with dropzone and KC plan. Part of mandatory Phase 2 tool chain." }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        let message = params["message"].string
        // Activate document collection UI and gate all tools
        await coordinator.activateDocumentCollection()

        Logger.info("📂 Document collection UI activated", category: .ai)

        // Get artifact count from typed artifacts
        let artifactCount = await MainActor.run { coordinator.sessionArtifacts.count }
        let narrativeCardCount = await MainActor.run { coordinator.ui.aggregatedNarrativeCards.count }

        // Build minimal response
        var response = JSON()
        response["status"].string = "completed"
        response["ui_displayed"].bool = true
        response["artifact_count"].int = artifactCount
        response["narrative_card_count"].int = narrativeCardCount
        response["await_user_action"].string = "done_with_uploads"

        if let message = message {
            response["displayed_message"].string = message
        }

        return .immediate(response)
    }
}
