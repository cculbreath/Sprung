//
//  NarrativeDeduplicationService.swift
//  Sprung
//
//  Service for intelligent deduplication of narrative knowledge cards.
//  Uses a multi-turn agentic approach with filesystem tools.
//

import Foundation

/// Service for intelligent deduplication of narrative knowledge cards.
/// Uses a multi-turn agent to identify duplicates and synthesize merged cards.
@MainActor
final class NarrativeDeduplicationService {
    private var llmFacade: LLMFacade?
    private weak var eventBus: EventBus?
    private weak var agentActivityTracker: AgentActivityTracker?

    private func getModelId() throws -> String {
        try ModelConfigResolver.resolve(key: "onboardingCardMergeModelId", operation: "Narrative Deduplication")
    }

    private let workspaceService = CardMergeWorkspaceService()

    init(llmFacade: LLMFacade?, eventBus: EventBus? = nil, agentActivityTracker: AgentActivityTracker? = nil) {
        self.llmFacade = llmFacade
        self.eventBus = eventBus
        self.agentActivityTracker = agentActivityTracker
        Logger.info("🔀 NarrativeDeduplicationService initialized", category: .ai)
    }

    // MARK: - Public API

    /// Deduplicate narrative cards using a multi-turn agent.
    /// Creates a workspace, runs the merge agent, imports results, and cleans up.
    /// - Parameters:
    ///   - cards: Cards to deduplicate
    ///   - parentAgentId: Optional parent agent ID to use for tracking (avoids duplicate agent registration)
    func deduplicateCards(_ cards: [KnowledgeCard], parentAgentId: String? = nil) async throws -> DeduplicationResult {
        guard !cards.isEmpty else {
            return DeduplicationResult(cards: [], mergeLog: [])
        }

        guard let facade = llmFacade else {
            throw DeduplicationError.llmNotConfigured
        }

        let modelId = try getModelId()

        Logger.info("🔀 Starting agentic deduplication of \(cards.count) cards", category: .ai)
        Logger.info("🔀 Using model: \(modelId)", category: .ai)

        // Use parent agent ID if provided, otherwise create new agent
        let agentId: String
        if let parentId = parentAgentId {
            agentId = parentId
            // Just log to existing agent, don't create new one
            agentActivityTracker?.appendTranscript(
                agentId: agentId,
                entryType: .system,
                content: "Starting agentic deduplication of \(cards.count) cards"
            )
        } else {
            // Create standalone agent (e.g., when called from EventDumpView)
            agentId = UUID().uuidString
            if let tracker = agentActivityTracker {
                tracker.trackAgent(
                    id: agentId,
                    type: .cardMerge,
                    name: "Card Merge Agent",
                    task: nil as Task<Void, Never>?
                )
                tracker.appendTranscript(
                    agentId: agentId,
                    entryType: .system,
                    content: "Starting deduplication of \(cards.count) cards"
                )
            }
        }

        // Track whether we own this agent (for completion marking)
        let ownsAgent = parentAgentId == nil

        do {
            // Step 1: Create workspace
            let workspacePath = try workspaceService.createWorkspace()
            Logger.info("🔀 Workspace created at \(workspacePath.path)", category: .ai)

            agentActivityTracker?.appendTranscript(
                agentId: agentId,
                entryType: .system,
                content: "Created workspace",
                details: workspacePath.path
            )

            // Step 2: Export cards to workspace
            try workspaceService.exportCards(cards)
            Logger.info("🔀 Exported \(cards.count) cards to workspace", category: .ai)

            agentActivityTracker?.appendTranscript(
                agentId: agentId,
                entryType: .toolResult,
                content: "Exported \(cards.count) cards to workspace"
            )

            // Step 3: Run merge agent
            let agent = CardMergeAgent(
                workspacePath: workspacePath,
                modelId: modelId,
                facade: facade,
                eventBus: eventBus,
                agentId: agentId,
                tracker: agentActivityTracker
            )

            let agentResult = try await agent.run()

            Logger.info("🔀 Agent completed: \(agentResult.originalCount) → \(agentResult.finalCount) cards (\(agentResult.mergeCount) merged)", category: .ai)

            agentActivityTracker?.appendTranscript(
                agentId: agentId,
                entryType: .assistant,
                content: "Merge complete",
                details: "\(agentResult.originalCount) → \(agentResult.finalCount) cards"
            )

            // Step 4: Import results
            let resultCards = try workspaceService.importCards()
            Logger.info("🔀 Imported \(resultCards.count) cards from workspace", category: .ai)

            // Step 5: Cleanup workspace
            try workspaceService.deleteWorkspace()
            Logger.info("🔀 Workspace cleaned up", category: .ai)

            // Mark agent complete (only if we created it)
            if ownsAgent {
                agentActivityTracker?.markCompleted(agentId: agentId)
            }

            return DeduplicationResult(cards: resultCards, mergeLog: agentResult.mergeLog)

        } catch {
            Logger.error("🔀 Deduplication failed: \(error.localizedDescription)", category: .ai)

            // Cleanup on error
            try? workspaceService.deleteWorkspace()

            // Mark agent failed (only if we created it)
            if ownsAgent {
                agentActivityTracker?.markFailed(agentId: agentId, error: error.localizedDescription)
            }

            throw error
        }
    }

    // MARK: - Errors

    enum DeduplicationError: Error, LocalizedError {
        case llmNotConfigured
        case workspaceError(String)
        case agentError(String)

        var errorDescription: String? {
            switch self {
            case .llmNotConfigured:
                return "LLM facade not configured"
            case .workspaceError(let msg):
                return "Workspace error: \(msg)"
            case .agentError(let msg):
                return "Agent error: \(msg)"
            }
        }
    }
}

// MARK: - Result Types

struct DeduplicationResult {
    let cards: [KnowledgeCard]
    let mergeLog: [MergeLogEntry]
}

struct MergeLogEntry {
    enum Action: String {
        case kept
        case keptSeparate
        case merged
        case error
    }

    let action: Action
    let inputCardIds: [String]
    let outputCardId: String?

    init(action: Action, inputCardIds: [String], outputCardId: String?, reasoning: String) {
        self.inputCardIds = inputCardIds
        self.outputCardId = outputCardId
        self.action = action
    }
}
