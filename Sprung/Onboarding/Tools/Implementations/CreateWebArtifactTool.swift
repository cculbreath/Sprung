//
//  CreateWebArtifactTool.swift
//  Sprung
//
//  Tool for creating artifacts from web content retrieved via web_search or web_fetch.
//  Used when the agent finds valuable content that should be persisted.
//
import Foundation
import SwiftyJSON
import SwiftOpenAI

struct CreateWebArtifactTool: InterviewTool {
    private static let schema: JSONSchema = ArtifactSchemas.createWebArtifact
    private let eventBus: EventCoordinator

    init(coordinator _: OnboardingInterviewCoordinator, eventBus: EventCoordinator) {
        self.eventBus = eventBus
    }

    var name: String { OnboardingToolName.createWebArtifact.rawValue }
    var description: String {
        "Create an artifact from web content. Use after web_search or web_fetch when the content is valuable for the user's profile."
    }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        // Validate required parameters
        guard let url = params["url"].string, !url.isEmpty else {
            return ToolResultHelpers.invalidParameters("url is required")
        }
        guard let title = params["title"].string, !title.isEmpty else {
            return ToolResultHelpers.invalidParameters("title is required")
        }
        guard let content = params["content"].string, !content.isEmpty else {
            return ToolResultHelpers.invalidParameters("content is required")
        }
        guard let documentType = params["documentType"].string, !documentType.isEmpty else {
            return ToolResultHelpers.invalidParameters("documentType is required")
        }

        let summary = params["summary"].string ?? ""

        // Generate unique artifact ID
        let artifactId = UUID().uuidString

        // Build artifact record JSON
        var artifactRecord = JSON()
        artifactRecord["id"].string = artifactId
        artifactRecord["filename"].string = "web_\(documentType)_\(artifactId.prefix(8)).txt"
        artifactRecord["title"].string = title
        artifactRecord["documentType"].string = documentType
        artifactRecord["contentType"].string = "text/plain"
        artifactRecord["extractedText"].string = content
        artifactRecord["summary"].string = summary.isEmpty ? String(content.prefix(200)) : summary
        artifactRecord["briefDescription"].string = summary.isEmpty ? "Web content from \(documentType)" : summary
        artifactRecord["sourceUrl"].string = url
        artifactRecord["createdAt"].string = ISO8601DateFormatter().string(from: Date())

        // Add metadata
        var metadata = JSON()
        metadata["sourceType"].string = "web_content"
        metadata["sourceUrl"].string = url
        metadata["documentType"].string = documentType
        metadata["extraction"]["characterCount"].int = content.count
        metadata["extraction"]["extractionMethod"].string = "web_fetch"
        artifactRecord["metadata"] = metadata

        // Summary metadata for consistency with other artifacts
        var summaryMetadata = JSON()
        summaryMetadata["documentType"].string = documentType
        summaryMetadata["briefDescription"].string = artifactRecord["briefDescription"].stringValue
        artifactRecord["summaryMetadata"] = summaryMetadata

        // Emit artifact record produced event for StateCoordinator to process
        await eventBus.publish(.artifact(.recordProduced(record: artifactRecord)))

        Logger.info("🌐 Web artifact created: id=\(artifactId), type=\(documentType), url=\(url)", category: .ai)

        // Build success response
        var response = JSON()
        response["status"].string = "completed"
        response["success"].bool = true
        response["artifactId"].string = artifactId
        response["title"].string = title
        response["documentType"].string = documentType
        response["message"].string = "Web artifact created successfully from \(url)"

        return .immediate(response)
    }
}
