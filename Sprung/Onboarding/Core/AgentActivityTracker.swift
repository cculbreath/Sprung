//
//  AgentActivityTracker.swift
//  Sprung
//
//  Central tracking and transcript storage for all parallel agents.
//  Enables Agent Tabs UI to show running/completed agents with full conversation history.
//

import Foundation
import SwiftyJSON
import Observation

// MARK: - Agent Types

/// Types of agents that can run in the onboarding system
enum AgentType: String, Codable, CaseIterable {
    case documentIngestion = "doc_ingest"
    case gitIngestion = "git_ingest"
    case knowledgeCard = "knowledge_card"
    case cardMerge = "card_merge"
    case backgroundMerge = "bg_merge"
    case pdfExtraction = "pdf_extract"
    case documentRegen = "doc_regen"
    case voiceProfile = "voice_profile"
    case skillsProcessing = "skills_processing"
    case atsExpansion = "ats_expansion"
    case enrichment = "enrichment"

    var displayName: String {
        switch self {
        case .documentIngestion: return "Doc Ingest"
        case .gitIngestion: return "Git Ingest"
        case .knowledgeCard: return "KC Agent"
        case .cardMerge: return "Card Merge"
        case .backgroundMerge: return "Merge"
        case .pdfExtraction: return "PDF Extract"
        case .documentRegen: return "Regen"
        case .voiceProfile: return "Voice Profile"
        case .skillsProcessing: return "Skills"
        case .atsExpansion: return "ATS"
        case .enrichment: return "Enrichment"
        }
    }

    var icon: String {
        switch self {
        case .documentIngestion: return "doc.text"
        case .gitIngestion: return "chevron.left.forwardslash.chevron.right"
        case .knowledgeCard: return "brain.head.profile"
        case .cardMerge: return "arrow.triangle.merge"
        case .backgroundMerge: return "arrow.triangle.branch"
        case .pdfExtraction: return "doc.viewfinder"
        case .documentRegen: return "arrow.clockwise"
        case .voiceProfile: return "mic"
        case .skillsProcessing: return "hammer"
        case .atsExpansion: return "text.badge.plus"
        case .enrichment: return "sparkles"
        }
    }
}

/// Status of a tracked agent
enum AgentStatus: String, Codable {
    case pending = "pending"
    case running = "running"
    case completed = "completed"
    case failed = "failed"
    case killed = "killed"
}

// MARK: - Task Cancellation

/// Type-erased wrapper for any Task, enabling cancellation regardless of Success/Failure types.
/// This is necessary because `Task<Success, Failure>.cancel()` is available for all Task types,
/// but Swift's type system doesn't allow storing heterogeneous Task types without type erasure.
final class AnyCancellableTask: @unchecked Sendable {
    private let _cancel: () -> Void

    init<Success, Failure>(_ task: Task<Success, Failure>) {
        self._cancel = { task.cancel() }
    }

    func cancel() {
        _cancel()
    }
}

// MARK: - Transcript Entry

/// A single entry in an agent's conversation transcript
struct AgentTranscriptEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let entryType: EntryType
    let content: String
    let details: String?

    enum EntryType: String, Codable {
        case system = "system"
        case tool = "tool"
        case assistant = "assistant"
        case error = "error"
        case toolResult = "tool_result"
        case turn = "turn"  // LLM turn marker
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        entryType: EntryType,
        content: String,
        details: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.entryType = entryType
        self.content = content
        self.details = details
    }
}

// MARK: - Tracked Agent

/// A single tracked agent with its full transcript
struct TrackedAgent: Identifiable, Codable {
    let id: String
    let agentType: AgentType
    let name: String
    var status: AgentStatus
    let startTime: Date
    var endTime: Date?
    var transcript: [AgentTranscriptEntry]
    var error: String?

    // Token usage tracking
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cachedTokens: Int = 0

    /// Current status message for running agents (e.g., "Analyzing repository structure...")
    var statusMessage: String?

    /// Parent agent ID for nested child agents (nil for top-level agents)
    var parentAgentId: String?

