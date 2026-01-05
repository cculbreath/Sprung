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

        // Build full message text with XML tags (Anthropic-native pattern)
        // Order: <interview_context> + <coordinator> + <chatbox> or raw text
        var fullMessageParts: [String] = []

        // 1. Interview context (replaces working memory in system prompt)
        if let interviewContext = await workingMemoryBuilder.buildInterviewContext() {
            fullMessageParts.append(interviewContext)
        }

        // 2. Coordinator instructions (replaces developer messages)
        for devPayload in bundledDeveloperMessages {
            let devText = devPayload["text"].stringValue
            if !devText.isEmpty {
                fullMessageParts.append("<coordinator>\(devText)</coordinator>")
            }
        }

        // 3. The actual message text (already tagged with <chatbox> if from user)
        fullMessageParts.append(text)

        let fullMessageText = fullMessageParts.joined(separator: "\n\n")

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
                    .text(AnthropicTextBlock(text: fullMessageText)),
                    .document(AnthropicDocumentBlock(source: docSource))
                ]
                Logger.info("📄 Including PDF document in user message", category: .ai)
            } else {
                let imageSource = AnthropicImageSource(mediaType: mimeType, data: fileData)
                newUserBlocks = [
                    .text(AnthropicTextBlock(text: fullMessageText)),
                    .image(AnthropicImageBlock(source: imageSource))
                ]
                Logger.info("🖼️ Including image attachment in user message (\(mimeType))", category: .ai)
            }
        } else {
            newUserBlocks = [.text(AnthropicTextBlock(text: fullMessageText))]
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

        // Determine tool choice - prefer auto, only use .any as last resort
        let toolChoice: AnthropicToolChoice
        if !isSystemGenerated {
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

        // Build system prompt (base personality only - interview context now in user messages)
        let systemPrompt = await buildSystemPrompt()

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

    // MARK: - Coordinator Message Request

    /// Build a request with coordinator instructions.
    /// Per Anthropic best practices, coordinator instructions are sent as user messages
    /// with <coordinator> XML tags, not stuffed into system prompt.
    func buildDeveloperMessageRequest(
        text: String,
        toolChoice toolChoiceName: String? = nil
    ) async -> AnthropicMessageParameter {
        var messages: [AnthropicMessage] = []

        // Include conversation history
        let history = await historyBuilder.buildAnthropicHistory()
        messages.append(contentsOf: history)

        // Build message with interview context + coordinator instruction
        var messageParts: [String] = []

        // 1. Interview context
        if let interviewContext = await workingMemoryBuilder.buildInterviewContext() {
            messageParts.append(interviewContext)
        }

        // 2. Coordinator instruction (the "developer message")
        messageParts.append("<coordinator>\(text)</coordinator>")

        let fullMessageText = messageParts.joined(separator: "\n\n")

        // Add as user message (or merge with existing trailing user message)
        if let lastIndex = messages.indices.last,
           messages[lastIndex].role == "user" {
            let existingBlocks = historyBuilder.extractContentBlocks(messages[lastIndex])
            let mergedBlocks = existingBlocks + [.text(AnthropicTextBlock(text: fullMessageText))]
            messages[lastIndex] = AnthropicMessage(role: "user", content: .blocks(mergedBlocks))
            Logger.info("📝 Merged coordinator message with trailing user message", category: .ai)
        } else {
            messages.append(.user(fullMessageText))
        }

        // Tool choice - prefer auto (no forced toolChoice in Anthropic-native pattern)
        let toolChoice: AnthropicToolChoice = .auto

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

        Logger.info(
            "📝 Built Anthropic coordinator message request: messages=\(messages.count)",
            category: .ai
        )

        return parameters
    }

    // MARK: - Tool Response Request

    /// Build a request containing tool results.
    ///
    /// Per Anthropic best practices, instruction text can be included AFTER tool_result blocks
    /// in the same user message. This provides immediate guidance to Claude for the next action.
    ///
    /// - Parameters:
    ///   - output: The tool output JSON
    ///   - callId: The tool call ID to respond to
    ///   - toolName: The name of the tool (for logging)
    ///   - instruction: Optional instruction text to include after the tool_result.
    ///     This travels WITH the tool result for immediate guidance.
    ///   - forcedToolChoice: Optional tool to force (deprecated - prefer instruction text)
    ///   - pdfBase64: Optional base64-encoded PDF to include as a document block
    ///   - pdfFilename: Optional filename for the PDF attachment
    func buildToolResponseRequest(
        output: JSON,
        callId: String,
        toolName: String,
        instruction: String? = nil,
        forcedToolChoice: String? = nil,
        pdfBase64: String? = nil,
        pdfFilename: String? = nil
    ) async -> AnthropicMessageParameter {
        var messages: [AnthropicMessage] = []

        // Include conversation history, excluding the current callId since we add it below
        let history = await historyBuilder.buildAnthropicHistory(excludeToolCallIds: [callId])
        messages.append(contentsOf: history)

        // Build tool result message with interview context and optional instruction
        // Per Anthropic docs: tool_result blocks FIRST, then other content AFTER
        let resultContent = output.rawString() ?? "{}"
        var contentBlocks: [AnthropicContentBlock] = [
            .toolResult(AnthropicToolResultBlock(toolUseId: callId, content: resultContent))
        ]

        // If PDF data is provided, include it as a document block
        // This allows resumes to be sent directly to the LLM alongside the tool result
        if let pdfData = pdfBase64 {
            let docSource = AnthropicDocumentSource(mediaType: "application/pdf", data: pdfData)
            contentBlocks.append(.document(AnthropicDocumentBlock(source: docSource)))
            Logger.info("📄 Including PDF document block with tool result: \(pdfFilename ?? "unknown")", category: .ai)
        }

        // Build text content: interview_context + optional coordinator instruction
        var textParts: [String] = []

        // Include interview context so Claude always has current state
        if let interviewContext = await workingMemoryBuilder.buildInterviewContext() {
            textParts.append(interviewContext)
        }

        // Add coordinator instruction if provided
        if let instruction = instruction {
            textParts.append("<coordinator>\(instruction)</coordinator>")
            Logger.info("📋 Including coordinator instruction with tool result", category: .ai)
        }

        // Append text after tool_result if we have any
        if !textParts.isEmpty {
            contentBlocks.append(.text(AnthropicTextBlock(text: textParts.joined(separator: "\n\n"))))
        }

        messages.append(AnthropicMessage(role: "user", content: .blocks(contentBlocks)))

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

    /// Build a request containing multiple tool results.
    ///
    /// Per Anthropic best practices, instruction text can be included AFTER tool_result blocks.
    /// For batched results, include instruction from the last payload if present.
    func buildBatchedToolResponseRequest(payloads: [JSON]) async -> AnthropicMessageParameter {
        var messages: [AnthropicMessage] = []

        // Extract all callIds to exclude from history (we add them below)
        let excludeCallIds = Set(payloads.map { $0["callId"].stringValue })

        // Include conversation history, excluding the current callIds since we add them below
        let history = await historyBuilder.buildAnthropicHistory(excludeToolCallIds: excludeCallIds)
        messages.append(contentsOf: history)

        // Add all tool results in a single user message with multiple tool_result blocks
        // Per Anthropic docs: tool_result blocks FIRST, then text AFTER
        var contentBlocks: [AnthropicContentBlock] = []
        for payload in payloads {
            let callId = payload["callId"].stringValue
            let output = payload["output"]
            let resultContent = output.rawString() ?? "{}"
            contentBlocks.append(.toolResult(AnthropicToolResultBlock(
                toolUseId: callId,
                content: resultContent
            )))
        }

        // Build text content: interview_context + optional coordinator instruction
        var textParts: [String] = []

        // Include interview context so Claude always has current state
        if let interviewContext = await workingMemoryBuilder.buildInterviewContext() {
            textParts.append(interviewContext)
        }

        // Check for instruction in any payload (typically the last one for UI tool completions)
        if let instruction = payloads.last?["instruction"].string, !instruction.isEmpty {
            textParts.append("<coordinator>\(instruction)</coordinator>")
            Logger.info("📋 Including coordinator instruction with batched tool results", category: .ai)
        }

        // Append text after tool_result blocks if we have any
        if !textParts.isEmpty {
            contentBlocks.append(.text(AnthropicTextBlock(text: textParts.joined(separator: "\n\n"))))
        }

        messages.append(AnthropicMessage(role: "user", content: .blocks(contentBlocks)))

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

    /// Build system prompt - base personality only.
    /// Per Anthropic best practices, working memory and coordinator instructions
    /// are now included in user messages with XML tags (<interview_context>, <coordinator>).
    private func buildSystemPrompt() async -> String {
        // System prompt is stable - just base personality
        // Dynamic context (interview state, coordinator instructions) goes in user messages
        return baseDeveloperMessage
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
