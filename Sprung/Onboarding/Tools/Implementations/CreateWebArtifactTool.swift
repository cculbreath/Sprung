//
//  CreateWebArtifactTool.swift
//  Sprung
//
//  Tool for creating artifacts from web content retrieved via web_search.
//  Used when the agent finds valuable content that should be persisted.
//
import Foundation
import SwiftyJSON
import SwiftOpenAI

struct CreateWebArtifactTool: InterviewTool {
    private static let schema: JSONSchema = ArtifactSchemas.createWebArtifact
    private unowned let coordinator: OnboardingInterviewCoordinator
    private let eventBus: EventCoordinator

    init(coordinator: OnboardingInterviewCoordinator, eventBus: EventCoordinator) {
        self.coordinator = coordinator
        self.eventBus = eventBus
    }

    var name: String { OnboardingToolName.createWebArtifact.rawValue }
    var description: String {
        "Create an artifact from web content. Use after web_search when the content is valuable for the user's profile."
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
        guard let documentType = params["document_type"].string, !documentType.isEmpty else {
            return ToolResultHelpers.invalidParameters("document_type is required")
        }

        let summary = params["summary"].string ?? ""

        // Generate unique artifact ID
        let artifactId = UUID().uuidString

        // Build artifact record JSON
        var artifactRecord = JSON()
        artifactRecord["id"].string = artifactId
        artifactRecord["filename"].string = "web_\(documentType)_\(artifactId.prefix(8)).txt"
        artifactRecord["title"].string = title
        artifactRecord["document_type"].string = documentType
        artifactRecord["content_type"].string = "text/plain"
        artifactRecord["extracted_text"].string = content
        artifactRecord["summary"].string = summary.isEmpty ? String(content.prefix(200)) : summary
        artifactRecord["brief_description"].string = summary.isEmpty ? "Web content from \(documentType)" : summary
        artifactRecord["source_url"].string = url
        artifactRecord["created_at"].string = ISO8601DateFormatter().string(from: Date())

        // Add metadata
        var metadata = JSON()
        metadata["source_type"].string = "web_search"
        metadata["source_url"].string = url
        metadata["document_type"].string = documentType
        metadata["extraction"]["character_count"].int = content.count
        metadata["extraction"]["extraction_method"].string = "web_search"
        artifactRecord["metadata"] = metadata

        // Summary metadata for consistency with other artifacts
        var summaryMetadata = JSON()
        summaryMetadata["document_type"].string = documentType
        summaryMetadata["brief_description"].string = artifactRecord["brief_description"].stringValue
        artifactRecord["summary_metadata"] = summaryMetadata

        // Emit artifact record produced event for StateCoordinator to process
        await eventBus.publish(.artifactRecordProduced(record: artifactRecord))

        Logger.info("🌐 Web artifact created: id=\(artifactId), type=\(documentType), url=\(url)", category: .ai)

        // Build success response
        var response = JSON()
        response["status"].string = "completed"
        response["success"].bool = true
        response["artifact_id"].string = artifactId
        response["title"].string = title
        response["document_type"].string = documentType
        response["message"].string = "Web artifact created successfully from \(url)"

        return .immediate(response)
    }
}
