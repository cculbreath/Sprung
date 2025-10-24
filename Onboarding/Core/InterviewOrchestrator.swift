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
    }

    private let client: OpenAIService
    private let state: InterviewState
    private let toolExecutor: ToolExecutor
    private let checkpoints: Checkpoints
    private let callbacks: Callbacks
    private let systemPrompt: String

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
        checkpoints: Checkpoints,
        callbacks: Callbacks,
        systemPrompt: String
    ) {
        self.client = client
        self.state = state
        self.toolExecutor = toolExecutor
        self.checkpoints = checkpoints
        self.callbacks = callbacks
        self.systemPrompt = systemPrompt
    }

    func startInterview(modelId: String) async {
        currentModelId = modelId
        conversationId = nil
        lastResponseId = nil

        await callbacks.emitAssistantMessage("👋 Let's gather your applicant profile and resume to get started.")
        await runPhaseOne()
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

    private func runPhaseOne() async {
        await callbacks.updateProcessingState(true)
        defer { Task { await self.callbacks.updateProcessingState(false) } }

        do {
            let profile = try await collectApplicantProfile()
            applicantProfileData = profile
            await state.completeObjective("applicant_profile")
            await callbacks.emitAssistantMessage("✅ Applicant profile captured.")
            let session = await state.currentSession()
            await checkpoints.save(
                from: session,
                applicantProfile: applicantProfileData,
                skeletonTimeline: skeletonTimelineData
            )
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
            let session = await state.currentSession()
            await checkpoints.save(
                from: session,
                applicantProfile: applicantProfileData,
                skeletonTimeline: skeletonTimelineData
            )
        } catch ToolError.userCancelled {
            await callbacks.emitAssistantMessage("⚠️ Resume upload skipped.")
        } catch {
            await callbacks.handleError("Failed to build skeleton timeline: \(error.localizedDescription)")
        }
    }

    private func collectApplicantProfile() async throws -> JSON {
        await callbacks.emitAssistantMessage("🪪 Gathering applicant profile details…")

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

        var args = JSON()
        args["dataType"].string = "applicantProfile"
        args["data"] = draft.toJSON()
        args["message"].string = "Review and confirm your applicant profile information."
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
        return final
    }

    private func collectSkeletonTimeline() async throws -> JSON {
        await callbacks.emitAssistantMessage("📄 Please upload your resume so we can draft a timeline.")

        var uploadArgs = JSON()
        uploadArgs["uploadType"].string = "resume"
        uploadArgs["prompt"].string = "Upload your latest resume to extract a skeleton timeline."

        let uploadResult = try await callTool(name: "get_user_upload", arguments: uploadArgs)
        guard uploadResult["status"].stringValue == "uploaded",
              let firstUpload = uploadResult["uploads"].array?.first,
              let extractedText = firstUpload["extractedText"].string,
              !extractedText.isEmpty else {
            throw ToolError.userCancelled
        }

        let timeline = try await generateTimeline(from: extractedText)

        var validationArgs = JSON()
        validationArgs["dataType"].string = "experience"
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
        return final
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
        var textConfig = TextConfiguration(format: .jsonObject, verbosity: config.defaultVerbosity)

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
        functionOutputs: [InputType.FunctionToolCallOutput] = []
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

        let config = ModelProvider.forTask(.orchestrator)
        var textConfig = TextConfiguration(format: .text, verbosity: config.defaultVerbosity)

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
        parameters.tools = toolExecutor.availableToolSchemas()
        if let effort = config.defaultReasoningEffort {
            parameters.reasoning = Reasoning(effort: effort)
        }

        let response = try await client.responseCreate(parameters)
        lastResponseId = response.id
        if let conversation = response.conversation {
            conversationId = extractConversationId(from: conversation)
        }

        try await handleResponse(response)
        let session = await state.currentSession()
        await checkpoints.save(
            from: session,
            applicantProfile: applicantProfileData,
            skeletonTimeline: skeletonTimelineData
        )
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
        let identifier = functionCall.id ?? callId
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
        guard let outputString = output.rawString(.withoutEscapingSlashes) else {
            throw NSError(domain: "InterviewOrchestrator", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to encode tool output as JSON string."
            ])
        }

        let functionOutput = InputType.FunctionToolCallOutput(callId: callId, output: outputString)
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
        default:
            return nil
        }
    }
}
