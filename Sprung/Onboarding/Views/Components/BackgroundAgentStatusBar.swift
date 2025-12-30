//
//  BackgroundAgentStatusBar.swift
//  Sprung
//
//  Full-width status bar showing background agent activity.
//  Displayed at the bottom of the onboarding interview window.
//

import SwiftUI

/// Full-width status bar showing background agent operations
struct BackgroundAgentStatusBar: View {
    let tracker: AgentActivityTracker
    let extractionMessage: String?
    let isExtractionInProgress: Bool

    /// Maximum number of agents to display before showing "+N more"
    private let maxVisibleAgents = 3

    private var hasActivity: Bool {
        tracker.isAnyRunning || isExtractionInProgress
    }

    /// Running agents to display (limited to maxVisibleAgents)
    private var visibleAgents: [TrackedAgent] {
        Array(tracker.runningAgents.prefix(maxVisibleAgents))
    }

    /// Number of agents not shown
    private var hiddenAgentCount: Int {
        max(0, tracker.runningAgentCount - maxVisibleAgents)
    }

    /// Format status message for an agent
    private func statusMessage(for agent: TrackedAgent) -> String {
        if let status = agent.statusMessage {
            return "\(agent.name): \(status)"
        }
        return "\(agent.name): Processing..."
    }

    var body: some View {
        if hasActivity {
            HStack(spacing: 4) {
                // Show extraction progress if active
                if isExtractionInProgress, let message = extractionMessage {
                    AgentStatusItem(message: message)
                }

                // Show each running agent with its own spinner
                ForEach(visibleAgents) { agent in
                    AgentStatusItem(message: statusMessage(for: agent))
                }

                // Show overflow indicator if more agents are hidden
                if hiddenAgentCount > 0 {
                    Text("+\(hiddenAgentCount) more")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8))
            )
            .overlay {
                // Animated glow border when busy
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .intelligenceStroke(
                        lineWidths: [1.5, 2.5, 3.5],
                        blurs: [4, 8, 14],
                        updateInterval: 0.5,
                        animationDurations: [0.6, 0.8, 1.0]
                    )
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// Individual agent status item with spinner and message
private struct AgentStatusItem: View {
    let message: String

    var body: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
