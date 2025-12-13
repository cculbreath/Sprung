import Foundation
import SwiftyJSON

/// Tool that displays the LLM's knowledge card generation plan as a visible checklist.
/// The LLM calls this to show the user what cards will be generated and track progress.
struct DisplayKnowledgeCardPlanTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: """
                Display the knowledge card generation plan to the user.

                MULTI-AGENT WORKFLOW:
                1. Call this tool after start_phase_two with your full plan
                2. Next, call open_document_collection to let user upload supporting documents
                3. After user clicks "Assess Completeness", call propose_card_assignments
                4. Cards are generated in parallel by KC agents via dispatch_kc_agents

                The plan is displayed to the user as a checklist. User can review and
                request modifications before generation begins.
                """,
            properties: [
                "items": KnowledgeCardSchemas.planItemsArray,
                "current_focus": KnowledgeCardSchemas.currentFocus,
                "message": KnowledgeCardSchemas.message
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
        let pendingItems = planItems.filter { $0.status == .pending }
        let completedCount = planItems.filter { $0.status == .completed }.count
        let allComplete = pendingItems.isEmpty && completedCount == planItems.count

        if allComplete {
            // All items are completed - no chaining needed
            response["next_action"].string = """
                All knowledge cards are complete! \
                Ready to proceed to Phase 3 or review/refine existing cards.
                """
        } else {
            // Multi-agent workflow: chain to open_document_collection
            // This shows the document collection UI for user to upload supporting docs
            response["next_required_tool"].string = OnboardingToolName.openDocumentCollection.rawValue
            response["next_action"].string = """
                Plan displayed with \(planItems.count) card(s) (\(pendingItems.count) pending).

                You MUST now call `open_document_collection` to:
                1. Show the document collection UI with the KC plan
                2. Let the user upload supporting documents (resumes, portfolios, etc.)
                3. Wait for user to click "Assess Completeness"

                After the user submits documents, proceed with propose_card_assignments.
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
