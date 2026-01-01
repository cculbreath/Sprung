//
//  AnthropicRequestBuilder.swift
//  Sprung
//
//  Builds AnthropicMessageParameter requests for the Onboarding Interview's Anthropic Messages API calls.
//  Mirrors OnboardingRequestBuilder but for Anthropic's API format.
//

import Foundation
import SwiftOpenAI
import SwiftyJSON

/// Builds AnthropicMessageParameter requests for the Onboarding Interview's Anthropic Messages API calls.
/// Extracted to separate request construction from stream handling.
struct AnthropicRequestBuilder {
    private let baseDeveloperMessage: String
    private let toolRegistry: ToolRegistry
    private let contextAssembler: ConversationContextAssembler
    private let stateCoordinator: StateCoordinator

    init(
        baseDeveloperMessage: String,
        toolRegistry: ToolRegistry,
        contextAssembler: ConversationContextAssembler,
        stateCoordinator: StateCoordinator
    ) {
        self.baseDeveloperMessage = baseDeveloperMessage
        self.toolRegistry = toolRegistry
        self.contextAssembler = contextAssembler
        self.stateCoordinator = stateCoordinator
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
        // Always include full history for Anthropic
        let hasHistory = await contextAssembler.hasConversationHistory()
        if hasHistory {
            let history = await buildAnthropicHistory()
            messages.append(contentsOf: history)
            Logger.info("📋 Including \(history.count) messages from transcript", category: .ai)
        }

        // Build user message - with image if provided
        if let imageData = imageBase64 {
            let mimeType = imageContentType ?? "image/jpeg"
            let imageSource = AnthropicImageSource(mediaType: mimeType, data: imageData)

            let contentBlocks: [AnthropicContentBlock] = [
                .text(AnthropicTextBlock(text: text)),
                .image(AnthropicImageBlock(source: imageSource))
            ]
            messages.append(AnthropicMessage(role: "user", content: .blocks(contentBlocks)))
            Logger.info("🖼️ Including image attachment in user message (\(mimeType))", category: .ai)
        } else {
            messages.append(.user(text))
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
            toolChoice = .tool(name: forcedTool)
            Logger.info("🎯 Using forced toolChoice: \(forcedTool)", category: .ai)
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
        let tools = await getAnthropicTools()

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
        let hasHistory = await contextAssembler.hasConversationHistory()
        if hasHistory {
            let history = await buildAnthropicHistory()
            messages.append(contentsOf: history)
        }

        // For Anthropic, developer instructions go in the system prompt
        // We still need a user message to trigger a response
        // Use a minimal user prompt to represent the developer instruction
        messages.append(.user("[System instruction received - please continue the conversation]"))

        let toolChoice: AnthropicToolChoice
        if let toolName = toolChoiceName {
            toolChoice = .tool(name: toolName)
        } else {
            toolChoice = .auto
        }

        let tools = await getAnthropicTools()
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

        // Include conversation history
        let hasHistory = await contextAssembler.hasConversationHistory()
        if hasHistory {
            let history = await buildAnthropicHistory()
            messages.append(contentsOf: history)
        }

        // Add tool result as user message
        let resultContent = output.rawString() ?? "{}"
        messages.append(.toolResult(toolUseId: callId, content: resultContent))

        let toolChoice: AnthropicToolChoice
        if let forcedTool = forcedToolChoice {
            toolChoice = .tool(name: forcedTool)
            Logger.info("🔗 Forcing toolChoice to: \(forcedTool)", category: .ai)
        } else {
            toolChoice = .auto
        }

        let tools = await getAnthropicTools()
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
            "📝 Built Anthropic tool response request: callId=\(callId)",
            category: .ai
        )

        return parameters
    }

    // MARK: - Batched Tool Response Request

