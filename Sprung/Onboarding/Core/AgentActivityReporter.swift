import Foundation

/// Self-contained bridge between the onboarding state actor and the MainActor-isolated
/// `AgentActivityTracker`. Owns the tracker reference and exposes async accessors that
/// hop to the MainActor to read running/completed agent status for inclusion in the
/// interview working-memory context. Holds no wire/event/conversation/phase state.
actor AgentActivityReporter {
    private var agentActivityTracker: AgentActivityTracker?

    /// Set the agent activity tracker for status reporting
    func setAgentActivityTracker(_ tracker: AgentActivityTracker) {
        self.agentActivityTracker = tracker
    }

    /// Get running agent status for inclusion in interview context
    func getRunningAgentStatus() async -> [(type: String, name: String, status: String)]? {
        guard let tracker = agentActivityTracker else { return nil }

        // Access MainActor-isolated tracker
        let runningAgents = await MainActor.run { tracker.runningAgents }
        guard !runningAgents.isEmpty else { return nil }

        return runningAgents.map { agent in
            (type: agent.agentType.displayName,
             name: agent.name,
             status: agent.statusMessage ?? "Running...")
        }
    }

    /// Get recently completed agents (within last 30 seconds) for inclusion in interview context
    func getRecentlyCompletedAgents() async -> [(type: String, name: String, succeeded: Bool, duration: String)]? {
        guard let tracker = agentActivityTracker else { return nil }

        let cutoff = Date().addingTimeInterval(-30) // Last 30 seconds
        let recentAgents = await MainActor.run {
            tracker.agents.filter { agent in
                guard let endTime = agent.endTime else { return false }
                return endTime > cutoff && (agent.status == .completed || agent.status == .failed)
            }
        }
        guard !recentAgents.isEmpty else { return nil }

        return recentAgents.map { agent in
            (type: agent.agentType.displayName,
             name: agent.name,
             succeeded: agent.status == .completed,
             duration: agent.durationString)
        }
    }
}
