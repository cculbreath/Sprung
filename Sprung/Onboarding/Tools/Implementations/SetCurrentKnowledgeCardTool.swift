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
            "item_id": KnowledgeCardSchemas.itemId,
            "message": KnowledgeCardSchemas.message
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
        // Validate required parameters using helpers
        let itemId: String
        do {
            itemId = try ToolResultHelpers.requireString(params["item_id"].string, named: "item_id")
        } catch {
            return .error(error as! ToolError)
        }

        let message = params["message"].string

        // Get the current focus BEFORE updating (to determine if we need to gate)
        let previousFocus = await MainActor.run { coordinator.getCurrentPlanItemFocus() }
        let isNewItem = previousFocus != itemId

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
            return ToolResultHelpers.invalidParameters("No plan item found with id '\(itemId)'. Call display_knowledge_card_plan first.")
        }

        // Update UI state with new focus
        await coordinator.updateKnowledgeCardPlan(
            items: planItems,
            currentFocus: itemId,
            message: message ?? existingMessage
        )

        // Only gate submit_knowledge_card if switching to a DIFFERENT item.
        // This allows multiple cards from the same evidence batch without requiring "Done" for each.
        if isNewItem {
            await eventBus.publish(.toolGatingRequested(toolName: OnboardingToolName.submitKnowledgeCard.rawValue, exclude: true))
        }

        // Build additional data for response
        var additionalData = JSON()
        additionalData["current_item_id"].string = itemId
        additionalData["current_item_title"].string = item.title
        additionalData["ui_message"].string = "User now sees '\(item.title)' highlighted with 'Done with this card' button"

        if isNewItem {
            additionalData["tool_gating"].string = "submit_knowledge_card is GATED until user clicks 'Done with this card'"
            additionalData["next_action"].string = """
                The user can now:
                1. Upload documents via the drop zone
                2. Add a git repository
                3. Click "Done with this card" when ready for you to generate the card

                Ask for relevant documents for this item while waiting.
                IMPORTANT: You CANNOT call submit_knowledge_card until the user clicks "Done with this card".
                """
        } else {
            additionalData["tool_gating"].string = "submit_knowledge_card remains UNGATED (same item)"
            additionalData["next_action"].string = """
                Same item re-selected. You may continue submitting cards for this evidence batch.
                """
        }

        return ToolResultHelpers.statusResponse(
            status: "completed",
            additionalData: additionalData
        )
    }
}
