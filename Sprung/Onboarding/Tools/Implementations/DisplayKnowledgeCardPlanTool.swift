import Foundation
import SwiftyJSON

/// Tool that displays the LLM's knowledge card generation plan as a visible checklist.
/// The LLM calls this to show the user what cards will be generated and track progress.
struct DisplayKnowledgeCardPlanTool: InterviewTool {
    private static let schema: JSONSchema = {
        let itemSchema = JSONSchema(
            type: .object,
            description: "A planned knowledge card item",
            properties: [
                "id": JSONSchema(type: .string, description: "Unique identifier for this item"),
                "title": JSONSchema(type: .string, description: "Title of the knowledge card (e.g., job title or skill area)"),
                "type": JSONSchema(
                    type: .string,
                    description: "Type of card: 'job' for positions, 'skill' for skill areas",
                    enum: ["job", "skill"]
                ),
                "description": JSONSchema(type: .string, description: "Brief description of what this card will cover"),
                "status": JSONSchema(
                    type: .string,
                    description: "Current status of this item",
                    enum: ["pending", "in_progress", "completed", "skipped"]
                ),
                "timeline_entry_id": JSONSchema(type: .string, description: "Optional: ID of the related timeline entry")
            ],
            required: ["id", "title", "type", "status"],
            additionalProperties: false
        )

        return JSONSchema(
            type: .object,
            description: """
                Display or update the knowledge card generation plan.

                WORKFLOW:
                1. At Phase 2 start, analyze skeleton_timeline and call this tool with your full plan
                2. Before working on an item, call again with that item's status set to "in_progress"
                3. After completing a card, call again with that item's status set to "completed"

                The plan is displayed to the user as a checklist they can follow along with.
                """,
            properties: [
                "items": JSONSchema(
                    type: .array,
                    description: "The complete list of planned knowledge cards with current status",
                    items: itemSchema
                ),
                "current_focus": JSONSchema(
                    type: .string,
                    description: "ID of the item currently being worked on (for highlighting)"
                ),
                "message": JSONSchema(
                    type: .string,
                    description: "Optional message to display with the plan (e.g., 'Starting with your role at Company X')"
                )
            ],
            required: ["items"],
            additionalProperties: false
        )
    }()

    private unowned let coordinator: OnboardingInterviewCoordinator

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { OnboardingToolName.displayKnowledgeCardPlan.rawValue }
    var description: String { "Display the knowledge card generation plan as a checklist. Call to show initial plan, then update as you complete each card." }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        let items = params["items"].arrayValue
        let currentFocus = params["current_focus"].string
        let message = params["message"].string

        guard !items.isEmpty else {
            return .error(.invalidParameters("items array is required and must not be empty"))
        }

        // Build plan items
        var planItems: [KnowledgeCardPlanItem] = []
        for item in items {
            guard let id = item["id"].string,
                  let title = item["title"].string,
                  let typeStr = item["type"].string,
                  let statusStr = item["status"].string else {
                continue
            }

            let itemType = KnowledgeCardPlanItem.ItemType(rawValue: typeStr) ?? .job
            let status = KnowledgeCardPlanItem.Status(rawValue: statusStr) ?? .pending

            planItems.append(KnowledgeCardPlanItem(
                id: id,
                title: title,
                type: itemType,
                description: item["description"].string,
                status: status,
                timelineEntryId: item["timeline_entry_id"].string
            ))
        }

        // Update the UI state with the plan
        await coordinator.updateKnowledgeCardPlan(
            items: planItems,
            currentFocus: currentFocus,
            message: message
        )

        // Build response
        var response = JSON()
        response["status"].string = "completed"
        response["item_count"].int = planItems.count
        response["pending_count"].int = planItems.filter { $0.status == .pending }.count
        response["in_progress_count"].int = planItems.filter { $0.status == .inProgress }.count
        response["completed_count"].int = planItems.filter { $0.status == .completed }.count

        if let currentFocus = currentFocus {
            response["current_focus"].string = currentFocus
        }

        // Determine next action based on plan state
        let hasInProgress = planItems.contains { $0.status == .inProgress }
        let pendingItems = planItems.filter { $0.status == .pending }
        let completedCount = planItems.filter { $0.status == .completed }.count
        let allComplete = pendingItems.isEmpty && !hasInProgress && completedCount == planItems.count

        if allComplete {
            // All items are completed - no chaining needed
            response["next_action"].string = """
                All knowledge cards are complete! \
                Ready to proceed to Phase 3 or review/refine existing cards.
                """
        } else if hasInProgress {
            // There's already an item in progress - don't change focus
            response["next_action"].string = """
                An item is already in progress. Continue collecting info for that item, \
                then generate the knowledge card when ready.
                """
        } else if let firstItem = pendingItems.first {
            // No item in progress but pending items exist - chain to select the first one
            response["next_required_tool"].string = OnboardingToolName.setCurrentKnowledgeCard.rawValue
            response["suggested_item_id"].string = firstItem.id
            response["suggested_item_title"].string = firstItem.title
            response["next_action"].string = """
                Plan displayed. You MUST now call set_current_knowledge_card with item_id="\(firstItem.id)" \
                to select "\(firstItem.title)" as the first item to work on. This enables the "Done" button.
                """
        } else {
            // Edge case: no pending, no in_progress, but not all complete (some skipped?)
            response["next_action"].string = """
                Plan displayed. Review the items and decide whether to work on any skipped items \
                or proceed to Phase 3.
                """
        }

        return .immediate(response)
    }
}

/// Model for a knowledge card plan item
struct KnowledgeCardPlanItem: Identifiable, Equatable, Codable {
    enum ItemType: String, Codable {
        case job
        case skill
    }

    enum Status: String, Codable {
        case pending
        case inProgress = "in_progress"
        case completed
        case skipped
    }

    let id: String
    let title: String
    let type: ItemType
    let description: String?
    let status: Status
    let timelineEntryId: String?

    func toJSON() -> JSON {
        var json = JSON()
        json["id"].string = id
        json["title"].string = title
        json["type"].string = type.rawValue
        json["status"].string = status.rawValue
        if let description = description {
            json["description"].string = description
        }
        if let timelineEntryId = timelineEntryId {
            json["timeline_entry_id"].string = timelineEntryId
        }
        return json
    }
}
