//
//  BackgroundActivityIndicator.swift
//  Sprung
//
//  Compact pill shown in the main window whenever any background AI
//  operation is running (preprocessing, event discovery, lead enrichment).
//  Hidden entirely when nothing is running. Clicking it reveals the activity
//  detail (operation list + transcript) in an in-window popover.
//

import SwiftUI

struct BackgroundActivityIndicator: View {
    @Environment(BackgroundActivityTracker.self) private var tracker
    @State private var showPopover = false

    var body: some View {
        if tracker.hasRunningOperations {
            Button {
                showPopover.toggle()
            } label: {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("\(tracker.runningCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.25)))
            }
            .buttonStyle(.plain)
            .help(tooltipText)
            .accessibilityLabel("\(tracker.runningCount) background AI operation\(tracker.runningCount == 1 ? "" : "s") running")
            .transition(.opacity)
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                BackgroundActivityContent(tracker: tracker)
                    .frame(width: 720, height: 440)
            }
        }
    }

    private var tooltipText: String {
        let lines = tracker.runningOperations.map { operation in
            "• \(operation.operationType.displayName): \(operation.name)"
        }
        return (["Background AI activity:"] + lines + ["Click to view details"])
            .joined(separator: "\n")
    }
}
