//
//  DiscoveryAgentService.swift
//  Sprung
//
//  Agent service for Discovery LLM interactions.
//  Tool-loop flows (daily tasks, event prep, weekly reflection) run on the
//  shared AnthropicToolLoopRunner against the user-selected Discovery
//  Anthropic model; single-shot flows (debrief outcomes, choose-best-jobs)
//  are plain Anthropic Messages calls. Web-search discovery (job sources,
//  networking events) stays on LLMFacade.executeWithWebSearch (OpenAI).
//

import Foundation
import SwiftOpenAI

// MARK: - Discovery Agent Service

@MainActor
final class DiscoveryAgentService {

    // MARK: - Dependencies

    private let llmFacade: LLMFacade
    private let toolExecutor: DiscoveryToolExecutor
    private let settingsStore: DiscoverySettingsStore
    private let parser = DiscoveryResponseParser()

    // MARK: - Model Configuration

    /// UserDefaults key for the user-selected Anthropic model powering all
    /// Discovery agent + coaching LLM flows (Settings > Models > Discovery Agent).
    static let anthropicModelSettingKey = "discoveryAnthropicModelId"

    // MARK: - Initialization

    init(
        llmFacade: LLMFacade,
        contextProvider: DiscoveryContextProviderImpl,
        settingsStore: DiscoverySettingsStore
    ) {
        self.llmFacade = llmFacade
        self.toolExecutor = DiscoveryToolExecutor(contextProvider: contextProvider)
        self.settingsStore = settingsStore
    }

    /// The user-selected Anthropic model for Discovery agent flows.
    /// Throws `ModelConfigurationError` when unset — never substitutes a default.
    private func anthropicModelId(operation: String) throws -> String {
        try ModelConfigResolver.resolve(key: Self.anthropicModelSettingKey, operation: operation)
    }

    // MARK: - Web-Search Model Configuration (OpenAI Responses path)

    private var webSearchModelId: String {
        settingsStore.current().llmModelId
    }

    private var reasoningEffort: String {
        settingsStore.current().reasoningEffort
    }

    // MARK: - Prompt Loading

