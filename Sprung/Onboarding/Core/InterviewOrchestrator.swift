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
    struct Callbacks {
        let updateProcessingState: @Sendable (Bool) async -> Void
        let emitAssistantMessage: @Sendable (String) async -> Void
        let handleWaitingState: @Sendable (InterviewSession.Waiting?) async -> Void
        let handleError: @Sendable (String) async -> Void
        let storeApplicantProfile: @Sendable (JSON) async -> Void
        let storeSkeletonTimeline: @Sendable (JSON) async -> Void
        let storeArtifactRecord: @Sendable (JSON) async -> Void
        let setExtractionStatus: @Sendable (OnboardingPendingExtraction?) async -> Void
        let persistCheckpoint: @Sendable () async -> Void
    }

    private let client: OpenAIService
    private let state: InterviewState
    private let toolExecutor: ToolExecutor
    private let callbacks: Callbacks
    private let systemPrompt: String
    private let allowedToolsMap: [InterviewPhase: [String]] = [
        .phase1CoreFacts: [
            "capabilities.describe",
            "get_user_option",
            "get_user_upload",
            "get_macos_contact_card",
            "extract_document",
            "submit_for_validation",
            "persist_data",
            "set_objective_status",
            "next_phase"
        ],
        .phase2DeepDive: [
            "capabilities.describe",
            "get_user_option",
            "get_user_upload",
            "extract_document",
            "submit_for_validation",
            "persist_data",
            "set_objective_status",
            "next_phase"
        ],
        .phase3WritingCorpus: [
            "capabilities.describe",
            "get_user_option",
            "get_user_upload",
            "extract_document",
            "submit_for_validation",
            "persist_data",
            "set_objective_status",
            "next_phase"
        ],
        .complete: [
            "capabilities.describe",
            "next_phase"
        ]
    ]

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
            await callbacks.handleError("Failed to start interview: \(error.localizedDescription)")
        }
    }

    func sendUserMessage(_ text: String) async {
        await callbacks.updateProcessingState(true)
        defer { Task { await self.callbacks.updateProcessingState(false) } }

        do {
            try await requestResponse(withUserMessage: text)
        } catch {
            await callbacks.handleError("Failed to send message: \(error.localizedDescription)")
        }
    }

    func resumeToolContinuation(id: UUID, payload: JSON) async {
        await callbacks.updateProcessingState(true)
        defer { Task { await self.callbacks.updateProcessingState(false) } }

        do {
            let result = try await toolExecutor.resumeContinuation(id: id, with: payload)
            let callId = continuationCallIds.removeValue(forKey: id)
            let toolName = continuationToolNames.removeValue(forKey: id)

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
            if let continuation = pendingToolContinuations.removeValue(forKey: id) {
                continuation.resume(throwing: error)
            }
            await callbacks.handleError("Failed to resume tool: \(error.localizedDescription)")
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
            await callbacks.emitAssistantMessage("Excellent. Contact information is set.")
            await callbacks.persistCheckpoint()
        } catch ToolError.userCancelled {
            await callbacks.emitAssistantMessage("⚠️ Applicant profile entry skipped for now.")
        } catch {
            await callbacks.handleError("Failed to collect applicant profile: \(error.localizedDescription)")
        }

        do {
            let timeline = try await collectSkeletonTimeline()
            skeletonTimelineData = timeline
            await state.completeObjective("skeleton_timeline")
            await callbacks.emitAssistantMessage("✅ Skeleton timeline prepared.")
            await callbacks.persistCheckpoint()
        } catch ToolError.userCancelled {
            await callbacks.emitAssistantMessage("⚠️ Resume upload skipped.")
        } catch {
            await callbacks.handleError("Failed to build skeleton timeline: \(error.localizedDescription)")
        }

        let current = await state.currentSession()
        if current.objectivesDone.contains("skeleton_timeline") && !current.objectivesDone.contains("enabled_sections") {
            await state.completeObjective("enabled_sections")
            await callbacks.emitAssistantMessage("📋 Enabled sections recorded for Phase 1.")
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
            debugLog("Contact card fetch unavailable: \(error)")
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
        await callbacks.emitAssistantMessage("Next, let's build a high-level timeline of your career. Upload your most recent résumé or a PDF of LinkedIn and I'll map out the roles we'll dig into later.")

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
        } catch {
            debugLog("Persist data for \(dataType) failed: \(error)")
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
            temperature: 0.0,
            text: textConfig
        )

        if let effort = config.defaultReasoningEffort {
            parameters.reasoning = Reasoning(effort: effort)
        }

        let response = try await client.responseCreate(parameters)
        guard let output = response.outputText else {
            throw ToolError.executionFailed("Timeline extraction returned no content.")
        }

        guard let data = output.data(using: .utf8) else {
            throw ToolError.executionFailed("Timeline extraction output was not valid UTF-8.")
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

        if let userMessage {
            let contentItem = ContentItem.text(TextContent(text: userMessage))
            let inputMessage = InputMessage(role: "user", content: .array([contentItem]))
            inputItems.append(.message(inputMessage))
        }

        for output in functionOutputs {
            inputItems.append(.functionToolCallOutput(output))
        }

        guard !inputItems.isEmpty else {
            debugLog("No input items provided for response request.")
            return
        }

        let session = await state.currentSession()
        let allowedToolNames = allowedToolNames(for: session)

        let config = ModelProvider.forTask(.orchestrator)
        let textConfig = TextConfiguration(format: .text, verbosity: config.defaultVerbosity)

        var parameters = ModelResponseParameter(
            input: .array(inputItems),
            model: .custom(currentModelId),
            conversation: conversationId.map { .id($0) },
            instructions: conversationId == nil ? systemPrompt : nil,
            previousResponseId: lastResponseId,
            store: true,
            temperature: 0.7,
            text: textConfig
        )
        parameters.parallelToolCalls = false

        parameters.tools = await toolExecutor.availableToolSchemas(allowedNames: allowedToolNames)

        if let effort = config.defaultReasoningEffort {
            parameters.reasoning = Reasoning(effort: effort)
        }

        let response = try await client.responseCreate(parameters)
        lastResponseId = response.id
        if let conversation = response.conversation {
            conversationId = extractConversationId(from: conversation)
        }

        try await handleResponse(response)
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

    private func handleResponse(_ response: ResponseModel) async throws {
        for item in response.output {
            switch item {
            case .message(let message):
                let text = extractAssistantText(from: message)
                if !text.isEmpty {
                    await callbacks.emitAssistantMessage(text)
                }
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
        let result = try await toolExecutor.handleToolCall(call)

        _ = try await handleToolResult(result, callId: callId, toolName: functionCall.name)
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

    private func allowedToolNames(for session: InterviewSession) -> Set<String> {
        if let tools = allowedToolsMap[session.phase] {
            return Set(tools)
        }
        return Set(["capabilities.describe"])
    }
}
