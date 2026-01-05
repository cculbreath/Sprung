//
//  AnthropicRequestBuilder.swift
//  Sprung
//
//  Builds AnthropicMessageParameter requests for the Onboarding Interview's Anthropic Messages API calls.
//  Delegates to specialized components for history building, tool conversion, and working memory.
//

import Foundation
import SwiftOpenAI
import SwiftyJSON

/// Builds AnthropicMessageParameter requests for the Onboarding Interview's Anthropic Messages API calls.
/// Extracted to separate request construction from stream handling.
struct AnthropicRequestBuilder {
    private let baseDeveloperMessage: String
    private let stateCoordinator: StateCoordinator
    private let historyBuilder: AnthropicHistoryBuilder
    private let toolConverter: AnthropicToolConverter
    private let workingMemoryBuilder: WorkingMemoryBuilder

    init(
        baseDeveloperMessage: String,
        toolRegistry: ToolRegistry,
        contextAssembler: ConversationContextAssembler,
        stateCoordinator: StateCoordinator
    ) {
        self.baseDeveloperMessage = baseDeveloperMessage
        self.stateCoordinator = stateCoordinator
        self.historyBuilder = AnthropicHistoryBuilder(contextAssembler: contextAssembler)
        self.toolConverter = AnthropicToolConverter(toolRegistry: toolRegistry, stateCoordinator: stateCoordinator)
        self.workingMemoryBuilder = WorkingMemoryBuilder(stateCoordinator: stateCoordinator)
    }

    // MARK: - User Message Request

    func buildUserMessageRequest(
        text: String,
        isSystemGenerated: Bool,
        bundledDeveloperMessages: [JSON] = [],
        forcedToolChoice: String? = nil,
        imageBase64: String? = nil,
        imageContentType: String? = nil
    ) async -> AnthropicMessageParameter {
        var messages: [AnthropicMessage] = []

        // Build conversation history (Anthropic uses explicit messages, no PRI)
        let history = await historyBuilder.buildAnthropicHistory()
        if !history.isEmpty {
            messages.append(contentsOf: history)
            Logger.info("📋 Including \(history.count) messages from transcript", category: .ai)
        }

        // Build user message - with image if provided
        // CRITICAL: If history ends with a user message (e.g., synthetic tool_result from race condition),
        // we must merge the new content with it to maintain Anthropic's role alternation requirement.
        let newUserBlocks: [AnthropicContentBlock]
        if let fileData = imageBase64 {
            let mimeType = imageContentType ?? "image/jpeg"

            // Use document block for PDFs, image block for images
            if mimeType == "application/pdf" {
                let docSource = AnthropicDocumentSource(mediaType: mimeType, data: fileData)
                newUserBlocks = [
                    .text(AnthropicTextBlock(text: text)),
                    .document(AnthropicDocumentBlock(source: docSource))
                ]
                Logger.info("📄 Including PDF document in user message", category: .ai)
            } else {
                let imageSource = AnthropicImageSource(mediaType: mimeType, data: fileData)
                newUserBlocks = [
                    .text(AnthropicTextBlock(text: text)),
                    .image(AnthropicImageBlock(source: imageSource))
                ]
                Logger.info("🖼️ Including image attachment in user message (\(mimeType))", category: .ai)
            }
        } else {
            newUserBlocks = [.text(AnthropicTextBlock(text: text))]
        }

        // Check if we need to merge with trailing user message from history
        if let lastIndex = messages.indices.last,
           messages[lastIndex].role == "user" {
            // Merge new content with existing user message
            let existingBlocks = historyBuilder.extractContentBlocks(messages[lastIndex])
            let mergedBlocks = existingBlocks + newUserBlocks
            messages[lastIndex] = AnthropicMessage(role: "user", content: .blocks(mergedBlocks))
            Logger.info("📝 Merged new user content with trailing user message (race condition handling)", category: .ai)
        } else {
            // Append as new user message
            messages.append(AnthropicMessage(role: "user", content: .blocks(newUserBlocks)))
        }

        // Determine tool choice
        let effectiveForcedToolChoice: String?
        if let forcedToolChoice {
            effectiveForcedToolChoice = forcedToolChoice
        } else {
            effectiveForcedToolChoice = await stateCoordinator.popPendingForcedToolChoice()
        }

        let toolChoice: AnthropicToolChoice
        if let forcedTool = effectiveForcedToolChoice {
            // Use 'any' instead of forcing specific tool - Anthropic has a bug where
            // forced tool_choice returns stop_reason=tool_use but no content blocks.
            // The system prompt guides the model to call the intended tool.
            toolChoice = .any
            Logger.info("🎯 Using toolChoice=any (intended: \(forcedTool)) - Anthropic workaround", category: .ai)
        } else if !isSystemGenerated {
            let hasStreamed = await stateCoordinator.getHasStreamedFirstResponse()
            if !hasStreamed {
                Logger.info("🚫 Disabling tools for first user request to ensure greeting", category: .ai)
                toolChoice = .none
            } else {
                toolChoice = .auto
            }
        } else {
            toolChoice = .auto
        }

        // Get tools and convert to Anthropic format
        let tools = await toolConverter.getAnthropicTools()

        // Build system prompt (includes base developer message + working memory + bundled messages)
        let systemPrompt = await buildSystemPrompt(bundledDeveloperMessages: bundledDeveloperMessages)

        let modelId = await stateCoordinator.getAnthropicModelId()

        let parameters = AnthropicMessageParameter(
            model: modelId,
            messages: messages,
            system: systemPrompt.isEmpty ? nil : .text(systemPrompt),
            maxTokens: 4096,
            stream: true,
            tools: tools.isEmpty ? nil : tools,
            toolChoice: toolChoice == .none && tools.isEmpty ? nil : toolChoice,
            temperature: 1.0
        )

        Logger.info(
            "📝 Built Anthropic request: messages=\(messages.count), tools=\(tools.count)",
            category: .ai
        )

        return parameters
    }

