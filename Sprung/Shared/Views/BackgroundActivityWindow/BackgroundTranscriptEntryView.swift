//
//  TranscriptEntryView.swift
//  Sprung
//
//  Individual transcript entry display.
//  Different styling based on entry type.
//

import SwiftUI

struct BackgroundTranscriptEntryView: View {
    let entry: BackgroundTranscriptEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            entryIcon
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.entryType.displayName)
                        .font(.caption.bold())
                        .foregroundStyle(entryColor)

                    Text(formatTime(entry.timestamp))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }

                Text(entry.content)
                    .font(.callout)
                    .foregroundStyle(contentColor)
                    .textSelection(.enabled)

                if let details = entry.details {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Styling

    @ViewBuilder
    private var entryIcon: some View {
        switch entry.entryType {
        case .system:
            Image(systemName: "gearshape")
                .foregroundStyle(.secondary)
        case .llmRequest:
            Image(systemName: "arrow.up.circle")
                .foregroundStyle(.blue)
        case .llmResponse:
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .phase:
            Image(systemName: "flag")
                .foregroundStyle(.orange)
        }
    }

    private var entryColor: Color {
        switch entry.entryType {
        case .system: return .secondary
        case .llmRequest: return .blue
        case .llmResponse: return .green
        case .error: return .red
        case .phase: return .orange
        }
    }

    private var contentColor: Color {
        switch entry.entryType {
        case .error: return .red
        default: return .primary
        }
    }

    private var backgroundColor: Color {
        switch entry.entryType {
        case .error: return Color.red.opacity(0.08)
        case .phase: return Color.orange.opacity(0.08)
        default: return Color.clear
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

// MARK: - Entry Type Extension

extension BackgroundTranscriptEntry.EntryType {
    var displayName: String {
        switch self {
        case .system: return "System"
        case .llmRequest: return "Request"
        case .llmResponse: return "Response"
        case .error: return "Error"
        case .phase: return "Phase"
        }
    }
}
