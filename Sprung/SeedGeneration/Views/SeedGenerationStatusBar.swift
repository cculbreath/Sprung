//
//  SeedGenerationStatusBar.swift
//  Sprung
//
//  Bottom status bar showing current generation activity.
//

import SwiftUI

/// Full-width status bar at bottom of SGM window
struct SeedGenerationStatusBar: View {
    let tracker: SeedGenerationActivityTracker

    private let maxVisibleItems = 3

    var body: some View {
        HStack(spacing: 8) {
            if tracker.isAnyRunning {
                runningTasksView
            } else if tracker.hasCompletedTasks {
                completedSummaryView
            } else {
                idleView
            }

            Spacer()

            if tracker.isAnyRunning {
                cancelButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var runningTasksView: some View {
        let visible = Array(tracker.runningTasks.prefix(maxVisibleItems))
        let remaining = tracker.runningTasks.count - maxVisibleItems

        ForEach(visible) { task in
            TaskStatusItem(task: task)
        }

        if remaining > 0 {
            Text("+\(remaining) more")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var completedSummaryView: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)

            Text("\(tracker.completedCount) tasks completed")
                .font(.callout)
                .foregroundStyle(.secondary)

            if tracker.failedCount > 0 {
                Text("(\(tracker.failedCount) failed)")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var idleView: some View {
        Text("Ready to generate")
            .font(.callout)
            .foregroundStyle(.tertiary)
    }

    private var cancelButton: some View {
        Button("Cancel All") {
            tracker.cancelAll()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

// MARK: - Task Status Item

private struct TaskStatusItem: View {
    let task: SeedGenerationActivityTracker.TrackedTask

    var body: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)

            Text(task.statusMessage ?? task.displayName)
                .font(.callout)
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }
}