    private func loadPromptTemplate(named name: String) throws -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: "Prompts"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            Logger.error("Failed to load prompt template: \(name)", category: .ai)
            throw DiscoveryAgentError.promptTemplateMissing(name)
        }
        return content
    }

    // MARK: - Agent Loop (shared AnthropicToolLoopRunner)

    /// Run a tool-enabled agent loop and return the final response text the
    /// agent submitted via the `submit_final_response` completion tool.
    private func runAgent(
        systemPrompt: String,
        userMessage: String,
        operation: String
    ) async throws -> String {
        let modelId = try anthropicModelId(operation: operation)
        let delegate = DiscoveryAgentLoop(
            llmFacade: llmFacade,
            toolExecutor: toolExecutor,
            modelId: modelId,
            systemPrompt: systemPrompt,
            userMessage: userMessage
        )
        return try await AnthropicToolLoopRunner(delegate: delegate).run()
    }

    /// Run a single-shot (no tools) Anthropic request and return the response text.
    private func runSingleShot(
        systemPrompt: String,
        userMessage: String,
        operation: String
    ) async throws -> String {
        let modelId = try anthropicModelId(operation: operation)
        return try await llmFacade.executeTextWithAnthropicCaching(
            systemContent: [AnthropicSystemBlock(text: systemPrompt)],
            userPrompt: userMessage,
            modelId: modelId
        )
    }

    // MARK: - OpenAI Responses API (web search, via LLMFacade)

    private func runOpenAIRequest(
        systemPrompt: String,
        userMessage: String,
        modelId: String,
        reasoningEffort: String = "low",
        webSearchLocation: String? = nil,
        searchContext: String = "job sources",
        statusCallback: (@MainActor @Sendable (DiscoveryStatus) async -> Void)? = nil,
        reasoningCallback: (@MainActor @Sendable (String) async -> Void)? = nil
    ) async throws -> String {
        do {
            return try await llmFacade.executeWithWebSearch(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                modelId: modelId,
                reasoningEffort: reasoningEffort,
                webSearchLocation: webSearchLocation,
                onWebSearching: statusCallback.map { callback in
                    { @Sendable in await callback(.webSearching(context: searchContext)) }
                },
                onWebSearchComplete: statusCallback.map { callback in
                    { @Sendable in await callback(.webSearchComplete) }
                },
                onTextDelta: reasoningCallback
            )
        } catch let error as LLMError {
            // Convert LLMError to DiscoveryAgentError for consistency
            throw DiscoveryAgentError.llmError(error.localizedDescription)
        }
    }

    // MARK: - Task Methods

    func generateDailyTasks(focusArea: String = "balanced") async throws -> DailyTasksResult {
        let systemPrompt = try loadPromptTemplate(named: "discovery_generate_daily_tasks")
        let response = try await runAgent(
            systemPrompt: systemPrompt,
            userMessage: "Generate today's job search tasks. Focus area: \(focusArea)",
            operation: "Daily Task Generation"
        )
        return try parser.parseTasks(response)
    }

    func discoverJobSources(
        sectors: [String],
        location: String,
        candidateContext: String = "",
        statusCallback: (@MainActor @Sendable (DiscoveryStatus) async -> Void)? = nil
    ) async throws -> JobSourcesResult {
        let systemPrompt = try loadPromptTemplate(named: "discovery_discover_job_sources")

        var userMessage = "Discover job sources for sectors: \(sectors.joined(separator: ", ")) in \(location)"
        if !candidateContext.isEmpty {
            userMessage += "\n\n\(candidateContext)"
        }

        let response = try await runOpenAIRequest(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            modelId: webSearchModelId,
            reasoningEffort: reasoningEffort,
            webSearchLocation: location,
            statusCallback: statusCallback
        )
        return try parser.parseSources(response)
    }

    func discoverNetworkingEvents(
        sectors: [String],
        location: String,
        candidateContext: String = "",
        daysAhead: Int = 14,
        statusCallback: (@MainActor @Sendable (DiscoveryStatus) async -> Void)? = nil,
        reasoningCallback: (@MainActor @Sendable (String) async -> Void)? = nil
    ) async throws -> NetworkingEventsResult {
        let systemPrompt = try loadPromptTemplate(named: "discovery_discover_networking_events")

        var userMessage = "Find networking events for sectors: \(sectors.joined(separator: ", ")) in \(location) for the next \(daysAhead) days"
        if !candidateContext.isEmpty {
            userMessage += "\n\n\(candidateContext)"
        }

        let response = try await runOpenAIRequest(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            modelId: webSearchModelId,
            reasoningEffort: reasoningEffort,
            webSearchLocation: location,
            searchContext: "networking events",
            statusCallback: statusCallback,
            reasoningCallback: reasoningCallback
        )
        return try parser.parseEvents(response)
    }

    func prepareForEvent(eventId: UUID, focusCompanies: [String] = [], goals: String? = nil) async throws -> EventPrepResult {
        let systemPrompt = try loadPromptTemplate(named: "discovery_prepare_for_event")
        var userMessage = "Prepare me for event \(eventId.uuidString)"
        if !focusCompanies.isEmpty {
            userMessage += ". Focus on companies: \(focusCompanies.joined(separator: ", "))"
        }
        if let goals = goals {
            userMessage += ". My goals: \(goals)"
        }
        let response = try await runAgent(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            operation: "Event Preparation"
        )
        return try parser.parsePrep(response)
    }

    func generateDebriefOutcomes(
        eventName: String,
        eventType: String,
        keyInsights: String,
        contactsMade: [String],
        notes: String
    ) async throws -> DebriefOutcomesResult {
        let systemPrompt = try loadPromptTemplate(named: "discovery_debrief_outcomes")

        var contextParts: [String] = ["Event: \(eventName) (\(eventType))"]
        if !contactsMade.isEmpty {
            contextParts.append("Contacts made: \(contactsMade.joined(separator: ", "))")
        }
        if !keyInsights.isEmpty {
            contextParts.append("Key insights: \(keyInsights)")
        }
        if !notes.isEmpty {
            contextParts.append("Additional notes: \(notes)")
        }

        let response = try await runSingleShot(
            systemPrompt: systemPrompt,
            userMessage: contextParts.joined(separator: "\n\n"),
            operation: "Event Debrief"
        )
        return try parser.parseDebriefOutcomes(response)
    }

    func generateWeeklyReflection() async throws -> String {
        let systemPrompt = try loadPromptTemplate(named: "discovery_generate_weekly_reflection")
        return try await runAgent(
            systemPrompt: systemPrompt,
            userMessage: "Generate my weekly job search reflection",
            operation: "Weekly Reflection"
        )
    }

    func chooseBestJobs(
        jobs: [(id: UUID, company: String, role: String, description: String)],
        knowledgeContext: String,
        dossierContext: String,
        count: Int = 5
    ) async throws -> JobSelectionsResult {
        let systemPrompt = try loadPromptTemplate(named: "discovery_choose_best_jobs")

        var userMessage = "Please select the top \(count) jobs from the following opportunities.\n\n"
        userMessage += "## CANDIDATE KNOWLEDGE CARDS\n\(knowledgeContext)\n\n"
        userMessage += "## CANDIDATE DOSSIER\n\(dossierContext)\n\n"
        userMessage += "## JOB OPPORTUNITIES\n"

        for job in jobs {
            userMessage += """
            ---
            ID: \(job.id.uuidString)
            Company: \(job.company)
            Role: \(job.role)
            Description: \(job.description)

            """
        }

        let response = try await runSingleShot(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            operation: "Job Selection"
        )
        return try parser.parseJobSelections(response)
    }
}

