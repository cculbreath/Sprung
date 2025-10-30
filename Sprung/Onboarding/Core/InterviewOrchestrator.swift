//
//  InterviewOrchestrator.swift
//  Sprung
//
//  Coordinates the onboarding interview conversation with OpenAI's Responses API,
//  mediating tool execution and state persistence.
//

import Foundation
import SwiftyJSON
import SwiftOpenAI

actor InterviewOrchestrator {
    // MARK: - Error Handling

    private func formatError(_ error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.displayDescription
        }
        return error.localizedDescription
    }
    struct Callbacks {
        let updateProcessingState: @Sendable (Bool) async -> Void
        let emitAssistantMessage: @Sendable (String) async -> UUID
        let beginStreamingAssistantMessage: @Sendable (String) async -> UUID
        let updateStreamingAssistantMessage: @Sendable (UUID, String) async -> Void
        let finalizeStreamingAssistantMessage: @Sendable (UUID, String) async -> Void
        let updateReasoningSummary: @Sendable (UUID, String, Bool) async -> Void
        let handleWaitingState: @Sendable (InterviewSession.Waiting?) async -> Void
        let handleError: @Sendable (String) async -> Void
        let storeApplicantProfile: @Sendable (JSON) async -> Void
        let storeSkeletonTimeline: @Sendable (JSON) async -> Void
        let storeArtifactRecord: @Sendable (JSON) async -> Void
        let storeKnowledgeCard: @Sendable (JSON) async -> Void
        let setExtractionStatus: @Sendable (OnboardingPendingExtraction?) async -> Void
        let persistCheckpoint: @Sendable () async -> Void
        let ledgerStatusMessage: @Sendable () async -> String?
    }

    private let client: OpenAIService
    private let state: InterviewState
    private let toolExecutor: ToolExecutor
    private let callbacks: Callbacks
    private let systemPrompt: String
    private let allowedToolsMap: [InterviewPhase: [String]] = [
        .phase1CoreFacts: [
            "capabilities_describe",
            "get_user_option",
            "get_applicant_profile",
            "get_user_upload",
            "get_macos_contact_card",
            "extract_document",
            "submit_for_validation",
            "persist_data",
            "set_objective_status",
            "next_phase"
        ],
        .phase2DeepDive: [
            "capabilities_describe",
            "get_user_option",
            "get_user_upload",
            "extract_document",
            "submit_for_validation",
            "persist_data",
            "set_objective_status",
            "next_phase",
            "generate_knowledge_card"
        ],
        .phase3WritingCorpus: [
            "capabilities_describe",
            "get_user_option",
            "get_user_upload",
            "extract_document",
            "submit_for_validation",
            "persist_data",
            "set_objective_status",
            "next_phase"
        ],
        .complete: [
            "capabilities_describe",
            "next_phase"
        ]
    ]

    private struct StreamBuffer {
        var messageId: UUID
        var text: String
    }

    private var conversationId: String?
    private var lastResponseId: String?
    private var currentModelId: String = "gpt-5"
    private var continuationCallIds: [UUID: String] = [:]
    private var continuationToolNames: [UUID: String] = [:]
    private var pendingToolContinuations: [UUID: CheckedContinuation<JSON, Error>] = [:]
    private var applicantProfileData: JSON?
    private var skeletonTimelineData: JSON?

    init(
        client: OpenAIService,
        state: InterviewState,
        toolExecutor: ToolExecutor,
        callbacks: Callbacks,
        systemPrompt: String
    ) {
        self.client = client
        self.state = state
        self.toolExecutor = toolExecutor
        self.callbacks = callbacks
        self.systemPrompt = systemPrompt
    }

    func startInterview(modelId: String) async {
        currentModelId = modelId
        conversationId = nil
        lastResponseId = nil

        // Let the LLM drive the conversation via tool calls
        // Send initial trigger message to activate the system prompt instructions
        do {
            try await requestResponse(withUserMessage: "Begin the onboarding interview.")
        } catch {
            let errorDetails = formatError(error)
            await callbacks.handleError("Failed to start interview: \(errorDetails)")
        }
    }

    func sendUserMessage(_ text: String) async {
        await callbacks.updateProcessingState(true)
        defer { Task { await self.callbacks.updateProcessingState(false) } }

        do {
            try await requestResponse(withUserMessage: text)
        } catch {
            let errorDetails = formatError(error)
            await callbacks.handleError("Failed to send message: \(errorDetails)")
        }
    }

    func resumeToolContinuation(id: UUID, payload: JSON) async {
        await callbacks.updateProcessingState(true)
        defer { Task { await self.callbacks.updateProcessingState(false) } }

        var callId: String?
        var toolName: String?
        do {
            let result = try await toolExecutor.resumeContinuation(id: id, with: payload)
            callId = continuationCallIds.removeValue(forKey: id)
            toolName = continuationToolNames.removeValue(forKey: id)

            await state.setWaiting(nil)
            await callbacks.handleWaitingState(nil)

            var waitingToken: ContinuationToken?
            let immediate = try await handleToolResult(
                result,
                callId: callId,
                toolName: toolName,
                waitingHandler: { token in waitingToken = token }
            )

            if let continuation = pendingToolContinuations.removeValue(forKey: id) {
                if let json = immediate {
                    continuation.resume(returning: json)
                } else if let token = waitingToken {
                    pendingToolContinuations[token.id] = continuation
                    if let toolName {
                        continuationToolNames[token.id] = toolName
                    }
                } else {
                    continuation.resume(throwing: ToolError.executionFailed("Tool resumed without output."))
                }
            }
        } catch {
            if let toolName,
               await handleToolExecutionError(error, callId: callId, toolName: toolName) {
                return
            }
            if let continuation = pendingToolContinuations.removeValue(forKey: id) {
                continuation.resume(throwing: error)
            }
            let errorDetails = formatError(error)
            await callbacks.handleError("Failed to resume tool: \(errorDetails)")
        }
    }

    // DEPRECATED: This imperative orchestration is replaced by LLM-driven flow via tool calls.
    // The LLM now drives Phase 1 by calling get_user_option, get_macos_contact_card,
    // submit_for_validation, and other tools as needed based on user choices.
    // Kept for reference only.
    private func runPhaseOne() async {
        await callbacks.updateProcessingState(true)
        defer { Task { await self.callbacks.updateProcessingState(false) } }

        do {
            let profile = try await collectApplicantProfile()
            applicantProfileData = profile
            await state.completeObjective("applicant_profile")
            _ = await callbacks.emitAssistantMessage("Excellent. Contact information is set.")
            await callbacks.persistCheckpoint()
        } catch ToolError.userCancelled {
            _ = await callbacks.emitAssistantMessage("⚠️ Applicant profile entry skipped for now.")
        } catch {
            let errorDetails = formatError(error)
            await callbacks.handleError("Failed to collect applicant profile: \(errorDetails)")
        }

        do {
            let timeline = try await collectSkeletonTimeline()
            skeletonTimelineData = timeline
            await state.completeObjective("skeleton_timeline")
            _ = await callbacks.emitAssistantMessage("✅ Skeleton timeline prepared.")
            await callbacks.persistCheckpoint()
        } catch ToolError.userCancelled {
            _ = await callbacks.emitAssistantMessage("⚠️ Resume upload skipped.")
        } catch {
            let errorDetails = formatError(error)
            await callbacks.handleError("Failed to build skeleton timeline: \(errorDetails)")
        }

        let current = await state.currentSession()
        if current.objectivesDone.contains("skeleton_timeline") && !current.objectivesDone.contains("enabled_sections") {
            await state.completeObjective("enabled_sections")
            _ = await callbacks.emitAssistantMessage("📋 Enabled sections recorded for Phase 1.")
            await callbacks.persistCheckpoint()
        }
    }

    private func collectApplicantProfile() async throws -> JSON {
        // Quietly try to fetch contact data first (no message to user yet)
        var draft = ApplicantProfileDraft()
        var sources: [String] = []

        do {
            let contactResponse = try await callTool(name: "get_macos_contact_card", arguments: JSON())
            if contactResponse["status"].stringValue == "fetched" {
                let contactDraft = buildApplicantProfileDraft(from: contactResponse["contact"])
                draft = draft.merging(contactDraft)
                sources.append("macOS Contacts")
            }
        } catch {
            Logger.debug("Contact card fetch unavailable: \(error)")
        }

        // Immediately submit for validation (even if empty) as per spec
        var args = JSON()
        args["dataType"].string = "applicant_profile"
        args["data"] = draft.toJSON()
        args["message"].string = "Review the suggested details below. Edit anything that needs correction or add missing information before continuing."
        if !sources.isEmpty {
            args["sources"] = JSON(sources)
        }

        let validation = try await callTool(name: "submit_for_validation", arguments: args)
        let status = validation["status"].stringValue
        guard status != "rejected" else {
            throw ToolError.executionFailed("Applicant profile rejected.")
        }

        let data = validation["data"]
        let final = data != .null ? data : draft.toJSON()
        await callbacks.storeApplicantProfile(final)
        await persistData(final, as: "applicant_profile")
        return final
    }

    private func collectSkeletonTimeline() async throws -> JSON {
        _ = await callbacks.emitAssistantMessage("Next, let's build a high-level timeline of your career. Upload your most recent résumé or a PDF of LinkedIn and I'll map out the roles we'll dig into later.")

        var uploadArgs = JSON()
        uploadArgs["uploadType"].string = "resume"
        uploadArgs["prompt"].string = "Upload your latest resume to extract a skeleton timeline."

        let uploadResult = try await callTool(name: "get_user_upload", arguments: uploadArgs)
        guard uploadResult["status"].stringValue == "uploaded",
              let firstUpload = uploadResult["uploads"].array?.first else {
            throw ToolError.userCancelled
        }

        guard let fileURLString = firstUpload["file_url"].string ?? firstUpload["storageUrl"].string,
              let fileURL = URL(string: fileURLString) else {
            throw ToolError.executionFailed("Uploaded file URL missing or invalid.")
        }

        var extractionArgs = JSON()
        extractionArgs["file_url"].string = fileURL.absoluteString
        extractionArgs["purpose"].string = "resume_timeline"
        extractionArgs["return_types"] = JSON(["artifact_record"])

        await callbacks.setExtractionStatus(
            OnboardingPendingExtraction(
                title: "Extracting résumé",
                summary: "Processing your uploaded résumé to draft a skeleton timeline."
            )
        )

        defer {
            Task { await callbacks.setExtractionStatus(nil) }
        }

        let extractionResult = try await callTool(name: "extract_document", arguments: extractionArgs)
        let artifact = extractionResult["artifact_record"]
        let extractedText = artifact["extracted_content"].stringValue
        guard !extractedText.isEmpty else {
            throw ToolError.executionFailed("Document extraction did not yield text content.")
        }
        if artifact != .null {
            await callbacks.storeArtifactRecord(artifact)
            await persistData(artifact, as: "artifact_record")
        }

        let timeline = try await generateTimeline(from: extractedText)

        var validationArgs = JSON()
        validationArgs["dataType"].string = "skeleton_timeline"
        validationArgs["data"] = timeline
        validationArgs["message"].string = "Review the generated skeleton timeline."

        let validation = try await callTool(name: "submit_for_validation", arguments: validationArgs)
        let status = validation["status"].stringValue
        guard status != "rejected" else {
            throw ToolError.executionFailed("Skeleton timeline rejected.")
        }

        let data = validation["data"]
        let final = data != .null ? data : timeline
        await callbacks.storeSkeletonTimeline(final)
        await persistData(final, as: "skeleton_timeline")
        return final
    }

    private func persistData(_ payload: JSON, as dataType: String) async {
        guard payload != .null else { return }

        var args = JSON()
        args["dataType"].string = dataType
        args["data"] = payload

        do {
            _ = try await callTool(name: "persist_data", arguments: args)
            if dataType == "knowledge_card" {
                await callbacks.storeKnowledgeCard(payload)
            }
        } catch {
            Logger.debug("Persist data for \(dataType) failed: \(error)")
        }
    }

    private func buildApplicantProfileDraft(from contact: JSON) -> ApplicantProfileDraft {
        var draft = ApplicantProfileDraft()

        let given = contact["name"]["given"].stringValue
        let family = contact["name"]["family"].stringValue
        let fullName = [given, family].filter { !$0.isEmpty }.joined(separator: " ")
        if !fullName.isEmpty { draft.name = fullName }

        if let jobTitle = contact["jobTitle"].string, !jobTitle.isEmpty {
            draft.label = jobTitle
        }

        if let organization = contact["organization"].string, !organization.isEmpty {
            draft.summary = "Current role at \(organization)."
        }

        if let emailEntry = contact["email"].array?.compactMap({ $0["value"].string }).first,
           !emailEntry.isEmpty {
            draft.email = emailEntry
        }

        if let phoneEntry = contact["phone"].array?.compactMap({ $0["value"].string }).first,
           !phoneEntry.isEmpty {
            draft.phone = phoneEntry
        }

        return draft
    }

    private func generateTimeline(from resumeText: String) async throws -> JSON {
        let config = ModelProvider.forTask(.extract)
        let textConfig = TextConfiguration(format: .jsonObject, verbosity: config.defaultVerbosity)

        let prompt = buildTimelineExtractionPrompt(resumeText: resumeText)
        let message = InputMessage(role: "user", content: .text(prompt))

        var parameters = ModelResponseParameter(
            input: .array([.message(message)]),
            model: .custom(config.id),
            text: textConfig
        )

        if let effort = config.defaultReasoningEffort {
            parameters.reasoning = Reasoning(effort: effort, summary: .auto)
        }

        let response = try await client.responseCreate(parameters)
        guard let output = response.outputText else {
            throw ToolError.executionFailed("Timeline extraction returned no content.")
        }

        guard let data = output.data(using: .utf8) else {
            throw ToolError.executionFailed("Timeline extraction output was not valid UTF-8.")
        }

        if let usage = response.usage {
            var parts: [String] = []
            if let input = usage.inputTokens ?? usage.promptTokens {
                parts.append("input: \(input)")
            }
            if let output = usage.outputTokens ?? usage.completionTokens {
                parts.append("output: \(output)")
            }
            if let reasoning = usage.outputTokensDetails?.reasoningTokens {
                parts.append("reasoning: \(reasoning)")
            }
            if !parts.isEmpty {
                Logger.debug("🧠 extract_document usage — " + parts.joined(separator: ", "), category: .ai)
            }
        }

        return try JSON(data: data)
    }

    private func buildTimelineExtractionPrompt(resumeText: String) -> String {
        let truncated = truncateText(resumeText, limit: 8000)
        return """
        You are an assistant that extracts a chronological career timeline from resume text.
        Respond with a JSON object containing a key \"experiences\" which holds an array of entries.
        Each entry must include the fields: title, organization, start, end, and summary.
        Use ISO 8601 date strings in the format YYYY-MM when dates are available; otherwise use null.
        Resume text:
        \(truncated)
        """
    }

    private func truncateText(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit))
    }

    private func requestResponse(
        withUserMessage userMessage: String? = nil,
        functionOutputs: [FunctionToolCallOutput] = []
    ) async throws {
        var inputItems: [InputItem] = []

        if let ledgerMessage = await callbacks.ledgerStatusMessage(), !ledgerMessage.isEmpty {
            let contentItem = ContentItem.text(TextContent(text: ledgerMessage))
            let message = InputMessage(role: "system", content: .array([contentItem]))
            inputItems.append(.message(message))
        }

        if let userMessage {
            let contentItem = ContentItem.text(TextContent(text: userMessage))
            let inputMessage = InputMessage(role: "user", content: .array([contentItem]))
            inputItems.append(.message(inputMessage))
        }

        for output in functionOutputs {
            inputItems.append(.functionToolCallOutput(output))
        }

        guard !inputItems.isEmpty else {
            Logger.debug("No input items provided for response request.")
            return
        }

        let session = await state.currentSession()
        let allowedToolNames = allowedToolNames(for: session)

        let config = ModelProvider.forTask(.orchestrator)
        let textConfig = TextConfiguration(format: .text, verbosity: config.defaultVerbosity)

        let apiModelId = currentModelId.replacingOccurrences(of: "openai/", with: "")

        var parameters = ModelResponseParameter(
            input: .array(inputItems),
            model: .custom(apiModelId),
            conversation: conversationId.map { .id($0) },
            instructions: conversationId == nil ? systemPrompt : nil,
            previousResponseId: lastResponseId,
            store: true,
            text: textConfig
        )
        parameters.parallelToolCalls = false
        parameters.tools = await toolExecutor.availableToolSchemas(allowedNames: allowedToolNames)

        if let effort = config.defaultReasoningEffort {
            parameters.reasoning = Reasoning(effort: effort, summary: .auto)
        }

        parameters.stream = true

        var streamBuffers: [String: StreamBuffer] = [:]
        var finalizedMessageIds: Set<String> = []
        var finalResponse: ResponseModel?
        var messageIdByOutputItem: [String: UUID] = [:]
        var reasoningSummaryBuffers: [String: String] = [:]
        var reasoningSummaryFinalized: Set<String> = []

        func deliverSummary(for itemId: String, isFinalOverride: Bool?) async {
            guard let summary = reasoningSummaryBuffers[itemId] else { return }
            guard let messageId = messageIdByOutputItem[itemId] else { return }
            let isFinal = isFinalOverride ?? reasoningSummaryFinalized.contains(itemId)
            await callbacks.updateReasoningSummary(messageId, summary, isFinal)
            if isFinal {
                reasoningSummaryBuffers.removeValue(forKey: itemId)
                reasoningSummaryFinalized.remove(itemId)
            }
        }

        do {
            let stream = try await client.responseCreateStream(parameters)
            for try await event in stream {
                try Task.checkCancellation()
                switch event {
                case .responseCreated(let created):
                    updateConversationState(from: created.response)
                case .responseInProgress(let inProgress):
                    updateConversationState(from: inProgress.response)
                case .responseCompleted(let completed):
                    updateConversationState(from: completed.response)
                    finalResponse = completed.response
                case .responseFailed(let failed):
                    updateConversationState(from: failed.response)
                    let message = failed.response.error?.message ?? "Model response failed."
                    throw ToolError.executionFailed(message)
                case .responseIncomplete(let incomplete):
                    updateConversationState(from: incomplete.response)
                    let reason = incomplete.response.incompleteDetails?.reason ?? "unknown"
                    throw ToolError.executionFailed("Model response incomplete: \(reason)")
                case .outputTextDelta(let delta):
                    let fragment = delta.delta
                    guard !fragment.isEmpty else { continue }
                    var buffer = streamBuffers[delta.itemId]
                    if buffer == nil {
                        let messageId = await callbacks.beginStreamingAssistantMessage("")
                        buffer = StreamBuffer(messageId: messageId, text: "")
                        messageIdByOutputItem[delta.itemId] = messageId
                    }
                    if messageIdByOutputItem[delta.itemId] == nil {
                        messageIdByOutputItem[delta.itemId] = buffer!.messageId
                    }
                    buffer!.text.append(contentsOf: fragment)
                    streamBuffers[delta.itemId] = buffer!
                    await callbacks.updateStreamingAssistantMessage(buffer!.messageId, buffer!.text)
                    await deliverSummary(for: delta.itemId, isFinalOverride: false)
                case .outputTextDone(let done):
                    let finalText = done.text
                    var buffer = streamBuffers[done.itemId]
                    if buffer == nil {
                        let messageId = await callbacks.beginStreamingAssistantMessage(finalText)
                        buffer = StreamBuffer(messageId: messageId, text: finalText)
                        messageIdByOutputItem[done.itemId] = messageId
                    } else {
                        buffer!.text = finalText
                    }
                    if messageIdByOutputItem[done.itemId] == nil {
                        messageIdByOutputItem[done.itemId] = buffer!.messageId
                    }
                    streamBuffers[done.itemId] = buffer!
                    await callbacks.finalizeStreamingAssistantMessage(buffer!.messageId, buffer!.text)
                    finalizedMessageIds.insert(done.itemId)
                    streamBuffers.removeValue(forKey: done.itemId)
                    await deliverSummary(for: done.itemId, isFinalOverride: nil)
                case .reasoningSummaryTextDelta(let delta):
                    let fragment = delta.delta
                    guard !fragment.isEmpty else { continue }
                    reasoningSummaryBuffers[delta.itemId, default: ""] += fragment
                    if messageIdByOutputItem[delta.itemId] != nil {
                        await deliverSummary(for: delta.itemId, isFinalOverride: false)
                    }
                case .reasoningSummaryTextDone(let done):
                    reasoningSummaryBuffers[done.itemId] = done.text
                    reasoningSummaryFinalized.insert(done.itemId)
                    if messageIdByOutputItem[done.itemId] != nil {
                        await deliverSummary(for: done.itemId, isFinalOverride: true)
                    }
                default:
                    continue
                }
            }
        } catch {
            throw error
        }

        guard let response = finalResponse else {
            Logger.debug("Streaming response completed without final response payload.")
            await callbacks.persistCheckpoint()
            return
        }

        try await handleResponse(
            response,
            finalizedMessageIds: finalizedMessageIds,
            messageIdByOutputItem: messageIdByOutputItem
        )
        await callbacks.persistCheckpoint()
    }

    private func callTool(name: String, arguments: JSON) async throws -> JSON {
        let call = ToolCall(
            id: UUID().uuidString,
            name: name,
            arguments: arguments,
            callId: UUID().uuidString
        )

        let result = try await toolExecutor.handleToolCall(call)
        var waitingToken: ContinuationToken?
        if let immediate = try await handleToolResult(
            result,
            callId: nil,
            toolName: name,
            waitingHandler: { token in waitingToken = token }
        ) {
            return immediate
        }

        guard let token = waitingToken else {
            throw ToolError.executionFailed("Tool \(name) entered waiting state without a continuation token.")
        }

        await callbacks.updateProcessingState(false)
        do {
            let resultJSON = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<JSON, Error>) in
                pendingToolContinuations[token.id] = continuation
            }
            await callbacks.updateProcessingState(true)
            return resultJSON
        } catch {
            await callbacks.updateProcessingState(true)
            throw error
        }
    }

    private func handleResponse(
        _ response: ResponseModel,
        finalizedMessageIds: Set<String> = [],
        messageIdByOutputItem: [String: UUID] = [:]
    ) async throws {
        var messageIds = messageIdByOutputItem
        var lastMessageUUID: UUID?

        for item in response.output {
            switch item {
            case .message(let message):
                let text = extractAssistantText(from: message)
                if let existing = messageIds[message.id] {
                    lastMessageUUID = existing
                }
                if finalizedMessageIds.contains(message.id) || text.isEmpty {
                    continue
                }
                let messageUUID = await callbacks.emitAssistantMessage(text)
                messageIds[message.id] = messageUUID
                lastMessageUUID = messageUUID
            case .reasoning(let reasoning):
                let summaryText = reasoning.summary
                    .map(\.text)
                    .joined(separator: "\n\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !summaryText.isEmpty else { continue }

                let targetId = lastMessageUUID ?? messageIds[reasoning.id]
                guard let messageUUID = targetId else {
                    Logger.debug("Reasoning summary received without matching message (reasoning id: \(reasoning.id)).")
                    continue
                }
                await callbacks.updateReasoningSummary(messageUUID, summaryText, true)
            case .functionCall(let functionCall):
                try await handleFunctionCall(functionCall)
            default:
                continue
            }
        }
    }

    private func handleFunctionCall(_ functionCall: OutputItem.FunctionToolCall) async throws {
        let argumentsJSON = JSON(parseJSON: functionCall.arguments)
        guard argumentsJSON != .null else {
            await callbacks.handleError("Tool call \(functionCall.name) had invalid parameters.")
            return
        }

        let callId = functionCall.callId
        let identifier = functionCall.id
        let call = ToolCall(id: identifier, name: functionCall.name, arguments: argumentsJSON, callId: callId)
        do {
            let result = try await toolExecutor.handleToolCall(call)
            _ = try await handleToolResult(result, callId: callId, toolName: functionCall.name)
        } catch {
            if await handleToolExecutionError(error, callId: callId, toolName: functionCall.name) {
                return
            }
            throw error
        }
    }

    private func handleToolResult(
        _ result: ToolResult,
        callId: String?,
        toolName: String? = nil,
        waitingHandler: ((ContinuationToken) -> Void)? = nil
    ) async throws -> JSON? {
        switch result {
        case .immediate(let json):
            if let callId {
                try await sendToolOutput(callId: callId, output: json)
            }
            return json
        case .waiting(_, let token):
            if let callId {
                // Send status to LLM to prevent tool call timeout
                // Use initialPayload if provided, otherwise send waiting status
                let statusPayload = token.initialPayload ?? JSON(["status": "waiting for user input"])
                try await sendToolOutput(callId: callId, output: statusPayload)
                continuationCallIds[token.id] = callId
            }
            if let toolName {
                continuationToolNames[token.id] = toolName
                let waitingState = waitingState(for: toolName)
                await state.setWaiting(waitingState)
                await callbacks.handleWaitingState(waitingState)
            }
            waitingHandler?(token)
            return nil
        case .error(let error):
            throw error
        }
    }

    private func sendToolOutput(callId: String, output: JSON) async throws {
        guard
            let data = try? output.rawData(options: []),
            let outputString = String(data: data, encoding: .utf8)
        else {
            throw NSError(domain: "InterviewOrchestrator", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to encode tool output as JSON string."
            ])
        }

        let functionOutput = FunctionToolCallOutput(callId: callId, output: outputString)
        try await requestResponse(functionOutputs: [functionOutput])
    }

    private func updateConversationState(from response: ResponseModel) {
        lastResponseId = response.id
        if let conversation = response.conversation {
            conversationId = extractConversationId(from: conversation)
        }
    }

    private func extractAssistantText(from message: OutputItem.Message) -> String {
        message.content.compactMap { content -> String? in
            if case let .outputText(output) = content {
                return output.text
            }
            return nil
        }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractConversationId(from conversation: Conversation) -> String {
        switch conversation {
        case .id(let identifier):
            return identifier
        case .object(let object):
            return object.id
        }
    }

    private func waitingState(for toolName: String?) -> InterviewSession.Waiting? {
        guard let toolName else { return nil }
        switch toolName {
        case "get_user_option":
            return .selection
        case "submit_for_validation":
            return .validation
        case "next_phase":
            return .validation
        default:
            return nil
        }
    }

    private func handleToolExecutionError(
        _ error: Error,
        callId: String?,
        toolName: String
    ) async -> Bool {
        guard case let ToolError.invalidParameters(message) = error,
              toolName == "submit_for_validation",
              message.contains("missing data payload")
        else {
            return false
        }

        if let callId {
            var output = JSON()
            output["status"].string = "error"
            output["reason"].string = "missing_data"
            output["message"].string = "submit_for_validation requires a populated data payload."
            do {
                try await sendToolOutput(callId: callId, output: output)
            } catch {
                Logger.error("❌ Unable to deliver tool error response: \(error)", category: .ai)
            }
        }

        Logger.warning("⚠️ submit_for_validation missing data payload; requesting LLM retry.", category: .ai)
        return true
    }

    private func allowedToolNames(for session: InterviewSession) -> Set<String> {
        if let tools = allowedToolsMap[session.phase] {
            return Set(tools)
        }
        return Set(["capabilities_describe"])
    }
}
