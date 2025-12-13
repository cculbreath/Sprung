import Foundation
import SwiftyJSON
import SwiftOpenAI

struct ListArtifactsTool: InterviewTool {
    private static let schema: JSONSchema = ArtifactSchemas.listArtifacts
    private unowned let coordinator: OnboardingInterviewCoordinator
    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }
    var name: String { OnboardingToolName.listArtifacts.rawValue }
    var description: String { "List artifacts with pagination. Returns {total, artifacts: [{id, filename, content_type}]}." }
    var parameters: JSONSchema { Self.schema }
    func isAvailable() async -> Bool {
        let summaries = await coordinator.listArtifactSummaries()
        return !summaries.isEmpty
    }
    func execute(_ params: JSON) async throws -> ToolResult {
        let allSummaries = await coordinator.listArtifactSummaries()

        // Parse pagination parameters
        let limit = min(params["limit"].int ?? 10, 50)  // Default 10, max 50
        let offset = max(params["offset"].int ?? 0, 0)
        let includeSummary = params["include_summary"].bool ?? false

        // Apply pagination
        let totalCount = allSummaries.count
        let paginatedSummaries = Array(allSummaries.dropFirst(offset).prefix(limit))

        // Build minimal artifact entries
        var artifacts: [JSON] = []
        for summary in paginatedSummaries {
            var entry = JSON()
            entry["id"].string = summary["id"].string
            entry["filename"].string = summary["filename"].string
            entry["content_type"].string = summary["content_type"].string
            if includeSummary {
                // Include brief description (truncated)
                if let desc = summary["brief_description"].string, !desc.isEmpty {
                    entry["description"].string = String(desc.prefix(100))
                } else if let summ = summary["summary"].string, !summ.isEmpty {
                    entry["description"].string = String(summ.prefix(100))
                }
            }
            artifacts.append(entry)
        }

        var response = JSON()
        response["status"].string = "completed"
        response["total"].int = totalCount
        response["offset"].int = offset
        response["limit"].int = limit
        response["artifacts"] = JSON(artifacts)
        return .immediate(response)
    }
}
