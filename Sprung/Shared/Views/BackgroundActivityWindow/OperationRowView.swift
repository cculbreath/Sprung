//
//  OperationRowView.swift
//  Sprung
//
//  Individual row for a tracked operation.
//  Shows status, name, phase, and duration.
//

import SwiftUI

struct OperationRowView: View {
    let operation: TrackedOperation
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                statusIcon

                VStack(alignment: .leading, spacing: 2) {
                    Text(operation.name)
                        .font(.subheadline)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(operation.operationType.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        if let phase = operation.currentPhase, operation.status == .running {
                            Text("\u{00B7}")
                                .foregroundStyle(.tertiary)
                            Text(phase)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 4)

                        OperationDurationView(operation: operation)
                    }
                }

                Spacer()

                // Transcript count badge
                if !operation.transcript.isEmpty {
                    Text("\(operation.transcript.count)")
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
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch operation.status {
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
        case .running:
            ProgressView()
                .controlSize(.small)
                .frame(width: 16, height: 16)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .frame(width: 16, height: 16)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .frame(width: 16, height: 16)
        }
    }
}

// MARK: - Duration View

struct OperationDurationView: View {
    let operation: TrackedOperation

    @State private var currentTime = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(formattedDuration)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
            .onReceive(timer) { _ in
                if operation.status == .running {
                    currentTime = Date()
                }
            }
    }

    private var formattedDuration: String {
        let duration: TimeInterval
        if let endTime = operation.endTime {
            duration = endTime.timeIntervalSince(operation.startTime)
        } else if operation.status == .running {
            duration = currentTime.timeIntervalSince(operation.startTime)
        } else {
            return ""
        }

        let seconds = Int(duration) % 60
        let minutes = Int(duration) / 60

        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return "\(seconds)s"
        }
    }
}
