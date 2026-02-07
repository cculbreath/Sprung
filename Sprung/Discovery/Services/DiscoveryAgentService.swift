//
//  DiscoveryAgentService.swift
//  Sprung
//
//  Actor-based agent service for Discovery LLM interactions.
//  Uses LLMFacade for all LLM operations including web search.
//  Per SEARCHOPS_AMENDMENT: Uses local context management, NOT server-managed.
//

import Foundation
import SwiftOpenAI

// MARK: - Discovery Agent Service

actor DiscoveryAgentService {

    // MARK: - Dependencies

    private let llmFacade: LLMFacade
    private let toolExecutor: DiscoveryToolExecutor
    private let settingsStore: DiscoverySettingsStore
    private let parser = DiscoveryResponseParser()

    // MARK: - Configuration

    private let maxIterations = 10

    // MARK: - Initialization

    init(
        llmFacade: LLMFacade,
        contextProvider: DiscoveryContextProvider,
        settingsStore: DiscoverySettingsStore
    ) {
        self.llmFacade = llmFacade
        self.toolExecutor = DiscoveryToolExecutor(contextProvider: contextProvider)
        self.settingsStore = settingsStore
    }

    // MARK: - Model Configuration

    private var modelId: String {
        get async {
            await MainActor.run { settingsStore.current().llmModelId }
        }
    }

    private var reasoningEffort: String {
        get async {
            await MainActor.run { settingsStore.current().reasoningEffort }
        }
    }

    // MARK: - Prompt Loading

    private func loadPromptTemplate(named name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: "Prompts"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            Logger.error("Failed to load prompt template: \(name)", category: .ai)
            return "Error loading prompt template"
        }
        return content
    }

    // MARK: - Agent Loop (via LLMFacade)

    /// Run an agent loop with tool execution.
    /// - Parameters:
    ///   - systemPrompt: System prompt for the agent
    ///   - userMessage: User message to process
    ///   - enableTools: Whether to enable tool calling
    ///   - backend: LLM backend to use (.openAI for discovery model, .openRouter for OpenRouter models)
    func runAgent(
        systemPrompt: String,
        userMessage: String,
        enableTools: Bool = true,
        backend: LLMFacade.Backend = .openAI
    ) async throws -> String {
        let model = await modelId

        var messages: [ChatCompletionParameters.Message] = [
            .init(role: .system, content: .text(systemPrompt)),
            .init(role: .user, content: .text(userMessage))
        ]

        let tools = enableTools ? toolExecutor.getToolSchemas() : []

        var iterations = 0
        while iterations < maxIterations {
            iterations += 1

            let response = try await llmFacade.executeWithTools(
                messages: messages,
                tools: tools,
                toolChoice: enableTools ? .auto : nil,
                modelId: model,
                temperature: 0.7,
                backend: backend
            )

            guard let choices = response.choices,
                  let choice = choices.first,
                  let message = choice.message else {
                throw DiscoveryAgentError.noResponse
            }

            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                let assistantContent: ChatCompletionParameters.Message.ContentType =
                    message.content.map { .text($0) } ?? .text("")
                messages.append(ChatCompletionParameters.Message(
                    role: .assistant,
                    content: assistantContent,
                    toolCalls: message.toolCalls
                ))

                for toolCall in toolCalls {
                    let toolCallId = toolCall.id ?? UUID().uuidString
                    let toolName = toolCall.function.name ?? "unknown"
                    Logger.debug("Executing tool: \(toolName)", category: .ai)

                    let result = await toolExecutor.execute(
                        toolName: toolName,
                        arguments: toolCall.function.arguments
                    )

                    messages.append(ChatCompletionParameters.Message(
                        role: .tool,
                        content: .text(result),
                        toolCallID: toolCallId
                    ))
                }
                continue
            }

            Logger.info("Agent completed with response", category: .ai)
            return message.content ?? ""
        }

        throw DiscoveryAgentError.toolLoopExceeded
    }

    // MARK: - OpenAI Responses API (via LLMFacade)

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
            // LLMFacade is @MainActor - Swift handles the actor hop automatically
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
        let systemPrompt = loadPromptTemplate(named: "discovery_generate_daily_tasks")
        let response = try await runAgent(
            systemPrompt: systemPrompt,
            userMessage: "Generate today's job search tasks. Focus area: \(focusArea)"
        )
        return try parser.parseTasks(response)
    }

    func discoverJobSources(
        sectors: [String],
        location: String,
        candidateContext: String = "",
        statusCallback: (@MainActor @Sendable (DiscoveryStatus) async -> Void)? = nil
    ) async throws -> JobSourcesResult {
        let systemPrompt = loadPromptTemplate(named: "discovery_discover_job_sources")

        var userMessage = "Discover job sources for sectors: \(sectors.joined(separator: ", ")) in \(location)"
        if !candidateContext.isEmpty {
            userMessage += "\n\n\(candidateContext)"
        }

        let response = try await runOpenAIRequest(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            modelId: await modelId,
            reasoningEffort: await reasoningEffort,
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
        let systemPrompt = loadPromptTemplate(named: "discovery_discover_networking_events")

        var userMessage = "Find networking events for sectors: \(sectors.joined(separator: ", ")) in \(location) for the next \(daysAhead) days"
        if !candidateContext.isEmpty {
            userMessage += "\n\n\(candidateContext)"
        }

        let response = try await runOpenAIRequest(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            modelId: await modelId,
            reasoningEffort: await reasoningEffort,
            webSearchLocation: location,
            searchContext: "networking events",
            statusCallback: statusCallback,
            reasoningCallback: reasoningCallback
        )
        return try parser.parseEvents(response)
    }

    func prepareForEvent(eventId: UUID, focusCompanies: [String] = [], goals: String? = nil) async throws -> EventPrepResult {
        let systemPrompt = loadPromptTemplate(named: "discovery_prepare_for_event")
        var userMessage = "Prepare me for event \(eventId.uuidString)"
        if !focusCompanies.isEmpty {
            userMessage += ". Focus on companies: \(focusCompanies.joined(separator: ", "))"
        }
        if let goals = goals {
            userMessage += ". My goals: \(goals)"
        }
        let response = try await runAgent(systemPrompt: systemPrompt, userMessage: userMessage)
        return try parser.parsePrep(response)
    }

    func generateDebriefOutcomes(
        eventName: String,
        eventType: String,
        keyInsights: String,
        contactsMade: [String],
        notes: String
    ) async throws -> DebriefOutcomesResult {
        let systemPrompt = loadPromptTemplate(named: "discovery_debrief_outcomes")

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

        let response = try await runAgent(
            systemPrompt: systemPrompt,
            userMessage: contextParts.joined(separator: "\n\n"),
            enableTools: false
        )
        return try parser.parseDebriefOutcomes(response)
    }

    func generateWeeklyReflection() async throws -> String {
        let systemPrompt = loadPromptTemplate(named: "discovery_generate_weekly_reflection")
        return try await runAgent(
            systemPrompt: systemPrompt,
            userMessage: "Generate my weekly job search reflection"
        )
    }

    // TODO: Context source choice - may revisit (currently using knowledge cards + dossier)
    func chooseBestJobs(
        jobs: [(id: UUID, company: String, role: String, description: String)],
        knowledgeContext: String,
        dossierContext: String,
        count: Int = 5
    ) async throws -> JobSelectionsResult {
        let systemPrompt = loadPromptTemplate(named: "discovery_choose_best_jobs")

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

        let response = try await runOpenAIRequest(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            modelId: await modelId,
            reasoningEffort: await reasoningEffort
        )
        return try parser.parseJobSelections(response)
    }
}
