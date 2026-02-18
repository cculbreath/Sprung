//
//  PipelineTrackerView.swift
//  Sprung
//
//
import SwiftUI

// MARK: - Pipeline Tracker

struct PipelineTrackerView: View {
    let currentStatus: Statuses
    let dates: [Statuses: Date]
    let onStatusTap: (Statuses) -> Void

    private let mainPipeline: [Statuses] = [
        .new, .queued, .inProgress, .submitted, .interview, .offer, .accepted
    ]

    private var currentIndex: Int {
        mainPipeline.firstIndex(of: currentStatus) ?? -1
    }

    private static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d/yy"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                ForEach(Array(mainPipeline.enumerated()), id: \.element) { index, status in
                    pipelineNode(status: status, index: index)

                    if index < mainPipeline.count - 1 {
                        connector(afterIndex: index)
                    }
                }
            }

            if currentStatus == .rejected || currentStatus == .withdrawn {
                HStack(spacing: 12) {
                    Spacer()
                    terminalNode(status: .rejected)
                    terminalNode(status: .withdrawn)
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func pipelineNode(status: Statuses, index: Int) -> some View {
        let isPast = currentIndex >= 0 && index < currentIndex
        let isCurrent = status == currentStatus
        let isFuture = !isPast && !isCurrent

        return Button {
            onStatusTap(status)
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(isCurrent ? status.color : isPast ? status.color.opacity(0.3) : Color(nsColor: .separatorColor).opacity(0.3))
                        .frame(width: 28, height: 28)
                    Image(systemName: status.icon)
                        .font(.system(size: 11))
                        .foregroundColor(isCurrent ? .white : isPast ? status.color : Color.secondary.opacity(0.5))
                }
                Text(status.displayName)
                    .font(.system(size: 9, weight: isCurrent ? .semibold : .regular))
                    .foregroundColor(isCurrent ? .primary : isFuture ? Color.secondary.opacity(0.5) : .secondary)
                    .lineLimit(1)
                    .fixedSize()
                if let date = dates[status] {
                    Text(Self.shortDate.string(from: date))
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func connector(afterIndex index: Int) -> some View {
        let isPast = currentIndex >= 0 && index < currentIndex
        return Rectangle()
            .fill(isPast ? Color.secondary.opacity(0.4) : Color(nsColor: .separatorColor).opacity(0.3))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
            .padding(.bottom, dates.isEmpty ? 16 : 28)
    }

    private func terminalNode(status: Statuses) -> some View {
        let isCurrent = status == currentStatus
        return Button {
            onStatusTap(status)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: status.icon)
                    .font(.caption)
                    .foregroundStyle(isCurrent ? status.color : .secondary)
                Text(status.displayName)
                    .font(.caption)
                    .foregroundStyle(isCurrent ? .primary : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isCurrent ? status.color.opacity(0.15) : Color(nsColor: .controlBackgroundColor).opacity(0.3))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isCurrent ? status.color.opacity(0.5) : Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
