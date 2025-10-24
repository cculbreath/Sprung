//
//  InterviewOrchestrator.swift
//  Sprung
//
//  Drives the onboarding interview loop via OpenAI Responses API.
//

import Foundation
import SwiftOpenAI
import SwiftyJSON

actor InterviewOrchestrator {
    private let client: OpenAIService
    private let state: InterviewState
    private let toolExecutor: ToolExecutor
    private var messages: [InputItem] = []
    private var isRunning = false

    init(
        client: OpenAIService,
        state: InterviewState,
        toolExecutor: ToolExecutor
    ) {
        self.client = client
        self.state = state
        self.toolExecutor = toolExecutor
    }

    func startInterview() async throws {
        guard !isRunning else {
            return
        }
        isRunning = true
        defer { isRunning = false }
        try await processNextStep()
    }

    private func processNextStep() async throws {
        let configuration = ModelProvider.configuration(for: .orchestrator)
        var parameters = ModelResponseParameter(
            input: .array(messages),
            model: .custom(configuration.id),
            temperature: 1.0,
            text: TextConfiguration(format: .text)
        )
        parameters.parallelToolCalls = false
        parameters.tools = toolExecutor.availableToolSchemas()

        if let verbosity = configuration.defaultVerbosity {
            parameters.text?.verbosity = verbosity
        }
        if let effort = configuration.defaultReasoningEffort {
            parameters.reasoning = ModelResponseParameter.Reasoning(effort: effort)
        }

        _ = try await client.responseCreate(parameters)
        // Response handling will be fleshed out in subsequent milestones.
    }
}
