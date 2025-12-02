import Foundation
import SwiftyJSON

/// Tool that sets the currently focused knowledge card item.
/// Called after display_knowledge_card_plan to indicate which card is being worked on.
/// This enables the "Done with this card" button in the UI.
struct SetCurrentKnowledgeCardTool: InterviewTool {
    private static let schema = JSONSchema(
        type: .object,
        description: """
            Set the current knowledge card being worked on.

            Call this AFTER `display_knowledge_card_plan` to indicate which item you're actively collecting info for.
            This enables the "Done with this card" button in the UI.

            The item's status will automatically be set to "in_progress".
            """,
        properties: [
            "item_id": JSONSchema(
                type: .string,
                description: "The ID of the plan item to mark as current (must match an ID from display_knowledge_card_plan)"
            ),
            "message": JSONSchema(
                type: .string,
                description: "Optional message to display (e.g., 'Let's start with your role at Company X')"
            )
        ],
        required: ["item_id"],
        additionalProperties: false
    )

    private unowned let coordinator: OnboardingInterviewCoordinator
    private let eventBus: EventCoordinator

    init(coordinator: OnboardingInterviewCoordinator, eventBus: EventCoordinator) {
        self.coordinator = coordinator
        self.eventBus = eventBus
    }

    var name: String { OnboardingToolName.setCurrentKnowledgeCard.rawValue }
    var description: String { "Set which knowledge card is currently being worked on. Enables the 'Done' button in UI." }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        guard let itemId = params["item_id"].string, !itemId.isEmpty else {
            return .error(.invalidParameters("item_id is required"))
        }

        let message = params["message"].string

        // Get current plan items (must access MainActor-isolated properties)
        let (planItems, existingMessage, item) = await MainActor.run {
            var items = coordinator.ui.knowledgeCardPlan
            let existingMsg = coordinator.ui.knowledgeCardPlanMessage

            // Find and update the target item's status
            guard let itemIndex = items.firstIndex(where: { $0.id == itemId }) else {
                return (items, existingMsg, nil as KnowledgeCardPlanItem?)
            }

            // Update the item's status to in_progress
            let targetItem = items[itemIndex]
            items[itemIndex] = KnowledgeCardPlanItem(
                id: targetItem.id,
                title: targetItem.title,
                type: targetItem.type,
                description: targetItem.description,
                status: .inProgress,
                timelineEntryId: targetItem.timelineEntryId
            )
            return (items, existingMsg, targetItem)
        }

        guard let item = item else {
            return .error(.invalidParameters("No plan item found with id '\(itemId)'. Call display_knowledge_card_plan first."))
        }

        // Update UI state with new focus
        await coordinator.updateKnowledgeCardPlan(
            items: planItems,
            currentFocus: itemId,
            message: message ?? existingMessage
        )

        // Gate submit_knowledge_card until user clicks "Done with this card"
        await eventBus.publish(.toolGatingRequested(toolName: OnboardingToolName.submitKnowledgeCard.rawValue, exclude: true))

        // Build response
        var response = JSON()
        response["status"].string = "completed"
        response["current_item_id"].string = itemId
        response["current_item_title"].string = item.title
        response["ui_message"].string = "User now sees '\(item.title)' highlighted with 'Done with this card' button"
        response["tool_gating"].string = "submit_knowledge_card is GATED until user clicks 'Done with this card'"
        response["next_action"].string = """
            The user can now:
            1. Upload documents via the drop zone
            2. Add a git repository
            3. Click "Done with this card" when ready for you to generate the card

            Ask for relevant documents for this item while waiting.
            IMPORTANT: You CANNOT call submit_knowledge_card until the user clicks "Done with this card".
            """

        return .immediate(response)
    }
}
