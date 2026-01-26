//
//  BackgroundActivityContent.swift
//  Sprung
//
//  Main content view for the Background Activity window.
//  HSplitView with operation list on left, transcript on right.
//

import SwiftUI

struct BackgroundActivityContent: View {
    @Bindable var tracker: BackgroundActivityTracker

    var body: some View {
        HSplitView {
            OperationListView(tracker: tracker)
                .frame(minWidth: 200, idealWidth: 260, maxWidth: 320)

            if let selectedId = tracker.selectedOperationId,
               let operation = tracker.getOperation(id: selectedId) {
                OperationTranscriptView(operation: operation)
                    .frame(minWidth: 350)
            } else {
                EmptySelectionView()
                    .frame(minWidth: 350)
            }
        }
        .frame(minWidth: 600, minHeight: 350)
    }
}

// MARK: - Empty State

private struct EmptySelectionView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No Activity Selected")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Select an operation from the list to view its transcript.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
