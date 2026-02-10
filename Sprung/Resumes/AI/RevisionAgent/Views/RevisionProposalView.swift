import SwiftUI

/// Displays a structured change proposal from the revision agent for user review.
struct RevisionProposalView: View {
    let proposal: ChangeProposal
    let onAccept: () -> Void
    let onReject: () -> Void
    let onModify: (String) -> Void

    @State private var feedbackText: String = ""
    @State private var showFeedbackField: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Summary
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(.blue)
                Text(proposal.summary)
                    .font(.body)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.blue.opacity(0.06))
            )

            // Changes list
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(proposal.changes.enumerated()), id: \.offset) { _, change in
                    changeRow(change)
                }
            }

            // Feedback field
            if showFeedbackField {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Feedback")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $feedbackText)
                        .font(.body)
                        .frame(minHeight: 60, maxHeight: 120)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.background)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(.quaternary)
                                )
                        )

                    HStack {
                        Spacer()
                        Button("Send Feedback") {
                            onModify(feedbackText)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }

            // Action buttons
            if !showFeedbackField {
                HStack(spacing: 8) {
                    Spacer()

                    Button("Provide Feedback") {
                        showFeedbackField = true
                    }
                    .buttonStyle(.bordered)

                    Button("Reject") {
                        onReject()
                    }
                    .buttonStyle(.bordered)

                    Button("Accept") {
                        onAccept()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        )
    }

    @ViewBuilder
    private func changeRow(_ change: ProposeChangesTool.ChangeDetail) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                changeBadge(change.type)
                Text(change.section)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(change.description)
                .font(.callout)

            if let before = change.beforePreview, !before.isEmpty,
               let after = change.afterPreview, !after.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    previewBlock(label: "Before", text: before, color: .red)
                    previewBlock(label: "After", text: after, color: .green)
                }
            } else if let after = change.afterPreview, !after.isEmpty {
                previewBlock(label: "New", text: after, color: .green)
            } else if let before = change.beforePreview, !before.isEmpty {
                previewBlock(label: "Removed", text: before, color: .red)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary.opacity(0.3))
        )
    }

    @ViewBuilder
    private func changeBadge(_ type: String) -> some View {
        let (label, color): (String, Color) = switch type {
        case "modify": ("Modify", .orange)
        case "add": ("Add", .green)
        case "remove": ("Remove", .red)
        case "reorder": ("Reorder", .blue)
        default: (type.capitalized, .secondary)
        }

        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
            )
    }

    @ViewBuilder
    private func previewBlock(label: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(color)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(color.opacity(0.15))
                )
        )
    }
}
