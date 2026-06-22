//
//  AnthropicRequestBuilder.swift
//  Sprung
//
//  Builds AnthropicMessageParameter requests for the Onboarding Interview's Anthropic Messages API calls.
//  Delegates to specialized components for history building, tool conversion, and working memory.
//
//  PROMPT-CACHE INVARIANT: the request prefix (tools → system → history) must be
//  byte-identical between consecutive turns within a phase:
//  - Tools: full phase union, sorted by name (AnthropicToolConverter) — only
//    changes at phase boundaries.
//  - System: static base prompt with a cache breakpoint (cache_control: ephemeral
//    on the system block caches tools+system together). Volatile content (todo
//    list, interview context, coordinator guidance) lives in the latest user
//    message, never in the system prompt.
//  - History: the exact merged wire text of each sent turn — including chatbox
//    attachments and tool_result strings — is written back to ConversationLog at
//    build time so the next request replays identical bytes.
//
//  ACCEPTANCE INVARIANT: building the same request twice with no new
//  ConversationLog entries must produce byte-identical messages JSON; building
//  turn N+1 must reproduce turn N's messages as an exact prefix (modulo
//  cache_control placement, which the API ignores for prefix matching).
//
//  CACHE BREAKPOINTS (applied at request-build time only, never persisted, so
//  they "move" naturally each turn — placed by AnthropicCacheBreakpointPlanner):
//  1. System block (always, when a system prompt exists).
//  2. Last cacheable content block of the final message — incremental
//     conversation caching: turn N+1 reads the prefix turn N wrote.
//  3. Last document block in the array (if any) — caching through the largest
//     payload covers all earlier blocks.
//  4. If total content blocks > 20, the last block of the message ~20 blocks
//     before the end — keeps a boundary inside Anthropic's 20-block lookback
//     window after tool-heavy turns.
//  HARD CLAMP: max 4 cache_control blocks per request INCLUDING system; drop
//  breakpoint 4 first, then 3 (see AnthropicCacheBreakpointPlanner.clampBreakpointCandidates).
//

import Foundation
import SwiftOpenAI
import SwiftyJSON

/// Builds AnthropicMessageParameter requests for the Onboarding Interview's Anthropic Messages API calls.
/// Extracted to separate request construction from stream handling.
struct AnthropicRequestBuilder {
    private let baseSystemPrompt: String
    private let stateCoordinator: StateCoordinator
    private let historyBuilder: AnthropicHistoryBuilder
    private let toolConverter: AnthropicToolConverter
    private let workingMemoryBuilder: WorkingMemoryBuilder
    /// Per-request prefix fingerprinting — logs the first divergent block when
    /// the byte-stability invariant breaks (see CachePrefixAuditor).
    private let cacheAuditor = CachePrefixAuditor()
    /// Shared message-tier breakpoint placement: the moving tail + >20-block
    /// lookback, .ephemeral TTL, reserving the system block (0 or 1). The full
    /// onboarding policy — see AnthropicCacheBreakpointPlanner.
    private let breakpointPlanner: AnthropicCacheBreakpointPlanner

    init(
        baseSystemPrompt: String,
        toolRegistry: ToolRegistry,
        contextAssembler: ConversationContextAssembler,
        stateCoordinator: StateCoordinator,
        todoStore: InterviewTodoStore
    ) {
        self.baseSystemPrompt = baseSystemPrompt
        self.stateCoordinator = stateCoordinator
        self.historyBuilder = AnthropicHistoryBuilder(contextAssembler: contextAssembler)
        self.toolConverter = AnthropicToolConverter(toolRegistry: toolRegistry, stateCoordinator: stateCoordinator)
        self.workingMemoryBuilder = WorkingMemoryBuilder(stateCoordinator: stateCoordinator, todoStore: todoStore)
        self.breakpointPlanner = AnthropicCacheBreakpointPlanner(
            cacheControl: .ephemeral,
            reservedBreakpointCount: baseSystemPrompt.isEmpty ? 0 : 1
        )
    }

