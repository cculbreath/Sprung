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

    private var hasActivity: Bool {
        tracker.isAnyRunning || isExtractionInProgress
    }

    private var statusMessage: String {
        // Priority: show extraction message if active, otherwise agent status
        if isExtractionInProgress, let message = extractionMessage {
            return message
        }

        // Show first running agent's status
        if let runningAgent = tracker.runningAgents.first {
            let agentName = runningAgent.name
            if let status = runningAgent.statusMessage {
                return "\(agentName): \(status)"
            }
            return "\(agentName): Processing..."
        }

        return "Processing..."
    }

    private var agentSummary: String? {
        let count = tracker.runningAgentCount
        guard count > 1 else { return nil }
        return "+\(count - 1) more"
    }

    var body: some View {
        if hasActivity {
            HStack(spacing: 10) {
                // Animated spinner
                ProgressView()
                    .controlSize(.small)

                // Status message
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                // Additional agents indicator
                if let summary = agentSummary {
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.9))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 0.5)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
