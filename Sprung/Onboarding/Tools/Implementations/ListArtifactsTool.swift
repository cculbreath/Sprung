import Foundation
import SwiftyJSON
import SwiftOpenAI

struct ListArtifactsTool: InterviewTool {
    private static let schema: JSONSchema = ArtifactSchemas.listArtifacts
    private weak var coordinator: OnboardingInterviewCoordinator?
    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }
    var name: String { OnboardingToolName.listArtifacts.rawValue }
    var description: String { "List artifacts with pagination. Returns {total, artifacts: [{id, filename, contentType}]}." }
    var parameters: JSONSchema { Self.schema }
    func isAvailable() async -> Bool {
        guard let coordinator else { return false }
        let summaries = await coordinator.listArtifactSummaries()
        return !summaries.isEmpty
    }
    func execute(_ params: JSON) async throws -> ToolResult {
        guard let coordinator else {
            return .error(ToolError.executionFailed("Coordinator unavailable"))
        }
        let allSummaries = await coordinator.listArtifactSummaries()

        // Parse pagination parameters
        let limit = min(params["limit"].int ?? 10, 50)  // Default 10, max 50
        let offset = max(params["offset"].int ?? 0, 0)
        let includeSummary = params["includeSummary"].bool ?? false

        // Apply pagination
        let totalCount = allSummaries.count
        let paginatedSummaries = Array(allSummaries.dropFirst(offset).prefix(limit))

        // Build minimal artifact entries
        var artifacts: [JSON] = []
        for summary in paginatedSummaries {
            var entry = JSON()
            entry["id"].string = summary["id"].string
            entry["filename"].string = summary["filename"].string
            entry["contentType"].string = summary["contentType"].string
            if includeSummary {
                // Include brief description (truncated)
                if let desc = summary["briefDescription"].string, !desc.isEmpty {
                    entry["description"].string = String(desc.prefix(100))
                } else if let summ = summary["summary"].string, !summ.isEmpty {
                    entry["description"].string = String(summ.prefix(100))
                }
            }
            artifacts.append(entry)
        }

        // Use paginatedResponse helper, but need to add status and rename artifacts to match expected format
        var response = JSON()
        response["success"].bool = true
        response["status"].string = "completed"
        response["total"].int = totalCount
        response["offset"].int = offset
        response["limit"].int = limit
        response["artifacts"] = JSON(artifacts)
        return .immediate(response)
    }
}
