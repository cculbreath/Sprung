//
//  AgentsTabContent.swift
//  Sprung
//
//  UI components for the Agents tab showing parallel agent activity,
//  transcripts, and controls for monitoring/killing agents.
//

import SwiftUI

// MARK: - Agents Tab Content

/// Main container for the Agents tab showing agent list and detail view.
struct AgentsTabContent: View {
    @Bindable var tracker: AgentActivityTracker

    var body: some View {
        HSplitView {
            // Agent list
            AgentListView(tracker: tracker)
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)

            // Agent detail/transcript
            if let selectedId = tracker.selectedAgentId,
               let agent = tracker.agents.first(where: { $0.id == selectedId }) {
                AgentTranscriptView(agent: agent, tracker: tracker)
                    .frame(minWidth: 300)
            } else {
                AgentEmptyState()
                    .frame(minWidth: 300)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Agent List View

/// Selectable list of agents with status icons.
struct AgentListView: View {
    @Bindable var tracker: AgentActivityTracker

    private var sortedAgents: [TrackedAgent] {
        // Running first, then pending, then others by start time (newest first)
        tracker.agents.sorted { a, b in
            let priorityOrder: [AgentStatus] = [.running, .pending, .completed, .failed, .killed]
            let aPriority = priorityOrder.firstIndex(of: a.status) ?? 99
            let bPriority = priorityOrder.firstIndex(of: b.status) ?? 99
            if aPriority != bPriority { return aPriority < bPriority }
            return a.startTime > b.startTime
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Agents")
                    .font(.headline)
                Spacer()
                if !tracker.agents.isEmpty {
                    Text("\(tracker.agents.count)")
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if tracker.agents.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "person.2.wave.2")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                    Text("No Agents")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Agents will appear here during knowledge card generation.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                // Agent list
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(sortedAgents) { agent in
                            AgentRowView(
                                agent: agent,
                                isSelected: tracker.selectedAgentId == agent.id,
                                onSelect: { tracker.selectedAgentId = agent.id }
                            )
                        }
                    }
                    .padding(8)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

/// Individual agent row in the list.
struct AgentRowView: View {
    let agent: TrackedAgent
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                // Status indicator
                statusIcon
                    .frame(width: 20)

                // Agent info
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name)
                        .font(.subheadline)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(agent.agentType.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        if let duration = formattedDuration {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(duration)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }

                        if agent.totalTokens > 0 {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(TokenUsageTracker.formatTokenCount(agent.totalTokens))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                // Message count badge
                if !agent.transcript.isEmpty {
                    Text("\(agent.transcript.count)")
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch agent.status {
        case .pending:
            Image(systemName: "clock.fill")
                .foregroundStyle(.gray)
                .font(.caption)
        case .running:
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 16, height: 16)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        case .killed:
            Image(systemName: "stop.circle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
        }
    }

    private var formattedDuration: String? {
        guard let duration = agent.duration else {
            // Still running - calculate current duration
            let elapsed = Date().timeIntervalSince(agent.startTime)
            return formatInterval(elapsed)
        }
        return formatInterval(duration)
    }

    private func formatInterval(_ interval: TimeInterval) -> String {
        if interval < 60 {
            return String(format: "%.0fs", interval)
        }
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Agent Transcript View

/// Detail view showing agent transcript and controls.
struct AgentTranscriptView: View {
    let agent: TrackedAgent
    let tracker: AgentActivityTracker

    var body: some View {
        VStack(spacing: 0) {
            // Header
            agentHeader

            Divider()

            // Transcript
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(agent.transcript) { entry in
                            TranscriptEntryView(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: agent.transcript.count) { _, _ in
                    // Auto-scroll to latest entry
                    if let lastEntry = agent.transcript.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(lastEntry.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Footer with status and kill button
            if agent.status == .running {
                Divider()
                agentFooter
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var agentHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .font(.headline)

                HStack(spacing: 8) {
                    Label(agent.agentType.displayName, systemImage: agent.agentType.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    statusBadge

                    if agent.totalTokens > 0 {
                        HStack(spacing: 4) {
                            Text("In:")
                                .foregroundStyle(.tertiary)
                            Text(TokenUsageTracker.formatTokenCount(agent.inputTokens))
                                .monospacedDigit()
                            Text("Out:")
                                .foregroundStyle(.tertiary)
                            Text(TokenUsageTracker.formatTokenCount(agent.outputTokens))
                                .monospacedDigit()
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if let error = agent.error {
                Button {
                    // Show error details
                } label: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help(error)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var statusBadge: some View {
        let (color, text) = statusInfo
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var statusInfo: (Color, String) {
        switch agent.status {
        case .pending: return (.gray, "Pending")
        case .running: return (.blue, "Running")
        case .completed: return (.green, "Completed")
        case .failed: return (.red, "Failed")
        case .killed: return (.orange, "Killed")
        }
    }

    private var agentFooter: some View {
        HStack {
            // Running indicator with status message
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                Text(agent.statusMessage ?? "Processing...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            // Kill button
            Button(role: .destructive) {
                Task {
                    await tracker.killAgent(agentId: agent.id)
                }
            } label: {
                Label("Stop Agent", systemImage: "stop.fill")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

/// Individual transcript entry view.
struct TranscriptEntryView: View {
    let entry: AgentTranscriptEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack {
                entryIcon
                Text(entryTypeName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(entryColor)
                Spacer()
                Text(formattedTime)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            // Content
            Text(entry.content)
                .font(.caption)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Details (if present)
            if let details = entry.details, !details.isEmpty {
                Text(details)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var entryIcon: some View {
        Image(systemName: iconName)
            .font(.caption)
            .foregroundStyle(entryColor)
    }

    private var iconName: String {
        switch entry.entryType {
        case .system: return "gear"
        case .tool: return "hammer.fill"
        case .assistant: return "brain"
        case .error: return "exclamationmark.triangle.fill"
        case .toolResult: return "checkmark.circle"
        case .turn: return "arrow.trianglehead.2.clockwise.rotate.90"
        }
    }

    private var entryTypeName: String {
        switch entry.entryType {
        case .system: return "System"
        case .tool: return "Tool Call"
        case .assistant: return "Assistant"
        case .error: return "Error"
        case .toolResult: return "Tool Result"
        case .turn: return "Turn"
        }
    }

    private var entryColor: Color {
        switch entry.entryType {
        case .system: return .purple
        case .tool: return .orange
        case .assistant: return .green
        case .error: return .red
        case .toolResult: return .blue
        case .turn: return .cyan
        }
    }

    private var backgroundColor: Color {
        switch entry.entryType {
        case .system: return Color.purple.opacity(0.05)
        case .tool: return Color.orange.opacity(0.05)
        case .assistant: return Color.green.opacity(0.05)
        case .error: return Color.red.opacity(0.05)
        case .toolResult: return Color.blue.opacity(0.05)
        case .turn: return Color.cyan.opacity(0.05)
        }
    }

    private var borderColor: Color {
        entryColor.opacity(0.2)
    }

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: entry.timestamp)
    }
}

// MARK: - Empty State

/// Empty state when no agent is selected.
struct AgentEmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.bubble")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)

            Text("Select an Agent")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Choose an agent from the list to view its transcript and activity.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
