import Foundation
import SwiftyJSON
import SwiftOpenAI

struct CapabilitiesDescribeTool: InterviewTool {
    private static let schema = JSONSchema(
        type: .object,
        description: "Returns the sanitized capabilities manifest for onboarding tools.",
        properties: [:],
        required: [],
        additionalProperties: false
    )

    private let service: OnboardingInterviewService

    init(service: OnboardingInterviewService) {
        self.service = service
    }

    var name: String { "capabilities.describe" }
    var description: String { "Describe currently available onboarding tools and their functional flags." }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        let manifest = await MainActor.run { service.capabilityManifest() }
        return .immediate(manifest)
    }
}
