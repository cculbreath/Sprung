//
//  OnboardingRequestBuilder.swift
//  Sprung
//
//  Request building logic extracted from LLMMessenger
//
import Foundation
import SwiftOpenAI
import SwiftyJSON

/// Builds ModelResponseParameter requests for the Onboarding Interview's Responses API calls
/// Extracted from LLMMessenger to separate request construction from stream handling
struct OnboardingRequestBuilder {
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
    ) async -> ModelResponseParameter {
        let previousResponseId = await contextAssembler.getPreviousResponseId()
        var inputItems: [InputItem] = []

        // If no previous response ID, we need to include full context
        // This happens on fresh start or after checkpoint restore
        if previousResponseId == nil {
            // Include base developer message (system prompt)
            inputItems.append(.message(InputMessage(
                role: "developer",
                content: .text(baseDeveloperMessage)
            )))

            // Include conversation history if this is a restore (not first message)
            let hasHistory = await contextAssembler.hasConversationHistory()
            if hasHistory {
                let history = await contextAssembler.buildConversationHistory()
                inputItems.append(contentsOf: history)
                Logger.info("📋 Checkpoint restore: including \(history.count) messages from transcript", category: .ai)
            } else {
                Logger.info("📋 Fresh start: including base developer message", category: .ai)
            }
        }

        // Include bundled developer messages (status updates, etc.) before the user message
        // These are included in the same request to avoid separate LLM turns
        for devPayload in bundledDeveloperMessages {
            let devText = devPayload["text"].stringValue
            if !devText.isEmpty {
                inputItems.append(.message(InputMessage(
                    role: "developer",
                    content: .text(devText)
                )))
            }
        }
        if !bundledDeveloperMessages.isEmpty {
            Logger.info("📦 Included \(bundledDeveloperMessages.count) bundled developer message(s) in request", category: .ai)
        }

        // Build user message - with image if provided
        if let imageData = imageBase64 {
            // Build multimodal message with text + image
            let mimeType = imageContentType ?? "image/jpeg"
            let dataUrl = "data:\(mimeType);base64,\(imageData)"

            var contentItems: [ContentItem] = [.text(TextContent(text: text))]
            contentItems.append(.image(ImageContent(imageUrl: dataUrl)))

            inputItems.append(.message(InputMessage(
                role: "user",
                content: .array(contentItems)
            )))
            Logger.info("🖼️ Including image attachment in user message (\(mimeType))", category: .ai)
        } else {
            inputItems.append(.message(InputMessage(
                role: "user",
                content: .text(text)
            )))
        }

        // Determine tool choice first (needed for tool bundling)
        // If we have a queued forced tool choice (from a workflow developer message),
        // apply it to the next request as a one-shot override.
        let effectiveForcedToolChoice: String?
        if let forcedToolChoice {
            effectiveForcedToolChoice = forcedToolChoice
        } else {
            effectiveForcedToolChoice = await stateCoordinator.popPendingForcedToolChoice()
        }
        let toolChoice: ToolChoiceMode
        if let forcedTool = effectiveForcedToolChoice {
            toolChoice = .functionTool(FunctionTool(name: forcedTool))
            Logger.info("🎯 Using forced toolChoice: \(forcedTool)", category: .ai)
        } else {
            toolChoice = await determineToolChoice(for: text, isSystemGenerated: isSystemGenerated)
        }

        // Get tools with bundling based on toolChoice
        let tools = await getToolSchemas(for: toolChoice)

        let modelId = await stateCoordinator.getCurrentModelId()
        let useFlexTier = await stateCoordinator.getUseFlexProcessing()

        // Build WorkingMemory for instructions (non-persistent context)
        let workingMemory = await buildWorkingMemory()

        var parameters = ModelResponseParameter(
            input: .array(inputItems),
            model: .custom(modelId),
            conversation: nil,
            instructions: workingMemory,  // WorkingMemory snapshot (non-persistent, high priority)
            previousResponseId: previousResponseId,
            store: true,
            temperature: 1.0,
            text: TextConfiguration(format: .text)
        )
        parameters.stream = true
        parameters.toolChoice = toolChoice
        parameters.tools = tools
        parameters.parallelToolCalls = await shouldEnableParallelToolCalls()
        if useFlexTier {
            parameters.serviceTier = "flex"
        }
        // Apply extended cache retention if enabled in settings
        let useCacheRetention = UserDefaults.standard.bool(forKey: "onboardingInterviewPromptCacheRetention")
        if useCacheRetention {
            parameters.promptCacheRetention = "24h"
        }
        // Apply default reasoning effort from settings, with summary enabled for UI display
        let effectiveReasoning = await stateCoordinator.getDefaultReasoningEffort()
        if effectiveReasoning != "none" {
            parameters.reasoning = Reasoning(effort: effectiveReasoning, summary: .auto)
        }
        Logger.info(
            "📝 Built request: previousResponseId=\(previousResponseId?.description ?? "nil"), inputItems=\(inputItems.count), parallelToolCalls=\(parameters.parallelToolCalls?.description ?? "nil"), serviceTier=\(parameters.serviceTier ?? "default"), cacheRetention=\(useCacheRetention ? "24h" : "default"), reasoningEffort=\(effectiveReasoning)",
            category: .ai
        )

        // Log telemetry for token budget tracking
        let currentPhase = await stateCoordinator.phase
        RequestTelemetry(
            phase: currentPhase.rawValue,
            substate: nil,
            toolsSentCount: tools.count,
            instructionsChars: workingMemory?.count ?? 0,
            bundledDevMsgsCount: bundledDeveloperMessages.count,
            inputTokens: nil,  // Will be populated after response
            outputTokens: nil,
            cachedTokens: nil,
            isFirstTurn: previousResponseId == nil,
            requestType: .userMessage
        ).log()

        return parameters
    }

    // MARK: - Developer Message Request

    func buildDeveloperMessageRequest(
        text: String,
        toolChoice toolChoiceName: String? = nil,
        reasoningEffort: String? = nil
    ) async -> ModelResponseParameter {
        let previousResponseId = await contextAssembler.getPreviousResponseId()
        var inputItems: [InputItem] = []
        if previousResponseId == nil {
            inputItems.append(.message(InputMessage(
                role: "developer",
                content: .text(baseDeveloperMessage)
            )))
            Logger.info("📋 Including base developer message (first request)", category: .ai)
        }
        inputItems.append(.message(InputMessage(
            role: "developer",
            content: .text(text)
        )))

        // Determine tool choice first (needed for tool bundling)
        let toolChoice: ToolChoiceMode
        if let toolName = toolChoiceName {
            toolChoice = .functionTool(FunctionTool(name: toolName))
        } else {
            toolChoice = .auto
        }

        // Get tools with bundling based on toolChoice
        let tools = await getToolSchemas(for: toolChoice)

        let modelId = await stateCoordinator.getCurrentModelId()
        let useFlexTier = await stateCoordinator.getUseFlexProcessing()

        // Build WorkingMemory for instructions (non-persistent context)
        let workingMemory = await buildWorkingMemory()

        var parameters = ModelResponseParameter(
            input: .array(inputItems),
            model: .custom(modelId),
            conversation: nil,
            instructions: workingMemory,  // WorkingMemory snapshot (non-persistent, high priority)
            previousResponseId: previousResponseId,
            store: true,
            temperature: 1.0,
            text: TextConfiguration(format: .text)
        )
        parameters.stream = true
        parameters.toolChoice = toolChoice
        parameters.tools = tools
        parameters.parallelToolCalls = await shouldEnableParallelToolCalls()
        if useFlexTier {
            parameters.serviceTier = "flex"
        }
        // Apply extended cache retention if enabled in settings
        let useCacheRetention = UserDefaults.standard.bool(forKey: "onboardingInterviewPromptCacheRetention")
        if useCacheRetention {
            parameters.promptCacheRetention = "24h"
        }
        // Set reasoning effort (use provided value or default from settings), with summary enabled
        let defaultReasoning = await stateCoordinator.getDefaultReasoningEffort()
        let effectiveReasoning = reasoningEffort ?? defaultReasoning
        if effectiveReasoning != "none" {
            parameters.reasoning = Reasoning(effort: effectiveReasoning, summary: .auto)
        }
        let toolChoiceDesc: String
        switch toolChoice {
        case .auto:
            toolChoiceDesc = "auto"
        case .none:
            toolChoiceDesc = "none"
        case .required:
            toolChoiceDesc = "required"
        case .functionTool(let ft):
            toolChoiceDesc = "function(\(ft.name))"
        case .allowedTools(let at):
            toolChoiceDesc = "allowedTools(\(at.tools.map { $0.name }.joined(separator: ", ")))"
        case .hostedTool(let ht):
            toolChoiceDesc = "hostedTool(\(ht))"
        case .customTool(let ct):
            toolChoiceDesc = "customTool(\(ct.name))"
        }
        Logger.info(
            """
            📝 Built developer message request: \
            previousResponseId=\(previousResponseId?.description ?? "nil"), \
            inputItems=\(inputItems.count), \
            toolChoice=\(toolChoiceDesc), \
            parallelToolCalls=\(parameters.parallelToolCalls?.description ?? "nil"), \
            reasoningEffort=\(effectiveReasoning)
            """,
            category: .ai
        )

        // Log telemetry for token budget tracking
        let currentPhase = await stateCoordinator.phase
        RequestTelemetry(
            phase: currentPhase.rawValue,
            substate: nil,
            toolsSentCount: tools.count,
            instructionsChars: workingMemory?.count ?? 0,
            bundledDevMsgsCount: 0,
            inputTokens: nil,
            outputTokens: nil,
            cachedTokens: nil,
            isFirstTurn: previousResponseId == nil,
            requestType: .developerMessage
        ).log()

        return parameters
    }

    // MARK: - Tool Response Request

    func buildToolResponseRequest(
        output: JSON,
        callId: String,
        reasoningEffort: String? = nil,
        forcedToolChoice: String? = nil
    ) async -> ModelResponseParameter {
        let inputItems = await contextAssembler.buildForToolResponse(
            output: output,
            callId: callId
        )

        // Determine tool choice first (needed for tool bundling)
        let toolChoice: ToolChoiceMode
        if let forcedTool = forcedToolChoice {
            toolChoice = .functionTool(FunctionTool(name: forcedTool))
            Logger.info("🔗 Forcing toolChoice to: \(forcedTool)", category: .ai)
        } else {
            toolChoice = .auto
        }

        // Get tools with bundling based on toolChoice
        let tools = await getToolSchemas(for: toolChoice)

        let modelId = await stateCoordinator.getCurrentModelId()
        let useFlexTier = await stateCoordinator.getUseFlexProcessing()
        let previousResponseId = await contextAssembler.getPreviousResponseId()

        // Build WorkingMemory for instructions (non-persistent context)
        let workingMemory = await buildWorkingMemory()

        var parameters = ModelResponseParameter(
            input: .array(inputItems),
            model: .custom(modelId),
            conversation: nil,
            instructions: workingMemory,  // WorkingMemory snapshot (non-persistent, high priority)
            previousResponseId: previousResponseId,
            store: true,
            temperature: 1.0,
            text: TextConfiguration(format: .text)
        )
        parameters.stream = true
        parameters.toolChoice = toolChoice
        parameters.tools = tools
        parameters.parallelToolCalls = await shouldEnableParallelToolCalls()
        if useFlexTier {
            parameters.serviceTier = "flex"
        }
        // Apply extended cache retention if enabled in settings
        let useCacheRetention = UserDefaults.standard.bool(forKey: "onboardingInterviewPromptCacheRetention")
        if useCacheRetention {
            parameters.promptCacheRetention = "24h"
        }
        // Set reasoning effort (use provided value or default from settings), with summary enabled
        let defaultReasoning = await stateCoordinator.getDefaultReasoningEffort()
        let effectiveReasoning = reasoningEffort ?? defaultReasoning
        if effectiveReasoning != "none" {
            parameters.reasoning = Reasoning(effort: effectiveReasoning, summary: .auto)
        }
        Logger.info("📝 Built tool response request: parallelToolCalls=\(parameters.parallelToolCalls?.description ?? "nil"), toolChoice=\(forcedToolChoice ?? "auto"), serviceTier=\(parameters.serviceTier ?? "default"), cacheRetention=\(useCacheRetention ? "24h" : "default"), reasoningEffort=\(effectiveReasoning)", category: .ai)

        // Log telemetry for token budget tracking
        let currentPhase = await stateCoordinator.phase
        RequestTelemetry(
            phase: currentPhase.rawValue,
            substate: nil,
            toolsSentCount: tools.count,
            instructionsChars: workingMemory?.count ?? 0,
            bundledDevMsgsCount: 0,
            inputTokens: nil,
            outputTokens: nil,
            cachedTokens: nil,
            isFirstTurn: false,  // Tool responses are never first turn
            requestType: .toolResponse
        ).log()

        return parameters
    }

    // MARK: - Batched Tool Response Request

    func buildBatchedToolResponseRequest(payloads: [JSON]) async -> ModelResponseParameter {
        let inputItems = await contextAssembler.buildForBatchedToolResponses(payloads: payloads)
        // Batched tool responses use auto toolChoice
        let toolChoice: ToolChoiceMode = .auto
        let tools = await getToolSchemas(for: toolChoice)

        let modelId = await stateCoordinator.getCurrentModelId()
        let useFlexTier = await stateCoordinator.getUseFlexProcessing()
        let previousResponseId = await contextAssembler.getPreviousResponseId()

        // Build WorkingMemory for instructions (non-persistent context)
        let workingMemory = await buildWorkingMemory()

        var parameters = ModelResponseParameter(
            input: .array(inputItems),
            model: .custom(modelId),
            conversation: nil,
            instructions: workingMemory,  // WorkingMemory snapshot (non-persistent, high priority)
            previousResponseId: previousResponseId,
            store: true,
            temperature: 1.0,
            text: TextConfiguration(format: .text)
        )
        parameters.stream = true
        parameters.toolChoice = toolChoice
        parameters.tools = tools
        parameters.parallelToolCalls = await shouldEnableParallelToolCalls()
        if useFlexTier {
            parameters.serviceTier = "flex"
        }
        // Apply extended cache retention if enabled in settings
        let useCacheRetention = UserDefaults.standard.bool(forKey: "onboardingInterviewPromptCacheRetention")
        if useCacheRetention {
            parameters.promptCacheRetention = "24h"
        }
        // Apply default reasoning effort from settings, with summary enabled
        let effectiveReasoning = await stateCoordinator.getDefaultReasoningEffort()
        if effectiveReasoning != "none" {
            parameters.reasoning = Reasoning(effort: effectiveReasoning, summary: .auto)
        }
        Logger.info("📝 Built batched tool response request: \(inputItems.count) tool outputs, parallelToolCalls=\(parameters.parallelToolCalls?.description ?? "nil"), serviceTier=\(parameters.serviceTier ?? "default"), cacheRetention=\(useCacheRetention ? "24h" : "default"), reasoningEffort=\(effectiveReasoning)", category: .ai)

        // Log telemetry for token budget tracking
        let currentPhase = await stateCoordinator.phase
        RequestTelemetry(
            phase: currentPhase.rawValue,
            substate: nil,
            toolsSentCount: tools.count,
            instructionsChars: workingMemory?.count ?? 0,
            bundledDevMsgsCount: 0,
            inputTokens: nil,
            outputTokens: nil,
            cachedTokens: nil,
            isFirstTurn: false,  // Batched tool responses are never first turn
            requestType: .batchedToolResponse
        ).log()

        return parameters
    }

    // MARK: - Tool Choice

    /// Determine appropriate tool_choice for the given message context
    private func determineToolChoice(for text: String, isSystemGenerated: Bool) async -> ToolChoiceMode {
        if isSystemGenerated {
            return .auto
        }
        let hasStreamed = await stateCoordinator.getHasStreamedFirstResponse()
        if !hasStreamed {
            Logger.info("🚫 Forcing toolChoice=.none for first user request to ensure greeting", category: .ai)
            return .none
        }
        return .auto
    }

    // MARK: - Tool Schemas

    /// Get tool schemas from ToolRegistry, filtered by allowed tools using subphase-aware bundling
    /// - Parameter toolChoice: Optional tool choice mode to override bundling
    private func getToolSchemas(for toolChoice: ToolChoiceMode? = nil) async -> [Tool] {
        // Get base allowed tools from state coordinator
        let allowedNames = await stateCoordinator.getAllowedToolNames()

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

        // Select tools based on subphase (handles toolChoice internally)
        let bundledNames = ToolBundlePolicy.selectBundleForSubphase(
            subphase,
            allowedTools: allowedNames,
            toolChoice: toolChoice
        )

        // Handle empty bundle case
        if bundledNames.isEmpty {
            Logger.debug("🔧 Tool bundling: subphase=\(subphase.rawValue), sending 0 tools", category: .ai)
            return []
        }

        let schemas = await toolRegistry.toolSchemas(filteredBy: bundledNames)
        Logger.debug("🔧 Tool bundling: subphase=\(subphase.rawValue), toolPane=\(toolPaneCard.rawValue), sending \(schemas.count) tools: \(bundledNames.sorted().joined(separator: ", "))", category: .ai)

        return schemas
    }

    // MARK: - Parallel Tool Calls

    /// Determine if parallel tool calls should be enabled based on current state
    /// Enabled for Phase 1 (skeleton timeline) and Phase 2 (document collection/KC generation)
    private func shouldEnableParallelToolCalls() async -> Bool {
        let currentPhase = await stateCoordinator.phase

        // Enable parallel tool calls for Phase 1 and Phase 2
        // Phase 1: skeleton timeline extraction and validation
        // Phase 2: document collection and KC generation
        return currentPhase == .phase1CoreFacts || currentPhase == .phase2DeepDive
    }

    // MARK: - Working Memory

    /// Build a compact WorkingMemory snapshot for the `instructions` parameter
    /// The `instructions` parameter doesn't persist in the PRI thread, making it
    /// ideal for providing rich context on every turn without growing the thread.
    private func buildWorkingMemory() async -> String? {
        let phase = await stateCoordinator.phase

        var parts: [String] = []

        // Phase header
        parts.append("## Working Memory (Phase: \(phase.shortName))")

        // Current visible UI panel (helps LLM know what user sees)
        let currentPanel = await stateCoordinator.getCurrentToolPaneCard()
        if currentPanel != .none {
            parts.append("Visible UI: \(currentPanel.rawValue)")
        } else {
            parts.append("Visible UI: none (call upload/prompt tools to show UI)")
        }

        // Objectives status (filtered to current phase)
        let objectives = await stateCoordinator.getObjectivesForPhase(phase)
        if !objectives.isEmpty {
            let statusList = objectives.map { "\($0.id): \($0.status.rawValue)" }
            parts.append("Objectives: \(statusList.joined(separator: ", "))")
        }

        // Timeline summary
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

        // Artifact summary
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

        // Dossier WIP notes (scratchpad for LLM to track dossier info during interview)
        let dossierNotes = await stateCoordinator.getDossierNotes()
        if !dossierNotes.isEmpty {
            // Truncate to prevent exceeding memory budget
            let truncatedNotes = String(dossierNotes.prefix(800))
            parts.append("Dossier Notes:\n\(truncatedNotes)")
        }

        // Only return if we have meaningful content
        guard parts.count > 1 else { return nil }

        let memory = parts.joined(separator: "\n")

        // Enforce max size (target ~2KB)
        let maxChars = 2500
        if memory.count > maxChars {
            Logger.warning("⚠️ WorkingMemory exceeds target (\(memory.count) chars)", category: .ai)
            return String(memory.prefix(maxChars))
        }

        Logger.debug("📋 WorkingMemory: \(memory.count) chars", category: .ai)
        return memory
    }
}
