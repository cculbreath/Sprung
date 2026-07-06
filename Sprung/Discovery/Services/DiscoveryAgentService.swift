//
//  DiscoveryAgentService.swift
//  Sprung
//
//  Agent service for Discovery LLM interactions.
//  Tool-loop flows (event prep, weekly reflection, networking-event
//  discovery) run on the shared AnthropicToolLoopRunner against the
//  user-selected Discovery Anthropic model — event discovery additionally
//  carries Anthropic's server-side web_search/web_fetch tools (see
//  EventDiscoveryLoop). Single-shot flows (debrief outcomes,
//  choose-best-jobs, and the onboarding structured calls: role
//  suggestions + location-preference extraction) are plain Anthropic
//  Messages calls. Daily-task generation lives in DailyTaskGenerator —
//  the single generation path.
//

import Foundation
import SwiftOpenAI

// MARK: - Discovery Agent Service

@MainActor
final class DiscoveryAgentService {

    // MARK: - Dependencies

    private let llmFacade: LLMFacade
    private let toolExecutor: DiscoveryToolExecutor
    private let parser = DiscoveryResponseParser()
    private weak var activityTracker: BackgroundActivityTracker?

    // MARK: - Model Configuration

    /// UserDefaults key for the user-selected Anthropic model powering all
    /// Discovery agent + coaching LLM flows (Settings > Models > Discovery Agent).
    static let anthropicModelSettingKey = "discoveryAnthropicModelId"

    // MARK: - Initialization

    init(
        llmFacade: LLMFacade,
        contextProvider: DiscoveryContextProviderImpl
    ) {
        self.llmFacade = llmFacade
        self.toolExecutor = DiscoveryToolExecutor(contextProvider: contextProvider)
    }

    /// Set the tracker that surfaces background discovery runs in the
    /// Background Activity window and the main-window indicator.
    func setActivityTracker(_ tracker: BackgroundActivityTracker) {
        self.activityTracker = tracker
    }