    /// Child agent IDs (populated by tracker, not persisted directly)
    var childAgentIds: [String] = []

    /// Total tokens processed (input + output only).
    /// Note: cachedTokens are already included in inputTokens by the API,
    /// so we don't add them separately to avoid double-counting.
    var totalTokens: Int { inputTokens + outputTokens }

    /// Duration in seconds (nil if still running)
    var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime)
    }

    /// Formatted duration string
    var durationString: String {
        guard let duration = duration else { return "Running..." }
        return String(format: "%.1fs", duration)
    }

    /// Whether this is a child agent
    var isChildAgent: Bool { parentAgentId != nil }

    /// Whether this agent has running children
    var hasRunningChildren: Bool { false } // Computed by tracker

    init(
        id: String = UUID().uuidString,
        agentType: AgentType,
        name: String,
        status: AgentStatus = .running,
        startTime: Date = Date(),
        endTime: Date? = nil,
        transcript: [AgentTranscriptEntry] = [],
        error: String? = nil,
        parentAgentId: String? = nil
    ) {
        self.id = id
        self.agentType = agentType
        self.name = name
        self.status = status
        self.startTime = startTime
        self.endTime = endTime
        self.transcript = transcript
        self.error = error
        self.parentAgentId = parentAgentId
    }
}

// MARK: - Agent Completion Summary

/// Summary of a completed agent for notification purposes
struct AgentCompletionSummary {
    let agentType: AgentType
    let name: String
    let succeeded: Bool
    let duration: TimeInterval?
    let errorMessage: String?
}

// MARK: - Agent Activity Tracker

/// Central tracking for all agent activity with full transcript storage.
/// Observable for SwiftUI integration with Agent Tabs UI.
@Observable
@MainActor
class AgentActivityTracker {
    // MARK: - State

    /// All tracked agents (running and completed)
    private(set) var agents: [TrackedAgent] = []

    /// Currently selected agent ID for detail view
    var selectedAgentId: String?

    /// Active task handles for cancellation (type-erased to support any Task type)
    private var activeTasks: [String: AnyCancellableTask] = [:]

    /// Set of agent IDs that have been cancelled. Agents can check this flag to stop work.
    /// This provides cancellation support even when the Task reference isn't stored.
    private var cancelledAgentIds: Set<String> = []

    /// Callback fired when all running agents complete (count transitions from >0 to 0)
    /// Provides summaries of the agents that just completed in this batch
    var onAllAgentsCompleted: (([AgentCompletionSummary]) -> Void)?

    /// Tracks agent IDs that completed since the last "all done" notification
    private var recentlyCompletedAgentIds: Set<String> = []

    // MARK: - Computed Properties

    /// Count of currently running agents
    var runningAgentCount: Int {
        agents.filter { $0.status == .running }.count
    }

    /// Whether any agent is currently running
    var isAnyRunning: Bool {
        runningAgentCount > 0
    }

    /// Running agents only
    var runningAgents: [TrackedAgent] {
        agents.filter { $0.status == .running }
    }

    // MARK: - Agent Lifecycle

    /// Register a new agent for tracking
    /// - Returns: The agent ID for later reference
    @discardableResult
    func trackAgent<Success, Failure>(
        id: String = UUID().uuidString,
        type: AgentType,
        name: String,
        status: AgentStatus = .running,
        task: Task<Success, Failure>? = nil
    ) -> String {
        let agent = TrackedAgent(
            id: id,
            agentType: type,
            name: name,
            status: status,
            startTime: Date()
        )

        agents.insert(agent, at: 0) // Most recent first

        if let task = task {
            activeTasks[id] = AnyCancellableTask(task)
        }

        let statusEmoji = status == .pending ? "⏳" : "🚀"
        Logger.info("\(statusEmoji) Agent tracked: [\(type.displayName)] \(name) (id: \(id.prefix(8)), status: \(status.rawValue))", category: .ai)

        return id
    }

