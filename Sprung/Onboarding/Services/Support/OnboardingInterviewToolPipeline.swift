import Foundation
import SwiftyJSON

@MainActor
final class OnboardingInterviewToolPipeline {
    struct CustomResult {
        let handled: Bool
        let responses: [JSON]

        static let unhandled = CustomResult(handled: false, responses: [])
        static func handled(_ responses: [JSON] = []) -> CustomResult {
            CustomResult(handled: true, responses: responses)
        }
    }

    private let toolExecutor: OnboardingToolExecutor
    private let customHandler: (OnboardingToolCall) -> CustomResult
    private let sendResponses: ([JSON]) async -> Void
    private var processedIdentifiers: Set<String> = []

    init(
        toolExecutor: OnboardingToolExecutor,
        customHandler: @escaping (OnboardingToolCall) -> CustomResult,
        sendResponses: @escaping ([JSON]) async -> Void
    ) {
        self.toolExecutor = toolExecutor
        self.customHandler = customHandler
        self.sendResponses = sendResponses
    }

    func reset() {
        processedIdentifiers.removeAll()
    }

    func process(_ calls: [OnboardingToolCall]) async throws {
        guard !calls.isEmpty else { return }

        var responses: [JSON] = []

        for call in calls where !processedIdentifiers.contains(call.identifier) {
            let result = customHandler(call)
            if result.handled {
                processedIdentifiers.insert(call.identifier)
                responses.append(contentsOf: result.responses)
                continue
            }

            let executionResult = try await toolExecutor.execute(call)
            processedIdentifiers.insert(call.identifier)
            let payload: [String: Any] = [
                "tool": call.tool,
                "id": call.identifier,
                "status": "ok",
                "result": executionResult
            ]
            responses.append(JSON(payload))
        }

        if !responses.isEmpty {
            await sendResponses(responses)
        }
    }
}