    // MARK: - Developer Message Request

    func buildDeveloperMessageRequest(
        text: String,
        toolChoice toolChoiceName: String? = nil
    ) async -> AnthropicMessageParameter {
        var messages: [AnthropicMessage] = []

        // Include conversation history
        let history = await historyBuilder.buildAnthropicHistory()
        messages.append(contentsOf: history)

        // For Anthropic, developer instructions go in the system prompt
        // We still need a user message to trigger a response
        // Use a minimal user prompt to represent the developer instruction
        // CRITICAL: Check if history ends with user message (e.g., synthetic tool_result) and merge if so
        let placeholderText = "[System instruction received - please continue the conversation]"
        if let lastIndex = messages.indices.last,
           messages[lastIndex].role == "user" {
            let existingBlocks = historyBuilder.extractContentBlocks(messages[lastIndex])
            let mergedBlocks = existingBlocks + [.text(AnthropicTextBlock(text: placeholderText))]
            messages[lastIndex] = AnthropicMessage(role: "user", content: .blocks(mergedBlocks))
            Logger.info("📝 Merged developer placeholder with trailing user message (race condition handling)", category: .ai)
        } else {
            messages.append(.user(placeholderText))
        }

        let toolChoice: AnthropicToolChoice
        if let toolName = toolChoiceName {
            toolChoice = .tool(name: toolName)
        } else {
            toolChoice = .auto
        }

        let tools = await toolConverter.getAnthropicTools()
        let systemPrompt = await buildSystemPrompt(additionalInstruction: text)
        let modelId = await stateCoordinator.getAnthropicModelId()

        let parameters = AnthropicMessageParameter(
            model: modelId,
            messages: messages,
            system: systemPrompt.isEmpty ? nil : .text(systemPrompt),
            maxTokens: 4096,
            stream: true,
            tools: tools.isEmpty ? nil : tools,
            toolChoice: tools.isEmpty ? nil : toolChoice,
            temperature: 1.0
        )

        Logger.info(
            "📝 Built Anthropic developer message request: messages=\(messages.count)",
            category: .ai
        )

        return parameters
    }

    // MARK: - Tool Response Request

    func buildToolResponseRequest(
        output: JSON,
        callId: String,
        toolName: String,
        forcedToolChoice: String? = nil
    ) async -> AnthropicMessageParameter {
        var messages: [AnthropicMessage] = []

        // Include conversation history, excluding the current callId since we add it below
        let history = await historyBuilder.buildAnthropicHistory(excludeToolCallIds: [callId])
        messages.append(contentsOf: history)

        // Add tool result as user message
        let resultContent = output.rawString() ?? "{}"
        messages.append(.toolResult(toolUseId: callId, content: resultContent))

        let toolChoice: AnthropicToolChoice
        if let forcedTool = forcedToolChoice {
            // Use 'any' instead of forcing specific tool - Anthropic has a bug where
            // forced tool_choice returns stop_reason=tool_use but no content blocks.
            // The system prompt guides the model to call the intended tool.
            toolChoice = .any
            Logger.info("🔗 Using toolChoice=any (intended: \(forcedTool)) - Anthropic workaround", category: .ai)
        } else {
            toolChoice = .auto
        }

        let tools = await toolConverter.getAnthropicTools()
        let systemPrompt = await buildSystemPrompt()
        let modelId = await stateCoordinator.getAnthropicModelId()

        let parameters = AnthropicMessageParameter(
            model: modelId,
            messages: messages,
            system: systemPrompt.isEmpty ? nil : .text(systemPrompt),
            maxTokens: 4096,
            stream: true,
            tools: tools.isEmpty ? nil : tools,
            toolChoice: tools.isEmpty ? nil : toolChoice,
            temperature: 1.0
        )

        // Log diagnostic info about tool blocks
        let (toolUseCount, toolResultCount) = countToolBlocks(in: messages)
        Logger.info(
            "📝 Built Anthropic tool response request: callId=\(callId), " +
            "tool_use=\(toolUseCount), tool_result=\(toolResultCount) (should match after this response)",
            category: .ai
        )

        // Log any mismatches
        if toolUseCount != toolResultCount {
            Logger.warning(
                "⚠️ Tool block mismatch: \(toolUseCount) tool_use vs \(toolResultCount) tool_result. " +
                "Anthropic requires each tool_use to have a corresponding tool_result.",
                category: .ai
            )
        }

        return parameters
    }

