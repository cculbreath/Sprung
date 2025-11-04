import Foundation
import SwiftyJSON
import SwiftOpenAI

struct RequestRawArtifactFileTool: InterviewTool {
    let service: OnboardingInterviewService
    
    var name: String { "request_raw_file" }
    var description: String { "Request raw artifact file" }
    var parameters: JSONSchema { JSONSchema(type: .object, properties: [:]) }
    
    func execute(_ params: JSON) async throws -> ToolResult {
        // TODO: Reimplement using event-driven architecture
        var response = JSON()
        response["status"] = "pending"
        return .immediate(response)
    }
}