    // MARK: - User Message Request

    func buildUserMessageRequest(
        text: String,
        isSystemGenerated: Bool,
        entryId: UUID? = nil,
        bundledCoordinatorMessages: [JSON] = [],
        imageBase64: String? = nil,
        imageContentType: String? = nil
    ) async throws -> AnthropicMessageParameter {
        // Resolve the model FIRST: it can throw, and the user entry must never be
        // created for a request that fails to build (the entry would replay in
        // history for a message the model never received).
        let modelId = try await stateCoordinator.getAnthropicModelId()

        // Build full message text with XML tags (Anthropic-native pattern)
        // Order: <interview_context> + <coordinator> + <chatbox> or raw text
        var fullMessageParts: [String] = []

        // 1. Interview context (volatile tail: state, objectives, todo list)
        if let interviewContext = await workingMemoryBuilder.buildInterviewContext() {
            fullMessageParts.append(interviewContext)
        }

        // 1b. Late tool results — delivered at the tail instead of mutating the
        // frozen tool_result bytes earlier in history (prompt-cache invariant).
        if let updates = await renderToolResultUpdates() {
            fullMessageParts.append(updates)
        }

        // 2. Coordinator instructions (app-generated guidance for the model)
        for devPayload in bundledCoordinatorMessages {
            let devText = devPayload["text"].stringValue
            if !devText.isEmpty {
                fullMessageParts.append("<coordinator>\(devText)</coordinator>")
            }
        }

        // 3. The actual message text (already tagged with <chatbox> if from user)
        fullMessageParts.append(text)

        let fullMessageText = fullMessageParts.joined(separator: "\n\n")

        // Chatbox attachment (image or PDF) for this turn. Recorded in the log
        // alongside the wire text so every later history rebuild replays the
        // attachment block in its original position — byte-identical prefix.
        let attachment: ConversationLog.WireAttachment? = imageBase64.map { fileData in
            ConversationLog.WireAttachment(
                base64Data: fileData,
                mediaType: imageContentType ?? "image/jpeg"
            )
        }

        // SEND-ORDER INVARIANT: the user entry is created HERE, at request-build
        // time — request builds are serialized behind any in-flight stream, so the
        // assistant entry from a stream that was running when this message was
        // enqueued has already been appended, and the log stays strictly
        // send-ordered (a rebuilt history can never end with an assistant turn).
        // Idempotent on entryId: a retried build re-uses the same entry.
        //
        // PROMPT-CACHE INVARIANT: write the exact wire text (and attachment) back
        // to the log BEFORE building history, so this turn (and every replay of it)
        // serializes the same bytes, keyed to this exact entry.
        let wireTextCaptured: Bool
        if let entryId {
            await stateCoordinator.appendUserMessage(text, id: entryId, isSystemGenerated: isSystemGenerated)
            wireTextCaptured = await stateCoordinator.setUserMessageWireText(entryId: entryId, fullMessageText)
            if wireTextCaptured, let attachment {
                await stateCoordinator.setUserMessageAttachment(entryId: entryId, attachment)
                Logger.info("📎 Captured \(attachment.mediaType) attachment for byte-stable replay", category: .ai)
            }
        } else {
            Logger.warning("⚠️ User-message payload missing entryId - wire text not captured (replay uses display text)", category: .ai)
            wireTextCaptured = false
        }

        // Build conversation history (Anthropic uses explicit messages, no PRI).
        // When the capture succeeded, the trailing user message already carries
        // the merged wire text AND the attachment block — send and replay share
        // the same construction path by design.
        var messages = await historyBuilder.buildAnthropicHistory()
        Logger.info("📋 Including \(messages.count) messages from transcript", category: .ai)

        if !wireTextCaptured {
            // Defensive: wire text could not be keyed to a log entry (missing
            // entryId, or no user entry with that id) — send the merged text and
            // attachment directly (replay will fall back to the entry's display
            // text; one-time cache rebuild). Merge into a trailing user message
            // if present to preserve role alternation.
            Logger.warning("⚠️ Wire text not captured in log - sending merged text directly", category: .ai)
            var newBlocks: [AnthropicContentBlock] = [.text(AnthropicTextBlock(text: fullMessageText))]
            if let attachment {
                newBlocks.append(historyBuilder.attachmentBlock(for: attachment))
            }
            if let lastIndex = messages.indices.last, messages[lastIndex].role == "user" {
                let existingBlocks = historyBuilder.extractContentBlocks(messages[lastIndex])
                messages[lastIndex] = AnthropicMessage(role: "user", content: .blocks(existingBlocks + newBlocks))
            } else {
                messages.append(AnthropicMessage(role: "user", content: .blocks(newBlocks)))
            }
        }

        // Message-block cache breakpoints (post-processing, build-time only)
        messages = breakpointPlanner.plan(messages: messages)

        // Determine tool choice - prefer auto, only use .none for the first greeting
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

        let tools = await toolConverter.getAnthropicTools()

        let parameters = AnthropicMessageParameter(
            model: modelId,
            messages: messages,
            system: cacheableSystem(),
            maxTokens: OnboardingLLMConfig.maxTokens,
            stream: true,
            tools: tools.isEmpty ? nil : tools,
            toolChoice: toolChoice == .none && tools.isEmpty ? nil : toolChoice
        )

        Logger.info(
            "📝 Built Anthropic request: messages=\(messages.count), tools=\(tools.count)",
            category: .ai
        )

        cacheAuditor.audit(tools: tools, system: baseSystemPrompt, messages: messages)

        return parameters
    }

