//
//  OperationTranscriptView.swift
//  Sprung
//
//  Right pane showing transcript entries for a selected operation.
//  Auto-scrolls to bottom as new entries appear.
//

import SwiftUI

struct OperationTranscriptView: View {
    let operation: TrackedOperation

    var body: some View {
        VStack(spacing: 0) {
            operationHeader

            Divider()

            transcriptList
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var operationHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: operation.operationType.icon)
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(operation.name)
                    .font(.headline)

                HStack(spacing: 8) {
                    statusBadge

                    if let phase = operation.currentPhase {
                        Text(phase)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if operation.inputTokens > 0 || operation.outputTokens > 0 {
                        Text("\(operation.inputTokens) / \(operation.outputTokens) tokens")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            if let duration = operation.duration {
                Text(formatDuration(duration))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var statusBadge: some View {
        HStack(spacing: 4) {
            switch operation.status {
            case .pending:
                Image(systemName: "clock")
                Text("Pending")
            case .running:
                ProgressView()
                    .controlSize(.mini)
                Text("Running")
            case .completed:
                Image(systemName: "checkmark")
                Text("Completed")
            case .failed:
                Image(systemName: "xmark")
                Text("Failed")
            }
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(statusColor.opacity(0.15))
        .foregroundStyle(statusColor)
        .clipShape(Capsule())
    }

    private var statusColor: Color {
        switch operation.status {
        case .pending: return .secondary
        case .running: return .accentColor
        case .completed: return .green
        case .failed: return .red
        }
    }

    // MARK: - Transcript

    private var transcriptList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(operation.transcript) { entry in
                        BackgroundTranscriptEntryView(entry: entry)
                            .id(entry.id)
                    }
                }
                .padding(12)
            }
            .onChange(of: operation.transcript.count) { _, _ in
                if let last = operation.transcript.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(duration) % 60
        let minutes = Int(duration) / 60

        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return "\(seconds)s"
        }
    }
}