    /// Count tool_use and tool_result blocks in messages
    private func countToolBlocks(in messages: [AnthropicMessage]) -> (toolUse: Int, toolResult: Int) {
        var toolUseCount = 0
        var toolResultCount = 0

        for message in messages {
            switch message.content {
            case .text:
                break
            case .blocks(let blocks):
                for block in blocks {
                    switch block {
                    case .toolUse:
                        toolUseCount += 1
                    case .toolResult:
                        toolResultCount += 1
                    default:
                        break
                    }
                }
            }
        }

        return (toolUseCount, toolResultCount)
    }

    // MARK: - Batched Tool Response Request

    func buildBatchedToolResponseRequest(payloads: [JSON]) async -> AnthropicMessageParameter {
        var messages: [AnthropicMessage] = []

        // Extract all callIds to exclude from history (we add them below)
        let excludeCallIds = Set(payloads.map { $0["callId"].stringValue })

        // Include conversation history, excluding the current callIds since we add them below
        let history = await historyBuilder.buildAnthropicHistory(excludeToolCallIds: excludeCallIds)
        messages.append(contentsOf: history)

        // Add all tool results in a single user message with multiple tool_result blocks
        var toolResultBlocks: [AnthropicContentBlock] = []
        for payload in payloads {
            let callId = payload["callId"].stringValue
            let output = payload["output"]
            let resultContent = output.rawString() ?? "{}"
            toolResultBlocks.append(.toolResult(AnthropicToolResultBlock(
                toolUseId: callId,
                content: resultContent
            )))
        }
        messages.append(AnthropicMessage(role: "user", content: .blocks(toolResultBlocks)))

        let tools = await toolConverter.getAnthropicTools()
        let systemPrompt = await buildSystemPrompt()
        let modelId = await stateCoordinator.getAnthropicModelId()

        let parameters = AnthropicMessageParameter(
            model: modelId,
            messages: messages,
            system: systemPrompt.isEmpty ? nil : .text(systemPrompt),
            maxTokens: 4096,
            stream: true,
            tools: tools.isEmpty ? nil : tools,
            toolChoice: tools.isEmpty ? nil : .auto,
            temperature: 1.0
        )

        Logger.info(
            "📝 Built Anthropic batched tool response request: \(payloads.count) tool outputs",
            category: .ai
        )

        return parameters
    }

    // MARK: - System Prompt

    private func buildSystemPrompt(
        bundledDeveloperMessages: [JSON] = [],
        additionalInstruction: String? = nil
    ) async -> String {
        var parts: [String] = [baseDeveloperMessage]

        // Add bundled developer messages
        for devPayload in bundledDeveloperMessages {
            let devText = devPayload["text"].stringValue
            if !devText.isEmpty {
                parts.append(devText)
            }
        }

        // Add additional instruction if provided
        if let instruction = additionalInstruction {
            parts.append(instruction)
        }

        // Add working memory
        if let workingMemory = await workingMemoryBuilder.buildWorkingMemory() {
            parts.append(workingMemory)
        }

        return parts.joined(separator: "\n\n")
    }
}

// MARK: - OnboardingProvider Enum

/// Available LLM providers for the onboarding interview
enum OnboardingProvider: String, CaseIterable {
    case openai = "openai"
    case anthropic = "anthropic"

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        }
    }
}

// MARK: - StateCoordinator Extension

extension StateCoordinator {
    /// Get the Anthropic model ID from settings
    func getAnthropicModelId() async -> String {
        return UserDefaults.standard.string(forKey: "onboardingAnthropicModelId") ?? DefaultModels.anthropic
    }

    /// Get the currently selected onboarding provider
    func getOnboardingProvider() async -> OnboardingProvider {
        let rawValue = UserDefaults.standard.string(forKey: "onboardingProvider") ?? "openai"
        return OnboardingProvider(rawValue: rawValue) ?? .openai
    }

    /// Set the onboarding provider
    func setOnboardingProvider(_ provider: OnboardingProvider) async {
        UserDefaults.standard.set(provider.rawValue, forKey: "onboardingProvider")
    }
}
