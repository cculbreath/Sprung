import SwiftUI

/// View that displays the knowledge card collection plan as a todo list.
/// Shows the current item being worked on with a "Done with this card" button.
/// Gates completion until all pending artifacts are processed.
struct KnowledgeCardCollectionView: View {
    let coordinator: OnboardingInterviewCoordinator
    let onDoneWithCard: (String) -> Void

    @State private var pendingArtifactStatus: String?
    @State private var hasPendingArtifacts = false

    private var planItems: [KnowledgeCardPlanItem] {
        coordinator.ui.knowledgeCardPlan
    }

    private var currentFocus: String? {
        coordinator.ui.knowledgeCardPlanFocus
    }

    private var message: String? {
        coordinator.ui.knowledgeCardPlanMessage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerSection

            if planItems.isEmpty {
                emptyState
            } else {
                planListSection
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
        .task(id: currentFocus) {
            await updatePendingStatus()
        }
        .task {
            // Periodically check for pending artifact updates
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await updatePendingStatus()
            }
        }
    }

    private func updatePendingStatus() async {
        hasPendingArtifacts = await coordinator.hasPendingArtifactsForCurrentItem()
        pendingArtifactStatus = await coordinator.getPendingArtifactStatus()
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Knowledge Cards")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                progressSummary
            }

            if let message = message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var progressSummary: some View {
        let completed = planItems.filter { $0.status == .completed }.count
        let total = planItems.count

        return Group {
            if total > 0 {
                Text("\(completed)/\(total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Building Plan",
            systemImage: "list.bullet.clipboard",
            description: Text("The interviewer is analyzing your timeline to plan knowledge card collection...")
        )
        .frame(height: 150)
    }

    private var planListSection: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(planItems) { item in
                    KnowledgeCardPlanRow(
                        item: item,
                        isFocused: item.id == currentFocus,
                        hasPendingArtifacts: item.id == currentFocus && hasPendingArtifacts,
                        pendingStatus: item.id == currentFocus ? pendingArtifactStatus : nil,
                        onDone: { onDoneWithCard(item.id) }
                    )
                }
            }
            .padding(.bottom, 4)
        }
    }
}

private struct KnowledgeCardPlanRow: View {
    let item: KnowledgeCardPlanItem
    let isFocused: Bool
    let hasPendingArtifacts: Bool
    let pendingStatus: String?
    let onDone: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            statusIcon
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(item.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(item.status == .completed ? .secondary : .primary)
                        .lineLimit(1)

                    Spacer()

                    typeTag
                }

                if item.status == .inProgress && isFocused {
                    if hasPendingArtifacts {
                        pendingArtifactView
                    } else {
                        doneButton
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(backgroundColor)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(borderColor, lineWidth: isFocused ? 2 : 1)
        )
    }

    @ViewBuilder
    private var pendingArtifactView: some View {
        HStack(spacing: 6) {
            ProgressView()
                .scaleEffect(0.7)
                .frame(width: 16, height: 16)

            Text(pendingStatus ?? "Processing artifacts...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(6)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .inProgress:
            Image(systemName: "circle.dotted")
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.pulse, options: .repeating)
        case .pending:
            Image(systemName: "circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .skipped:
            Image(systemName: "minus.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var typeTag: some View {
        Text(item.type == .job ? "Job" : "Skill")
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(item.type == .job ? Color.blue.opacity(0.1) : Color.purple.opacity(0.1))
            .foregroundStyle(item.type == .job ? .blue : .purple)
            .cornerRadius(4)
    }

    private var doneButton: some View {
        Button(action: onDone) {
            Label("Done with this card", systemImage: "checkmark")
                .font(.caption.weight(.medium))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(.green)
    }

    private var backgroundColor: Color {
        if isFocused && item.status == .inProgress {
            return Color.accentColor.opacity(0.05)
        } else if item.status == .completed {
            return Color.green.opacity(0.03)
        }
        return Color(nsColor: .controlBackgroundColor)
    }

    private var borderColor: Color {
        if isFocused && item.status == .inProgress {
            return Color.accentColor
        } else if item.status == .completed {
            return Color.green.opacity(0.3)
        }
        return Color(nsColor: .separatorColor)
    }
}