    /// The user-selected Anthropic model for Discovery agent flows.
    /// Throws `ModelConfigurationError` when unset — never substitutes a default.
    private func anthropicModelId(operation: String) throws -> String {
        try ModelConfigResolver.resolve(key: Self.anthropicModelSettingKey, operation: operation)
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

    // MARK: - Task Methods

    /// Discover networking events via a multi-turn Anthropic agent loop with
    /// server-side web_search + web_fetch (EventDiscoveryLoop). Every returned
    /// event was page-verified by the agent before submission.
    func discoverNetworkingEvents(
        sectors: [String],
        location: String,
        candidateContext: String = "",
        knownEventsContext: String = "",
        attendedHistoryContext: String = "",
        operatorGuidance: String = "",
        daysAhead: Int = 42,
        statusCallback: (@MainActor @Sendable (DiscoveryStatus) async -> Void)? = nil,
        reasoningCallback: (@MainActor @Sendable (String) async -> Void)? = nil
    ) async throws -> [DiscoveredEvent] {
        let systemPrompt = try loadPromptTemplate(named: "discovery_discover_events")
        let modelId = try anthropicModelId(operation: "Event Discovery")

        let userMessage = Self.eventDiscoveryUserMessage(
            sectors: sectors,
            location: location,
            candidateContext: candidateContext,
            knownEventsContext: knownEventsContext,
            attendedHistoryContext: attendedHistoryContext,
            operatorGuidance: operatorGuidance,
            today: Date(),
            daysAhead: daysAhead
        )

        await statusCallback?(.webSearching(context: "networking events"))

        // Surface the run in the background-activity UI: one operation per
        // discovery run, with the loop's per-turn progress lines
        // ("Searching: …", "Fetching: …") as the live phase.
        let tracker = activityTracker
        let operationId = UUID().uuidString
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        tracker?.trackOperation(
            id: operationId,
            type: .eventDiscovery,
            name: trimmedLocation.isEmpty ? "Networking events" : "Networking events — \(trimmedLocation)"
        )
        tracker?.updatePhase(operationId: operationId, phase: "Searching the web")

        let loop = EventDiscoveryLoop(
            llmFacade: llmFacade,
            modelId: modelId,
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            onProgress: { line in
                tracker?.updatePhase(operationId: operationId, phase: line)
                await reasoningCallback?(line + "\n")
            }
        )
        do {
            let events = try await AnthropicToolLoopRunner(delegate: loop).run()
            await statusCallback?(.webSearchComplete)
            tracker?.appendTranscript(
                operationId: operationId,
                entryType: .system,
                content: "Completed with \(events.count) verified event\(events.count == 1 ? "" : "s")"
            )
            tracker?.markCompleted(operationId: operationId)
            return events
        } catch {
            tracker?.markFailed(operationId: operationId, error: error.localizedDescription)
            throw error
        }
    }

    // MARK: - Event-Discovery Context Assembly (pure — covered by EventDiscoveryLoopTests)

    /// Most recent attended events kept as taste signal; older history adds
    /// tokens without sharpening the signal.
    static let attendedHistoryLimit = 10

    /// Format most-recent-first attended-event records into the agent's
    /// taste-signal block, capped at `attendedHistoryLimit`. Empty when there
    /// is no history.
    static func attendedHistoryContext(_ records: [AttendedEventRecord]) -> String {
        records.prefix(attendedHistoryLimit).map { record in
            var line = "- \(record.name) — \(record.eventType)"
            if let organizer = record.organizer, !organizer.isEmpty {
                line += ", organizer: \(organizer)"
            }
            if let rating = record.rating {
                line += ", rated \(rating)/5"
            }
            return line
        }.joined(separator: "\n")
    }

    /// Build the event-discovery task message: today's date plus the two
    /// windows the prompt keys on (PRIORITY WINDOW = next 7 days, the core
    /// deliverable of a weekly run; FULL WINDOW = `daysAhead`), then the
    /// optional context blocks. Attended history (taste signal) stays distinct
    /// from known events (do-not-resubmit); operator guidance is delimited so
    /// the prompt can scope it to steering, never to waiving verification.
    static func eventDiscoveryUserMessage(
        sectors: [String],
        location: String,
        candidateContext: String,
        knownEventsContext: String,
        attendedHistoryContext: String,
        operatorGuidance: String,
        today: Date,
        daysAhead: Int
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let calendar = Calendar.current
        let priorityEnd = calendar.date(byAdding: .day, value: 7, to: today) ?? today
        let windowEnd = calendar.date(byAdding: .day, value: daysAhead, to: today) ?? today

        var message = """
            Find networking events for this job seeker.

            Target sectors: \(sectors.joined(separator: ", "))
            Location: \(location)
            Today: \(formatter.string(from: today))
            PRIORITY WINDOW (next 7 days): \(formatter.string(from: today)) through \(formatter.string(from: priorityEnd))
            FULL WINDOW: \(formatter.string(from: today)) through \(formatter.string(from: windowEnd))
            """
        if !candidateContext.isEmpty {
            message += "\n\n\(candidateContext)"
        }
        if !attendedHistoryContext.isEmpty {
            message += "\n\n## ATTENDED EVENT HISTORY (what the user actually shows up to)\n\(attendedHistoryContext)"
        }
        if !knownEventsContext.isEmpty {
            message += "\n\n## ALREADY KNOWN EVENTS (do not resubmit)\n\(knownEventsContext)"
        }
        let guidance = operatorGuidance.trimmingCharacters(in: .whitespacesAndNewlines)
        if !guidance.isEmpty {
            message += "\n\n## OPERATOR GUIDANCE FOR THIS RUN\n\(guidance)"
        }
        return message
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

    func generateWeeklyReflection(previousWeekNotes: String?) async throws -> String {
        let systemPrompt = try loadPromptTemplate(named: "discovery_generate_weekly_reflection")

        var userMessage = "Generate my weekly job search reflection"
        if let previousWeekNotes,
           !previousWeekNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            userMessage += "\n\n## Last Week's Review Notes (written by the user)\n\(previousWeekNotes)"
        }

        return try await runAgent(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
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

    // MARK: - Onboarding Structured Calls (single-shot, structured output)

    /// Suggest 5-8 specific target job titles from the user's dossier.
    /// Discovery-onboarding-only. The facade sets maxTokens to the model's
    /// full completion headroom (4096 floor), so schema-bounded responses
    /// aren't truncated.
    func suggestTargetRoles(
        dossierSummary: String,
        existingRoles: [String] = [],
        keywords: String? = nil
    ) async throws -> [String] {
        let modelId = try anthropicModelId(operation: "Role Suggestions")
        let result: RoleSuggestionsResult = try await llmFacade.executeStructuredWithAnthropicCaching(
            systemContent: [AnthropicSystemBlock(text: Self.roleSuggestionsSystemPrompt)],
            userPrompt: Self.roleSuggestionsUserPrompt(
                dossierSummary: dossierSummary,
                existingRoles: existingRoles,
                keywords: keywords
            ),
            modelId: modelId,
            responseType: RoleSuggestionsResult.self,
            schema: Self.roleSuggestionsSchema
        )
        return result.suggestedRoles
    }

    /// Extract location and work-arrangement preferences from the applicant
    /// profile and dossier. Discovery-onboarding-only.
    func extractLocationPreferences(
        profileInfo: String,
        dossierSummary: String
    ) async throws -> ExtractedLocationPreferences {
        let modelId = try anthropicModelId(operation: "Location Preferences")
        let result: LocationPreferencesResult = try await llmFacade.executeStructuredWithAnthropicCaching(
            systemContent: [AnthropicSystemBlock(text: Self.locationPreferencesSystemPrompt)],
            userPrompt: Self.locationPreferencesUserPrompt(
                profileInfo: profileInfo,
                dossierSummary: dossierSummary
            ),
            modelId: modelId,
            responseType: LocationPreferencesResult.self,
            schema: Self.locationPreferencesSchema
        )
        return Self.extractedPreferences(from: result)
    }

    // MARK: - Onboarding Call Prompts & Schemas (pure — unit-testable halves)

    static let roleSuggestionsSystemPrompt =
        "You are a career advisor helping someone identify job roles to target. Be specific with job titles."

    /// Build the role-suggestions user prompt. Existing roles and keywords are
    /// optional context blocks; the schema pins the output shape.
    static func roleSuggestionsUserPrompt(
        dossierSummary: String,
        existingRoles: [String],
        keywords: String?
    ) -> String {
        let existingContext = existingRoles.isEmpty
            ? ""
            : "\n\nThe user has already indicated interest in: \(existingRoles.joined(separator: ", ")). Suggest additional complementary roles they might not have considered."

        let keywordsContext: String
        if let keywords, !keywords.isEmpty {
            keywordsContext = "\n\nKEYWORDS TO EXPLORE:\nThe user is particularly interested in roles related to: \(keywords). Prioritize suggestions that connect their background to these areas, industries, or themes."
        } else {
            keywordsContext = ""
        }

        return """
            Based on the following professional background, suggest 5-8 specific job roles/titles this person should target in their job search.

            BACKGROUND:
            \(dossierSummary)
            \(existingContext)\(keywordsContext)

            Focus on:
            1. Roles that match their experience level
            2. Both obvious fits and adjacent opportunities they might not have considered
            3. Specific titles (e.g., "Senior Software Engineer", "Engineering Manager", "Staff Developer"), not broad categories
            \(keywordsContext.isEmpty ? "" : "4. Roles that connect to the specified keywords/interests")
            """
    }

    static let roleSuggestionsSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "suggestedRoles": [
                "type": "array",
                "description": "List of specific job titles to target",
                "items": ["type": "string"]
            ],
            "reasoning": [
                "type": ["string", "null"],
                "description": "Brief explanation of why these roles fit, or null"
            ]
        ],
        "required": ["suggestedRoles", "reasoning"],
        "additionalProperties": false
    ]

    static let locationPreferencesSystemPrompt =
        "Extract job search preferences from the provided profile and background. Return null for fields that cannot be determined."

    /// Build the location-preferences user prompt from the applicant profile
    /// and dossier context.
    static func locationPreferencesUserPrompt(
        profileInfo: String,
        dossierSummary: String
    ) -> String {
        """
        Extract job search preferences from the following sources.

        APPLICANT PROFILE:
        \(profileInfo)

        BACKGROUND/DOSSIER:
        \(dossierSummary)

        Infer from context clues like mentions of relocating, working from home, commuting preferences, company culture preferences, etc.
        """
    }

    static let locationPreferencesSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "location": [
                "type": ["string", "null"],
                "description": "Primary job search location (e.g., 'San Francisco Bay Area', 'Austin, TX'). Null if not determinable."
            ],
            "workArrangement": [
                "type": ["string", "null"],
                "description": "Work arrangement preference: remote, hybrid, or onsite. Null if not determinable."
            ],
            "remoteAcceptable": [
                "type": ["boolean", "null"],
                "description": "True if open to remote work, false if prefers in-person. Null if not determinable."
            ],
            "companySize": [
                "type": ["string", "null"],
                "description": "Preferred company size: startup, small, mid, enterprise, or any. Null if not determinable."
            ]
        ],
        "required": ["location", "workArrangement", "remoteAcceptable", "companySize"],
        "additionalProperties": false
    ]

    /// Map the wire DTO into the typed preferences the onboarding flow
    /// consumes. Unrecognized enum strings map to nil — the flow leaves the
    /// corresponding field untouched rather than guessing.
    static func extractedPreferences(from result: LocationPreferencesResult) -> ExtractedLocationPreferences {
        ExtractedLocationPreferences(
            location: result.location,
            workArrangement: parseWorkArrangement(result.workArrangement),
            remoteAcceptable: result.remoteAcceptable,
            companySize: parseCompanySizePreference(result.companySize)
        )
    }

    static func parseWorkArrangement(_ raw: String?) -> WorkArrangement? {
        switch raw?.lowercased() {
        case "remote": return .remote
        case "hybrid": return .hybrid
        case "onsite", "on-site", "in-office": return .onsite
        default: return nil
        }
    }

    static func parseCompanySizePreference(_ raw: String?) -> CompanySizePreference? {
        switch raw?.lowercased() {
        case "startup": return .startup
        case "small": return .small
        case "mid", "mid-size", "midsize": return .mid
        case "enterprise", "large": return .enterprise
        case "any": return .any
        default: return nil
        }
    }
}

// MARK: - Onboarding Call DTOs

/// Wire contract of the role-suggestions structured call (camelCase keys we
/// control; `reasoning` arrives as explicit JSON null when the model has
/// nothing to add).
struct RoleSuggestionsResult: Codable {
    let suggestedRoles: [String]
    let reasoning: String?
}

/// Wire contract of the location-preferences structured call. Every field is
/// nullable — the model returns null for anything the sources don't support.
struct LocationPreferencesResult: Codable {
    let location: String?
    let workArrangement: String?
    let remoteAcceptable: Bool?
    let companySize: String?
}

/// Location preferences with parsed enums, as consumed by the Discovery
/// onboarding flow.
struct ExtractedLocationPreferences {
    let location: String?
    let workArrangement: WorkArrangement?
    let remoteAcceptable: Bool?
    let companySize: CompanySizePreference?
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