    /// Track a child agent nested under a parent
    /// - Returns: The child agent ID for later reference
    @discardableResult
    func trackChildAgent<Success, Failure>(
        id: String = UUID().uuidString,
        parentAgentId: String,
        type: AgentType,
        name: String,
        status: AgentStatus = .running,
        task: Task<Success, Failure>? = nil
    ) -> String {
        let agent = TrackedAgent(
            id: id,
            agentType: type,
            name: name,
            status: status,
            startTime: Date(),
            parentAgentId: parentAgentId
        )

        agents.insert(agent, at: 0) // Most recent first

        // Link to parent
        if let parentIndex = agents.firstIndex(where: { $0.id == parentAgentId }) {
            agents[parentIndex].childAgentIds.append(id)
        }

        if let task = task {
            activeTasks[id] = AnyCancellableTask(task)
        }

        Logger.info("🔀 Child agent tracked: [\(type.displayName)] \(name) (parent: \(parentAgentId.prefix(8)))", category: .ai)

        return id
    }

    /// Get child agents for a parent
    func childAgents(for parentAgentId: String) -> [TrackedAgent] {
        agents.filter { $0.parentAgentId == parentAgentId }
    }

    /// Check if a parent agent has any running children
    func hasRunningChildren(agentId: String) -> Bool {
        childAgents(for: agentId).contains { $0.status == .running }
    }

    /// Mark an agent as running (transitions from pending)
    func markRunning(agentId: String) {
        guard let index = agents.firstIndex(where: { $0.id == agentId }) else {
            Logger.warning("⚠️ Cannot mark running: agent not found (id: \(agentId.prefix(8)))", category: .ai)
            return
        }

        agents[index].status = .running
        Logger.info("🚀 Agent started: \(agents[index].name) (id: \(agentId.prefix(8)))", category: .ai)
    }

    /// Associate a task with an already-tracked agent
    func setTask<Success, Failure>(_ task: Task<Success, Failure>, forAgentId agentId: String) {
        activeTasks[agentId] = AnyCancellableTask(task)
    }

    /// Append a transcript entry to an agent
    func appendTranscript(
        agentId: String,
        entryType: AgentTranscriptEntry.EntryType,
        content: String,
        details: String? = nil
    ) {
        guard let index = agents.firstIndex(where: { $0.id == agentId }) else {
            Logger.warning("⚠️ Cannot append transcript: agent not found (id: \(agentId.prefix(8)))", category: .ai)
            return
        }

        let entry = AgentTranscriptEntry(
            entryType: entryType,
            content: content,
            details: details
        )

        agents[index].transcript.append(entry)
    }

    /// Mark an agent as completed successfully
    func markCompleted(agentId: String) {
        guard let index = agents.firstIndex(where: { $0.id == agentId }) else {
            Logger.warning("⚠️ Cannot mark completed: agent not found (id: \(agentId.prefix(8)))", category: .ai)
            return
        }

        agents[index].status = .completed
        agents[index].endTime = Date()
        activeTasks[agentId] = nil
        recentlyCompletedAgentIds.insert(agentId)

        Logger.info("✅ Agent completed: \(agents[index].name) (\(agents[index].durationString))", category: .ai)

        checkAllAgentsCompleted()
    }

    /// Mark an agent as failed with an error message
    func markFailed(agentId: String, error: String) {
        guard let index = agents.firstIndex(where: { $0.id == agentId }) else {
            Logger.warning("⚠️ Cannot mark failed: agent not found (id: \(agentId.prefix(8)))", category: .ai)
            return
        }

        agents[index].status = .failed
        agents[index].endTime = Date()
        agents[index].error = error
        activeTasks[agentId] = nil
        recentlyCompletedAgentIds.insert(agentId)

        // Add error to transcript
        appendTranscript(
            agentId: agentId,
            entryType: .error,
            content: "Agent failed",
            details: error
        )

        checkAllAgentsCompleted()

        Logger.error("❌ Agent failed: \(agents[index].name) - \(error)", category: .ai)
    }