    // MARK: - Coordinator Message Request

    /// Build a request with coordinator instructions.
    /// Per Anthropic best practices, coordinator instructions are sent as user messages
    /// with <coordinator> XML tags, not stuffed into system prompt.
    func buildCoordinatorMessageRequest(
        text: String
    ) async throws -> AnthropicMessageParameter {
        // Resolve the model FIRST: it can throw, and a coordinator wire turn (and
        // any drained tool-result updates) must never be consumed by a request
        // that fails to build.
        let modelId = try await stateCoordinator.getAnthropicModelId()

        // Build message with interview context + coordinator instruction
        var messageParts: [String] = []

        // 1. Interview context (volatile tail)
        if let interviewContext = await workingMemoryBuilder.buildInterviewContext() {
            messageParts.append(interviewContext)
        }

        // 1b. Late tool results (cache-stable tail delivery)
        if let updates = await renderToolResultUpdates() {
            messageParts.append(updates)
        }

        // 2. Coordinator instruction (app-generated guidance)
        messageParts.append("<coordinator>\(text)</coordinator>")

        let fullMessageText = messageParts.joined(separator: "\n\n")

        // PROMPT-CACHE INVARIANT: coordinator turns have no ConversationEntry, so
        // record a wire-only turn in the log BEFORE building history — the turn
        // then appears here and replays byte-identically on every later request.
        await stateCoordinator.recordCoordinatorWireTurn(fullMessageText)

        // Build history — it now ends with the coordinator wire turn
        // (message-block cache breakpoints applied as build-time post-processing)
        let messages = breakpointPlanner.plan(messages: await historyBuilder.buildAnthropicHistory())

        let tools = await toolConverter.getAnthropicTools()

        let parameters = AnthropicMessageParameter(
            model: modelId,
            messages: messages,
            system: cacheableSystem(),
            maxTokens: OnboardingLLMConfig.maxTokens,
            stream: true,
            tools: tools.isEmpty ? nil : tools,
            toolChoice: tools.isEmpty ? nil : .auto
        )

        Logger.info(
            "📝 Built Anthropic coordinator message request: messages=\(messages.count)",
            category: .ai
        )

        cacheAuditor.audit(tools: tools, system: baseSystemPrompt, messages: messages)

        return parameters
    }

