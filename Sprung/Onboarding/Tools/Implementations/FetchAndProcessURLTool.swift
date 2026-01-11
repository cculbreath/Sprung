//
//  FetchAndProcessURLTool.swift
//  Sprung
//
//  Tool for fetching web content from a URL and processing it through the
//  full extraction pipeline: verbatim content capture, KC extraction, skill extraction.
//
import Foundation
import SwiftyJSON
import SwiftOpenAI

struct FetchAndProcessURLTool: InterviewTool {
    private static let schema = SchemaGenerator.object(
        description: "Fetch content from a URL and extract knowledge cards and skills",
        properties: [
            "url": SchemaGenerator.string(description: "The URL to fetch and process"),
            "documentType": SchemaGenerator.string(
                description: "Type of document (e.g., 'portfolio', 'linkedin_profile', 'blog_post', 'project_page')"
            )
        ],
        required: ["url", "documentType"]
    )

    private let eventBus: EventCoordinator
    private weak var coordinator: OnboardingInterviewCoordinator?
    private let webExtractionService: WebExtractionService

    init(
        coordinator: OnboardingInterviewCoordinator,
        eventBus: EventCoordinator,
        webExtractionService: WebExtractionService
    ) {
        self.coordinator = coordinator
        self.eventBus = eventBus
        self.webExtractionService = webExtractionService
    }

    var name: String { OnboardingToolName.fetchAndProcessURL.rawValue }
    var description: String {
        """
        Fetch content from a URL and process it like a document upload. \
        This will capture the page content verbatim, extract narrative knowledge cards, \
        and identify skills from the content.
        """
    }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        // Validate required parameters
        guard let urlString = params["url"].string, !urlString.isEmpty else {
            return ToolResultHelpers.invalidParameters("url is required")
        }
        guard let url = URL(string: urlString) else {
            return ToolResultHelpers.invalidParameters("Invalid URL format")
        }
        guard let documentType = params["documentType"].string, !documentType.isEmpty else {
            return ToolResultHelpers.invalidParameters("documentType is required")
        }

        Logger.info("🌐 FetchAndProcessURLTool: Starting extraction for \(urlString)", category: .ai)

        // Run the full extraction pipeline
        do {
            let result = try await webExtractionService.processURL(url: url) { status in
                Logger.info("🌐 \(status)", category: .ai)
            }

            // Create artifact record from result
            var artifactRecord = await MainActor.run {
                webExtractionService.createArtifactRecord(from: result)
            }
            artifactRecord["documentType"].string = documentType

            // Emit artifact record produced event
            await eventBus.publish(.artifact(.recordProduced(record: artifactRecord)))

            Logger.info("✅ FetchAndProcessURLTool: Extraction complete - \(result.skills.count) skills, \(result.narrativeCards.count) KCs", category: .ai)

            // Build success response
            var response = JSON()
            response["status"].string = "completed"
            response["success"].bool = true
            response["artifactId"].string = result.id
            response["url"].string = urlString
            response["title"].string = result.title ?? urlString
            response["documentType"].string = documentType
            response["extractedTextLength"].int = result.extractedText.count
            response["skillsCount"].int = result.skills.count
            response["narrativeCardsCount"].int = result.narrativeCards.count
            response["message"].string = """
                Successfully processed \(urlString). \
                Extracted \(result.extractedText.count) characters, \
                \(result.skills.count) skills, and \(result.narrativeCards.count) narrative cards.
                """

            return .immediate(response)
        } catch {
            Logger.error("❌ FetchAndProcessURLTool: Extraction failed - \(error.localizedDescription)", category: .ai)

            var response = JSON()
            response["status"].string = "failed"
            response["success"].bool = false
            response["error"].string = error.localizedDescription
            response["message"].string = "Failed to fetch or process URL: \(error.localizedDescription)"

            return .immediate(response)
        }
    }
}