// MARK: - Agent Loop Delegate

/// One-shot delegate driving a Discovery agent task on the shared
/// `AnthropicToolLoopRunner`. Context tools (executed by
/// `DiscoveryToolExecutor`) feed the model; the loop terminates when the
/// model submits its final response through the `submit_final_response`
/// completion tool.
@MainActor
private final class DiscoveryAgentLoop: AnthropicToolLoopDelegate {
    private let llmFacade: LLMFacade
    private let toolExecutor: DiscoveryToolExecutor
    private let modelId: String
    private let systemPrompt: String
    private let userMessage: String

    /// Set after a no-tool turn so the next turn forces the completion tool —
    /// pre-runner behavior treated a plain text turn as the final answer, so a
    /// model that answers in prose is steered into resubmitting via the tool.
    private var forceCompletionNextTurn = false

    let maxTurns = 10
    private let maxResponseTokens = 8192

    init(
        llmFacade: LLMFacade,
        toolExecutor: DiscoveryToolExecutor,
        modelId: String,
        systemPrompt: String,
        userMessage: String
    ) {
        self.llmFacade = llmFacade
        self.toolExecutor = toolExecutor
        self.modelId = modelId
        self.systemPrompt = systemPrompt
        self.userMessage = userMessage
    }

    var completionToolName: String { DiscoveryToolSchemas.finalResponseToolName }

    func maxTurnsError() -> Error { DiscoveryAgentError.toolLoopExceeded }

    func initialMessages() -> [AnthropicMessage] {
        [.user(userMessage)]
    }

    func runModelTurn(messages: [AnthropicMessage]) async throws -> AnthropicTurnResult {
        let toolChoice: AnthropicToolChoice = forceCompletionNextTurn
            ? .tool(name: completionToolName)
            : .auto
        forceCompletionNextTurn = false

        let parameters = AnthropicMessageParameter(
            model: modelId,
            messages: messages,
            system: .blocks([AnthropicSystemBlock(text: fullSystemPrompt)]),
            maxTokens: maxResponseTokens,
            stream: false,
            tools: DiscoveryToolSchemas.allTools,
            toolChoice: toolChoice
        )
        let response = try await llmFacade.anthropicMessages(parameters: parameters)
        let usage = response.usage
        Logger.debug(
            "🧭 DiscoveryAgent usage (\(modelId)): input=\(usage.inputTokens) output=\(usage.outputTokens)",
            category: .ai
        )
        return AnthropicTurnResult(response: response)
    }

    func executeTools(_ toolCalls: [AnthropicToolUseResponseBlock]) async -> [String: AnthropicToolOutput] {
        var outputs: [String: AnthropicToolOutput] = [:]
        for call in toolCalls {
            Logger.debug("Executing Discovery tool: \(call.name)", category: .ai)
            let result = await toolExecutor.execute(toolName: call.name, arguments: call.input.jsonString)
            outputs[call.id] = AnthropicToolOutput(content: result)
        }
        return outputs
    }

    func parseCompletion(_ call: AnthropicToolUseResponseBlock) async throws -> String {
        guard let response = call.input["response"]?.value as? String,
              !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DiscoveryAgentError.invalidResponse
        }
        Logger.info("Discovery agent completed with response", category: .ai)
        return response
    }

    func handleNoTool(turnCount: Int, consecutiveNoToolTurns: Int) -> AnthropicNoToolDecision {
        // A plain text turn was the terminal shape before the runner migration;
        // steer the model into resubmitting that answer through the completion
        // tool (forced on the next turn, so this converges in one round trip).
        forceCompletionNextTurn = true
        return .nudge(
            "If that was your final response, call the \(completionToolName) tool now, "
            + "passing the complete response text as the `response` argument."
        )
    }

    func onMaxTurnsReached(messages: [AnthropicMessage]) async throws -> String? {
        nil  // → runner throws maxTurnsError()
    }

    private var fullSystemPrompt: String {
        systemPrompt + """


        ## Final Response
        When your analysis is complete, call the `\(DiscoveryToolSchemas.finalResponseToolName)` tool exactly once, \
        passing your complete final response — in exactly the output format requested above — as the `response` argument. \
        Do not put the final response in a plain text message.
        """
    }
}