    func buildBatchedToolResponseRequest(payloads: [JSON]) async -> AnthropicMessageParameter {
        var messages: [AnthropicMessage] = []

        // Include conversation history
        let hasHistory = await contextAssembler.hasConversationHistory()
        if hasHistory {
            let history = await buildAnthropicHistory()
            messages.append(contentsOf: history)
        }

        // Add all tool results in a single user message with multiple tool_result blocks
        var toolResultBlocks: [AnthropicContentBlock] = []
        for payload in payloads {
            let callId = payload["call_id"].stringValue
            let output = payload["output"]
            let resultContent = output.rawString() ?? "{}"
            toolResultBlocks.append(.toolResult(AnthropicToolResultBlock(
                toolUseId: callId,
                content: resultContent
            )))
        }
        messages.append(AnthropicMessage(role: "user", content: .blocks(toolResultBlocks)))

        let tools = await getAnthropicTools()
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
        if let workingMemory = await buildWorkingMemory() {
            parts.append(workingMemory)
        }

        return parts.joined(separator: "\n\n")
    }

    // MARK: - History Building

    private func buildAnthropicHistory() async -> [AnthropicMessage] {
        // Get messages from transcript store through context assembler
        let inputItems = await contextAssembler.buildConversationHistory()

        var messages: [AnthropicMessage] = []

        for item in inputItems {
            switch item {
            case .message(let inputMessage):
                // Map roles: developer messages are skipped (go in system prompt)
                // user and assistant messages are converted directly
                switch inputMessage.role {
                case "user":
                    if case .text(let text) = inputMessage.content {
                        messages.append(.user(text))
                    }
                case "assistant":
                    if case .text(let text) = inputMessage.content {
                        messages.append(.assistant(text))
                    }
                default:
                    // Skip developer messages - they go in system prompt
                    break
                }
            case .functionToolCallOutput(let output):
                // Tool outputs become tool_result blocks
                messages.append(.toolResult(
                    toolUseId: output.callId,
                    content: output.output
                ))
            default:
                break
            }
        }

        return messages
    }

    // MARK: - Tool Conversion

    private func getAnthropicTools() async -> [AnthropicTool] {
        // Get current state for subphase inference
        let phase = await stateCoordinator.phase
        let toolPaneCard = await stateCoordinator.getCurrentToolPaneCard()
        let objectives = await stateCoordinator.getObjectiveStatusMap()

        // Infer current subphase from objectives + UI state
        let subphase = ToolBundlePolicy.inferSubphase(
            phase: phase,
            toolPaneCard: toolPaneCard,
            objectives: objectives
        )

        // Select tools based on subphase
        let bundledNames = ToolBundlePolicy.selectBundleForSubphase(subphase, toolChoice: nil)

        if bundledNames.isEmpty {
            Logger.debug("🔧 Anthropic tool bundling: subphase=\(subphase.rawValue), sending 0 tools", category: .ai)
            return []
        }

        // Get OpenAI Tool schemas and convert to Anthropic format
        let openAITools = await toolRegistry.toolSchemas(filteredBy: bundledNames)
        var anthropicTools: [AnthropicTool] = openAITools.compactMap { tool -> AnthropicTool? in
            guard case .function(let funcTool) = tool else { return nil }
            return convertToAnthropicTool(funcTool)
        }

        // Add web_search server-side tool
        anthropicTools.append(.serverTool(.webSearch()))

        Logger.debug(
            "🔧 Anthropic tool bundling: subphase=\(subphase.rawValue), sending \(anthropicTools.count) tools (incl. web_search)",
            category: .ai
        )

        return anthropicTools
    }

    private func convertToAnthropicTool(_ funcTool: Tool.FunctionTool) -> AnthropicTool {
        // Convert JSONSchema to dictionary for Anthropic's input_schema
        let inputSchema = convertJSONSchemaToDictionary(funcTool.parameters)

        return .function(AnthropicFunctionTool(
            name: funcTool.name,
            description: funcTool.description,
            inputSchema: inputSchema
        ))
    }

