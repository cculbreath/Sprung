//
//  OpenDocumentCollectionTool.swift
//  Sprung
//
//  Tool that opens the document collection UI in Phase 2.
//  Part of the mandatory tool chain: start_phase_two → display_knowledge_card_plan → open_document_collection
//
import Foundation
import SwiftyJSON

/// Tool that opens the document collection UI for Phase 2 evidence gathering.
/// Displays the KC plan, large dropzone, and "Assess Completeness" button.
struct OpenDocumentCollectionTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: """
                Open the document collection UI for Phase 2 evidence gathering.

                MANDATORY TOOL CHAIN:
                1. start_phase_two → get timeline + existing artifacts
                2. display_knowledge_card_plan → show what cards will be generated
                3. open_document_collection (THIS TOOL) → show dropzone for uploads

                This tool displays:
                - List of planned knowledge cards
                - Large dropzone for file uploads
                - Git repository selector
                - "Assess Document Completeness" button

                After calling this tool, WAIT for the user to:
                - Upload documents (each file becomes a separate artifact)
                - Select git repositories for analysis
                - Click "Assess Completeness" when done

                The user's click on "Assess Completeness" sends a message to continue the conversation.
                You should then call propose_card_assignments to map artifacts to cards.
                """,
            properties: [
                "message": JSONSchema(
                    type: .string,
                    description: "Optional message to display to the user (e.g., suggestions for document types)"
                ),
                "suggested_doc_types": JSONSchema(
                    type: .array,
                    description: "List of suggested document types for the user to upload (shown as tags)",
                    items: JSONSchema(type: .string)
                )
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
        // Activate the document collection UI
        await MainActor.run {
            coordinator.ui.isDocumentCollectionActive = true
        }

        Logger.info("📂 Document collection UI activated", category: .ai)

        // Get counts from MainActor-isolated UI state
        let artifactCount = await MainActor.run { coordinator.ui.artifactRecords.count }
        let planCount = await MainActor.run { coordinator.ui.knowledgeCardPlan.count }

        // Build response
        var response = JSON()
        response["status"].string = "completed"
        response["ui_displayed"].bool = true
        response["artifact_count"].int = artifactCount
        response["kc_plan_count"].int = planCount

        // Provide clear instructions for next steps
        response["next_action"].string = """
            Document collection UI is now displayed. The user can:
            - Drag and drop files (PDFs, Word docs, images, text files)
            - Click "Browse Files" to select files
            - Click "Add Git Repo" to analyze code repositories
            - Click "Assess Document Completeness" when done uploading

            WAIT for the user to click "Assess Document Completeness" before proceeding.
            When they do, you will receive a chat message. Then call `propose_card_assignments`
            to map the uploaded artifacts to knowledge cards.
            """

        if let message = message {
            response["displayed_message"].string = message
        }

        return .immediate(response)
    }
}
