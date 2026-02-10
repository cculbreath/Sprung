import SwiftUI

/// Toolbar controls for the revision agent session.
struct RevisionToolbar: View {
    let status: RevisionAgentStatus
    let currentAction: String
    let onCancel: () -> Void
    let onAccept: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            statusIndicator

            Text(currentAction)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            if case .completed = status {
                Button("Done") { onAccept() }
                    .buttonStyle(.borderedProminent)
            }

            Button("Cancel") { onCancel() }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch status {
        case .idle:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        case .running:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
        }
    }
}