    /// Add token usage to an agent's running totals
    func addTokenUsage(agentId: String, input: Int, output: Int, cached: Int = 0) {
        guard let index = agents.firstIndex(where: { $0.id == agentId }) else {
            Logger.warning("⚠️ Cannot add token usage: agent not found (id: \(agentId.prefix(8)))", category: .ai)
            return
        }

        agents[index].inputTokens += input
        agents[index].outputTokens += output
        agents[index].cachedTokens += cached

        Logger.debug(
            "📊 Agent token usage: +\(input) in, +\(output) out (total: \(agents[index].totalTokens))",
            category: .ai
        )
    }

    /// Update the current status message for a running agent
    func updateStatusMessage(agentId: String, message: String?) {
        guard let index = agents.firstIndex(where: { $0.id == agentId }) else {
            return // Silent fail - status updates are non-critical
        }

        agents[index].statusMessage = message
    }

    /// Kill (cancel) a running agent
    func killAgent(agentId: String) async {
        guard let index = agents.firstIndex(where: { $0.id == agentId }) else {
            Logger.warning("⚠️ Cannot kill: agent not found (id: \(agentId.prefix(8)))", category: .ai)
            return
        }

        // Mark as cancelled so agents checking isCancelled() will stop
        cancelledAgentIds.insert(agentId)

        // Also cancel any child agents
        for childId in agents[index].childAgentIds {
            cancelledAgentIds.insert(childId)
            if let childTask = activeTasks[childId] {
                childTask.cancel()
                activeTasks[childId] = nil
            }
        }

        // Cancel the task if it exists
        if let task = activeTasks[agentId] {
            task.cancel()
            activeTasks[agentId] = nil
        }

        agents[index].status = .killed
        agents[index].endTime = Date()

        // Add kill notice to transcript
        appendTranscript(
            agentId: agentId,
            entryType: .system,
            content: "Agent cancelled by user"
        )

        Logger.info("⏹️ Agent killed: \(agents[index].name)", category: .ai)
    }

    /// Kill all running agents
    func killAllAgents() async {
        let runningAgentIds = agents.filter { $0.status == .running }.map { $0.id }
        for agentId in runningAgentIds {
            await killAgent(agentId: agentId)
        }
        if !runningAgentIds.isEmpty {
            Logger.info("⏹️ Killed \(runningAgentIds.count) running agent(s)", category: .ai)
        }
    }

    /// Check if an agent has been cancelled. Agents should call this periodically to support cancellation.
    /// - Returns: true if the agent has been cancelled and should stop work
    func isCancelled(agentId: String) -> Bool {
        cancelledAgentIds.contains(agentId)
    }

    /// Throws CancellationError if the agent has been cancelled.
    /// Convenience method for agents to check cancellation and throw in one call.
    func checkCancellation(agentId: String) throws {
        if cancelledAgentIds.contains(agentId) {
            throw CancellationError()
        }
    }

    // MARK: - Query Methods

    /// Get a specific agent by ID
    func getAgent(id: String) -> TrackedAgent? {
        agents.first { $0.id == id }
    }

    // MARK: - Private Helpers

    /// Check if all agents completed and fire callback if so
    private func checkAllAgentsCompleted() {
        guard runningAgentCount == 0,
              !recentlyCompletedAgentIds.isEmpty,
              let callback = onAllAgentsCompleted else {
            return
        }

        // Build summaries for recently completed agents
        let summaries: [AgentCompletionSummary] = recentlyCompletedAgentIds.compactMap { agentId in
            guard let agent = agents.first(where: { $0.id == agentId }) else { return nil }
            return AgentCompletionSummary(
                agentType: agent.agentType,
                name: agent.name,
                succeeded: agent.status == .completed,
                duration: agent.duration,
                errorMessage: agent.error
            )
        }

        // Clear the tracking set
        recentlyCompletedAgentIds.removeAll()

        Logger.info("🏁 All agents completed (\(summaries.count) in batch)", category: .ai)

        // Fire the callback
        callback(summaries)
    }
}
