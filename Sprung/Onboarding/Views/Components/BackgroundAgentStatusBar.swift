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
    let drainGate: DrainGate
    // Keep parameters for API compatibility but rely on agent tracker for display
    let extractionMessage: String?
    let isExtractionInProgress: Bool

    /// Maximum number of items to display before showing "+N more"
    private let maxVisibleItems = 3

    /// Background tools currently executing
    private var backgroundTools: [(callId: String, toolName: String)] {
        drainGate.executingBackgroundTools
    }

    private var hasActivity: Bool {
        tracker.isAnyRunning || !backgroundTools.isEmpty
    }

    /// Running agents to display (limited to maxVisibleItems)
    private var visibleAgents: [TrackedAgent] {
        Array(tracker.runningAgents.prefix(maxVisibleItems))
    }

    /// Number of agents not shown
    private var hiddenAgentCount: Int {
        max(0, tracker.runningAgentCount - maxVisibleItems)
    }

    /// Total count of all activities (agents + tools)
    private var totalActivityCount: Int {
        tracker.runningAgentCount + backgroundTools.count
    }

    /// How many items are hidden (beyond maxVisibleItems)
    private var hiddenItemCount: Int {
        max(0, totalActivityCount - maxVisibleItems)
    }

    /// Format status message for an agent
    private func statusMessage(for agent: TrackedAgent) -> String {
        if let status = agent.statusMessage {
            return "\(agent.name): \(status)"
        }
        return "\(agent.name): Processing..."
    }

    /// Items to show (agents take priority, then tools fill remaining slots)
    private var visibleItems: [StatusBarItem] {
        var items: [StatusBarItem] = []
        let remaining = maxVisibleItems

        // Add agents first (they have richer status info)
        for agent in tracker.runningAgents.prefix(remaining) {
            items.append(.agent(agent))
        }

        // Fill remaining slots with background tools
        let toolSlots = remaining - items.count
        if toolSlots > 0 {
            for tool in backgroundTools.prefix(toolSlots) {
                items.append(.tool(callId: tool.callId, name: tool.toolName))
            }
        }

        return items
    }

    var body: some View {
        HStack(spacing: 4) {
            if hasActivity {
                // Show each running item with its own spinner
                ForEach(visibleItems, id: \.id) { item in
                    switch item {
                    case .agent(let agent):
                        AgentStatusItem(message: statusMessage(for: agent))
                    case .tool(_, let name):
                        ToolStatusItem(toolName: name)
                    }
                }

                // Show overflow indicator if more items are hidden
                if hiddenItemCount > 0 {
                    Text("+\(hiddenItemCount) more")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                }
            } else {
                // Idle state
                Text("Ready")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
            // Animated glow border only when busy
            if hasActivity {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .intelligenceStroke(
                        lineWidths: [1.5, 2.5, 3.5],
                        blurs: [4, 8, 14],
                        updateInterval: 0.5,
                        animationDurations: [0.6, 0.8, 1.0]
                    )
            }
        }
        .animation(.easeInOut(duration: 0.3), value: hasActivity)
    }
}

// MARK: - Status Bar Item

/// Represents an item in the status bar (either an agent or a tool)
private enum StatusBarItem {
    case agent(TrackedAgent)
    case tool(callId: String, name: String)

    var id: String {
        switch self {
        case .agent(let agent):
            return "agent-\(agent.id)"
        case .tool(let callId, _):
            return "tool-\(callId)"
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

/// Individual tool status item with spinner and tool name
private struct ToolStatusItem: View {
    let toolName: String

    /// Format tool name for display (snake_case → readable)
    private var displayName: String {
        toolName
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    var body: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)

            Text(displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.purple.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
