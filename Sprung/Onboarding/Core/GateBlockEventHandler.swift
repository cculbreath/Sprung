//
//  GateBlockEventHandler.swift
//  Sprung
//
//  Listens to events and manages DrainGate blocking state.
//  Blocks the gate during streaming and UI tool display.
//

import Foundation

/// Handles event-based gate blocking for the user action queue
actor GateBlockEventHandler {

    private let eventBus: EventCoordinator
    private let drainGate: DrainGate
    private var subscriptionTask: Task<Void, Never>?

    init(eventBus: EventCoordinator, drainGate: DrainGate) {
        self.eventBus = eventBus
        self.drainGate = drainGate
    }

    /// Start listening to events
    func startListening() {
        subscriptionTask = Task { [weak self] in
            guard let self = self else { return }
            let stream = await self.eventBus.streamAll()

            for await event in stream {
                await self.handleEvent(event)
            }
        }
        Logger.info("GateBlockEventHandler started listening", category: .ai)
    }

    /// Stop listening to events
    func stopListening() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
    }

    private func handleEvent(_ event: OnboardingEvent) async {
        switch event {
        // MARK: - Streaming Events

        case .llm(.streamingMessageBegan):
            await MainActor.run {
                drainGate.blockForStreaming()
            }

        case .llm(.streamingMessageFinalized):
            // Don't unblock yet - tool calls may follow
            break

        case .llm(.streamCompleted):
            await MainActor.run {
                drainGate.unblockStreaming()
            }

        // MARK: - Tool Execution Events

        case .tool(.callRequested(let call, _)):
            // Register tool name for status bar display
            await MainActor.run {
                drainGate.registerToolCall(callId: call.callId, toolName: call.name)
            }

        case .llm(.toolCallBatchStarted(_, let callIds)):
            // Block gate while tools are executing
            await MainActor.run {
                drainGate.blockForToolExecution(callIds: callIds)
            }

        case .llm(.toolResultFilled(let callId, _)):
            // Mark this tool as completed
            await MainActor.run {
                drainGate.toolCallCompleted(callId: callId)
            }

        // MARK: - LLM Response Events

        case .llm(.status(let status)):
            switch status {
            case .busy:
                // LLM is responding, block the gate
                await MainActor.run {
                    drainGate.blockForLLMResponse()
                }
            case .idle, .error:
                // LLM finished responding, unblock
                await MainActor.run {
                    drainGate.unblockLLMResponse()
                }
            }

        // MARK: - UI Tool Events

        case .toolpane(.uploadRequestPresented):
            await MainActor.run {
                drainGate.blockForUITool("get_user_upload")
            }

        case .toolpane(.uploadRequestCancelled):
            await MainActor.run {
                drainGate.unblockUITool("get_user_upload")
            }

        case .artifact(.uploadCompleted):
            // Upload completed, unblock the UI tool gate
            await MainActor.run {
                drainGate.unblockUITool("get_user_upload")
            }

        case .toolpane(.choicePromptRequested):
            await MainActor.run {
                drainGate.blockForUITool("get_user_option")
            }

        case .toolpane(.choicePromptCleared):
            await MainActor.run {
                drainGate.unblockUITool("get_user_option")
            }

        case .toolpane(.validationPromptRequested):
            await MainActor.run {
                drainGate.blockForUITool("submit_for_validation")
            }

        case .toolpane(.validationPromptCleared):
            await MainActor.run {
                drainGate.unblockUITool("submit_for_validation")
            }

        case .toolpane(.applicantProfileIntakeRequested):
            await MainActor.run {
                drainGate.blockForUITool("get_applicant_profile")
            }

        case .toolpane(.applicantProfileIntakeCleared):
            await MainActor.run {
                drainGate.unblockUITool("get_applicant_profile")
            }

        case .toolpane(.sectionToggleRequested):
            await MainActor.run {
                drainGate.blockForUITool("configure_enabled_sections")
            }

        case .toolpane(.sectionToggleCleared):
            await MainActor.run {
                drainGate.unblockUITool("configure_enabled_sections")
            }

        default:
            break
        }
    }
}
