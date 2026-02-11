import SwiftUI

/// Toolbar controls for the revision agent session.
struct RevisionToolbar: View {
    let status: RevisionAgentStatus
    let currentAction: String
    let onCancel: () -> Void
    let onAccept: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Status + action
            HStack(spacing: 8) {
                statusIndicator

                Text(statusLabel)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)

                if case .running = status, !currentAction.isEmpty {
                    Text(currentAction)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer()

            // Actions
            switch status {
            case .completed:
                Button("Done") { onAccept() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)

            case .running:
                Button("Cancel") { onCancel() }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

            case .failed:
                Button("Close") { onAccept() }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

            default:
                Button("Cancel") { onCancel() }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var statusLabel: String {
        switch status {
        case .idle: return "Preparing..."
        case .running: return "Revising"
        case .completed: return "Revision Complete"
        case .failed: return "Revision Failed"
        case .cancelled: return "Cancelled"
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch status {
        case .idle:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
                .font(.caption)
        case .running:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.callout)
        case .cancelled:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }
}
