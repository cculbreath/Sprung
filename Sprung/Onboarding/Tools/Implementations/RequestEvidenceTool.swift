import Foundation
import SwiftyJSON
struct RequestEvidenceTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: "Request a specific piece of evidence (document, link, code) from the user to verify a timeline entry. Use this to build an 'Evidence Request List' that the user can fulfill by uploading files.",
            properties: [
                "timeline_entry_id": JSONSchema(
                    type: .string,
                    description: "ID of the timeline entry this evidence relates to."
                ),
                "description": JSONSchema(
                    type: .string,
                    description: "Clear description of what evidence is needed (e.g., 'Upload your PhD dissertation PDF')."
                ),
                "category": JSONSchema(
                    type: .string,
                    description: "Type of evidence: 'paper', 'code', 'website', 'portfolio', 'degree', or 'other'.",
                    enum: ["paper", "code", "website", "portfolio", "degree", "other"]
                )
            ],
            required: ["timeline_entry_id", "description", "category"],
            additionalProperties: false
        )
    }()
    private unowned let coordinator: OnboardingInterviewCoordinator
    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }
    var name: String { OnboardingToolName.requestEvidence.rawValue }
    var description: String { "Request specific evidence from the user to verify a timeline entry." }
    var parameters: JSONSchema { Self.schema }
    func execute(_ params: JSON) async throws -> ToolResult {
        guard let timelineEntryId = params["timeline_entry_id"].string, !timelineEntryId.isEmpty else {
            throw ToolError.invalidParameters("timeline_entry_id must be provided")
        }
        guard let description = params["description"].string, !description.isEmpty else {
            throw ToolError.invalidParameters("description must be provided")
        }
        guard let categoryString = params["category"].string else {
            throw ToolError.invalidParameters("category must be provided")
        }
        guard let category = EvidenceRequirement.EvidenceCategory(rawValue: categoryString) else {
            throw ToolError.invalidParameters("Invalid category: \(categoryString). Must be one of: paper, code, website, portfolio, degree, other")
        }
        let requirement = EvidenceRequirement(
            timelineEntryId: timelineEntryId,
            description: description,
            category: category
        )
        await coordinator.eventBus.publish(.evidenceRequirementAdded(requirement))
        let result = JSON([
            "status": "success",
            "message": "Evidence request added: \(description)",
            "request_id": requirement.id
        ])
        return .immediate(result)
    }
}
