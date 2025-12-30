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
                3. User clicks "Done with Uploads" → system merges card inventories
                4. User reviews cards, clicks "Generate Cards" → system dispatches KC agents

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
        // Validate required parameters using helpers
        let items: [JSON]
        do {
            items = try ToolResultHelpers.requireNonEmptyArray(params["items"].array, named: "items")
        } catch {
            return .error(error as! ToolError)
        }

        let currentFocus = params["current_focus"].string
        let message = params["message"].string

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

        // Determine next action based on plan state
        let pendingItems = planItems.filter { $0.status == .pending }
        let completedCount = planItems.filter { $0.status == .completed }.count
        let allComplete = pendingItems.isEmpty && completedCount == planItems.count

        // Build additional data for response
        var additionalData = JSON()
        additionalData["item_count"].int = planItems.count
        additionalData["pending_count"].int = pendingItems.count
        additionalData["in_progress_count"].int = planItems.filter { $0.status == .inProgress }.count
        additionalData["completed_count"].int = completedCount

        if let currentFocus = currentFocus {
            additionalData["current_focus"].string = currentFocus
        }

        if allComplete {
            // All items are completed - no chaining needed
            additionalData["next_action"].string = """
                All knowledge cards are complete! \
                Ready to proceed to Phase 3 or review/refine existing cards.
                """
        } else {
            // Multi-agent workflow: chain to open_document_collection
            additionalData["next_required_tool"].string = OnboardingToolName.openDocumentCollection.rawValue
            additionalData["next_action"].string = """
                Plan displayed with \(planItems.count) card(s) (\(pendingItems.count) pending).

                You MUST now call `open_document_collection` to:
                1. Show the document collection UI with the KC plan
                2. Let the user upload supporting documents (resumes, portfolios, etc.)
                3. Wait for user to click "Done with Uploads"

                When user clicks "Done with Uploads", system merges card inventories automatically.
                User will then review cards and click "Generate Cards" to dispatch KC agents.
                """
        }

        return ToolResultHelpers.statusResponse(
            status: "completed",
            additionalData: additionalData
        )
    }
}

/// Model for a knowledge card plan item
struct KnowledgeCardPlanItem: Identifiable, Equatable, Codable {
    enum ItemType: String, Codable {
        case job
        case skill
        case project
        case achievement
        case education
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
    var status: Status
    let timelineEntryId: String?
    /// Artifact IDs assigned to this card (set by card merge)
    var assignedArtifactIds: [String]
    /// Brief summaries of assigned artifacts for UI display
    var assignedArtifactSummaries: [String]

    init(
        id: String,
        title: String,
        type: ItemType,
        description: String? = nil,
        status: Status = .pending,
        timelineEntryId: String? = nil,
        assignedArtifactIds: [String] = [],
        assignedArtifactSummaries: [String] = []
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.description = description
        self.status = status
        self.timelineEntryId = timelineEntryId
        self.assignedArtifactIds = assignedArtifactIds
        self.assignedArtifactSummaries = assignedArtifactSummaries
    }

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
        if !assignedArtifactIds.isEmpty {
            json["assigned_artifact_ids"].arrayObject = assignedArtifactIds
        }
        return json
    }

    /// Create a copy with updated artifact assignments
    func withAssignments(artifactIds: [String], summaries: [String]) -> KnowledgeCardPlanItem {
        KnowledgeCardPlanItem(
            id: id,
            title: title,
            type: type,
            description: description,
            status: status,
            timelineEntryId: timelineEntryId,
            assignedArtifactIds: artifactIds,
            assignedArtifactSummaries: summaries
        )
    }
}