    private func convertJSONSchemaToDictionary(_ schema: JSONSchema) -> [String: Any] {
        var result: [String: Any] = [:]

        // Type - convert JSONSchemaType to string
        if let schemaType = schema.type {
            result["type"] = jsonSchemaTypeToString(schemaType)
        }

        // Properties
        if let properties = schema.properties {
            var propsDict: [String: Any] = [:]
            for (key, propSchema) in properties {
                propsDict[key] = convertJSONSchemaToDictionary(propSchema)
            }
            result["properties"] = propsDict
        }

        // Required
        if let required = schema.required {
            result["required"] = required
        }

        // Description
        if let description = schema.description {
            result["description"] = description
        }

        // Items (for arrays)
        if let items = schema.items {
            result["items"] = convertJSONSchemaToDictionary(items)
        }

        // Enum (JSONSchema uses backtick `enum`)
        if let enumValues = schema.`enum` {
            result["enum"] = enumValues
        }

        // Additional properties (simple Bool? in JSONSchema)
        if let additionalProps = schema.additionalProperties {
            result["additionalProperties"] = additionalProps
        }

        return result
    }

    /// Convert JSONSchemaType to its string representation
    private func jsonSchemaTypeToString(_ type: JSONSchemaType) -> String {
        switch type {
        case .string: return "string"
        case .number: return "number"
        case .integer: return "integer"
        case .boolean: return "boolean"
        case .object: return "object"
        case .array: return "array"
        case .null: return "null"
        case .union(let types):
            // For union types, return the first non-null type
            // (Anthropic doesn't support union types directly)
            if let firstType = types.first(where: { $0 != .null }) {
                return jsonSchemaTypeToString(firstType)
            }
            return "string"
        }
    }

    // MARK: - Working Memory

    private func buildWorkingMemory() async -> String? {
        let phase = await stateCoordinator.phase

        var parts: [String] = []
        parts.append("## Working Memory (Phase: \(phase.shortName))")

        let currentPanel = await stateCoordinator.getCurrentToolPaneCard()
        if currentPanel != .none {
            parts.append("Visible UI: \(currentPanel.rawValue)")
        } else {
            parts.append("Visible UI: none (call upload/prompt tools to show UI)")
        }

        let objectives = await stateCoordinator.getObjectivesForPhase(phase)
        if !objectives.isEmpty {
            let statusList = objectives.map { "\($0.id): \($0.status.rawValue)" }
            parts.append("Objectives: \(statusList.joined(separator: ", "))")
        }

        let artifacts = await stateCoordinator.artifacts
        if let entries = artifacts.skeletonTimeline?["experiences"].array, !entries.isEmpty {
            let timelineSummary = entries.prefix(6).compactMap { entry -> String? in
                guard let org = entry["organization"].string,
                      let title = entry["title"].string else { return nil }
                let dates = [entry["start"].string, entry["end"].string]
                    .compactMap { $0 }
                    .joined(separator: "-")
                return "\(title) @ \(org)" + (dates.isEmpty ? "" : " (\(dates))")
            }
            if !timelineSummary.isEmpty {
                parts.append("Timeline (\(entries.count) entries): \(timelineSummary.joined(separator: "; "))")
            }
        }

        let artifactSummaries = await stateCoordinator.listArtifactSummaries()
        if !artifactSummaries.isEmpty {
            let artifactSummary = artifactSummaries.prefix(6).compactMap { record -> String? in
                guard let filename = record["filename"].string else { return nil }
                let desc = record["brief_description"].string ?? record["summary"].string ?? ""
                let shortDesc = desc.isEmpty ? "" : " - \(String(desc.prefix(40)))"
                return filename + shortDesc
            }
            if !artifactSummary.isEmpty {
                parts.append("Artifacts (\(artifactSummaries.count)): \(artifactSummary.joined(separator: "; "))")
            }
        }

        let dossierNotes = await stateCoordinator.getDossierNotes()
        if !dossierNotes.isEmpty {
            let truncatedNotes = String(dossierNotes.prefix(800))
            parts.append("Dossier Notes:\n\(truncatedNotes)")
        }

        guard parts.count > 1 else { return nil }

        let memory = parts.joined(separator: "\n")
        let maxChars = 2500
        if memory.count > maxChars {
            Logger.warning("⚠️ WorkingMemory exceeds target (\(memory.count) chars)", category: .ai)
            return String(memory.prefix(maxChars))
        }

        Logger.debug("📋 WorkingMemory: \(memory.count) chars", category: .ai)
        return memory
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
        return UserDefaults.standard.string(forKey: "onboardingAnthropicModelId") ?? "claude-sonnet-4-20250514"
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