    // MARK: - Tool Response Request

    /// Build a request after a tool has completed.
    ///
    /// The tool result is already stored in ConversationLog (via setToolResult).
    /// The computed context (interview state, optional coordinator instruction) is
    /// written to the log as the assistant entry's tool-turn context text, then
    /// history is rebuilt — so the trailing tool_result user message carries the
    /// exact blocks that will replay on subsequent turns.
    ///
    /// PDF attachments are NOT passed separately: tool outputs containing
    /// pdfAttachment.storageUrl are re-included as document blocks by
    /// AnthropicHistoryBuilder on every build, which keeps send and replay bytes
    /// identical.
    ///
    /// - Parameters:
    ///   - callId: The tool call ID (for logging)
    ///   - instruction: Optional instruction text to include after the tool_result.
    ///     This provides immediate guidance to Claude for the next action.
    func buildToolResponseRequest(
        callId: String,
        instruction: String? = nil
    ) async throws -> AnthropicMessageParameter {
        // Resolve the model FIRST: it can throw, and drained tool-result updates
        // must never be consumed by a request that fails to build.
        let modelId = try await stateCoordinator.getAnthropicModelId()

        // Build computed context: interview_context + optional coordinator instruction
        var textParts: [String] = []

        if let interviewContext = await workingMemoryBuilder.buildInterviewContext() {
            textParts.append(interviewContext)
        }

        // Late tool results whose history bytes are frozen (placeholder/synthetic)
        // — delivered here at the tail, where they freeze into this turn's context.
        if let updates = await renderToolResultUpdates() {
            textParts.append(updates)
        }

        if let instruction = instruction {
            textParts.append("<coordinator>\(instruction)</coordinator>")
            Logger.info("📋 Including coordinator instruction with tool result", category: .ai)
        }

        // PROMPT-CACHE INVARIANT: persist the context text on the assistant entry
        // BEFORE building history so send and replay bytes match.
        if !textParts.isEmpty {
            await stateCoordinator.setToolTurnContextWireText(textParts.joined(separator: "\n\n"))
        }

        // Build conversation history — tool_result(s) and the context text are
        // emitted by the history builder in wire order.
        // (message-block cache breakpoints applied as build-time post-processing)
        let messages = breakpointPlanner.plan(messages: await historyBuilder.buildAnthropicHistory())

        let tools = await toolConverter.getAnthropicTools()

        let parameters = AnthropicMessageParameter(
            model: modelId,
            messages: messages,
            system: cacheableSystem(),
            maxTokens: OnboardingLLMConfig.maxTokens,
            stream: true,
            tools: tools.isEmpty ? nil : tools,
            toolChoice: tools.isEmpty ? nil : .auto
        )

        // Log diagnostic info about tool blocks
        let (toolUseCount, toolResultCount) = countToolBlocks(in: messages)
        Logger.info(
            "📝 Built Anthropic tool response request: callId=\(callId), " +
            "tool_use=\(toolUseCount), tool_result=\(toolResultCount)",
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

        cacheAuditor.audit(tools: tools, system: baseSystemPrompt, messages: messages)

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

    /// Build a request after multiple tools have completed.
    ///
    /// Tool results are already stored in ConversationLog (via setToolResult).
    /// Like buildToolResponseRequest, the computed context is persisted on the
    /// assistant entry before history is built, keeping replay byte-identical.
    ///
    /// - Parameter payloads: Payloads containing callIds and optional instructions (output not needed)
    func buildBatchedToolResponseRequest(payloads: [JSON]) async throws -> AnthropicMessageParameter {
        // Resolve the model FIRST: it can throw, and drained tool-result updates
        // must never be consumed by a request that fails to build.
        let modelId = try await stateCoordinator.getAnthropicModelId()

        // Build computed context: interview_context + optional coordinator instruction
        var textParts: [String] = []

        if let interviewContext = await workingMemoryBuilder.buildInterviewContext() {
            textParts.append(interviewContext)
        }

        // Late tool results (cache-stable tail delivery)
        if let updates = await renderToolResultUpdates() {
            textParts.append(updates)
        }

        // Check for instruction in any payload (typically the last one for UI tool completions)
        if let instruction = payloads.last?["instruction"].string, !instruction.isEmpty {
            textParts.append("<coordinator>\(instruction)</coordinator>")
            Logger.info("📋 Including coordinator instruction with batched tool results", category: .ai)
        }

        // PROMPT-CACHE INVARIANT: persist context text before building history.
        if !textParts.isEmpty {
            await stateCoordinator.setToolTurnContextWireText(textParts.joined(separator: "\n\n"))
        }

        // Build conversation history — all tool_results plus context text in wire order
        // (message-block cache breakpoints applied as build-time post-processing)
        let messages = breakpointPlanner.plan(messages: await historyBuilder.buildAnthropicHistory())

        let tools = await toolConverter.getAnthropicTools()

        let parameters = AnthropicMessageParameter(
            model: modelId,
            messages: messages,
            system: cacheableSystem(),
            maxTokens: OnboardingLLMConfig.maxTokens,
            stream: true,
            tools: tools.isEmpty ? nil : tools,
            toolChoice: tools.isEmpty ? nil : .auto
        )

        Logger.info(
            "📝 Built Anthropic batched tool response request: \(payloads.count) tools",
            category: .ai
        )

        cacheAuditor.audit(tools: tools, system: baseSystemPrompt, messages: messages)

        return parameters
    }

    // MARK: - Late Tool-Result Delivery

    /// Render tool results that completed after their history bytes were frozen
    /// (pending placeholder or synthetic auto-fill) as <tool_result_update>
    /// blocks. Drained from ConversationLog and merged into the request's
    /// volatile text, where the wire capture freezes them like all other tail
    /// content — the model gets the real output without any in-place history
    /// mutation (which would invalidate the cached prefix on every later turn).
    private func renderToolResultUpdates() async -> String? {
        let updates = await stateCoordinator.drainPendingToolWireUpdates()
        guard !updates.isEmpty else { return nil }
        let rendered = updates.map { update in
            """
            <tool_result_update call_id="\(update.callId)" tool="\(update.name)" status="\(update.status.rawValue)">
            \(update.output)
            </tool_result_update>
            """
        }
        Logger.info(
            "📦 Delivering \(updates.count) late tool result(s) as <tool_result_update> (cache-stable tail delivery)",
            category: .ai
        )
        return rendered.joined(separator: "\n")
    }

    // MARK: - System Prompt

    /// Static system prompt with a cache breakpoint.
    /// The system prompt is the PhaseScriptRegistry base prompt ONLY — byte-identical
    /// within a phase. Volatile content (todo list, interview state) lives in the
    /// <interview_context> block of the latest user message (WorkingMemoryBuilder).
    /// The ephemeral cache_control on the system block caches tools+system together
    /// (tools render before system in the prompt).
    private func cacheableSystem() -> AnthropicSystemContent? {
        guard !baseSystemPrompt.isEmpty else { return nil }
        return .blocks([AnthropicSystemBlock(text: baseSystemPrompt, cacheControl: .ephemeral)])
    }
}

// MARK: - StateCoordinator Extension

extension StateCoordinator {
    /// Get the Anthropic model ID from settings
    /// Throws ModelConfigurationError if no model is configured
    func getAnthropicModelId() async throws -> String {
        try ModelConfigResolver.resolve(key: "onboardingAnthropicModelId", operation: "Anthropic Request Building")
    }
}
