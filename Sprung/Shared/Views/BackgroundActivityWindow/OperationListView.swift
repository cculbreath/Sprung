//
//  OperationListView.swift
//  Sprung
//
//  Left pane showing list of tracked operations.
//  Running operations appear first, then by time.
//

import SwiftUI

struct OperationListView: View {
    @Bindable var tracker: BackgroundActivityTracker

    private var sortedOperations: [TrackedOperation] {
        // Running first, then by start time (newest first)
        tracker.operations.sorted { lhs, rhs in
            if lhs.status == .running && rhs.status != .running { return true }
            if rhs.status == .running && lhs.status != .running { return false }
            return lhs.startTime > rhs.startTime
        }
    }

    private var hasCompletedOrFailed: Bool {
        tracker.operations.contains { $0.status == .completed || $0.status == .failed }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Activity")
                    .font(.headline)

                if tracker.hasRunningOperations {
                    Text("\(tracker.runningCount)")
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())
                }

                Spacer()

                if hasCompletedOrFailed {
                    Button("Clear") {
                        tracker.clearCompleted()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // Operation list
            if sortedOperations.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(sortedOperations) { op in
                            OperationRowView(
                                operation: op,
                                isSelected: tracker.selectedOperationId == op.id,
                                onSelect: { tracker.selectedOperationId = op.id }
                            )
                        }
                    }
                    .padding(8)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No Activity")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Background operations will appear here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}
