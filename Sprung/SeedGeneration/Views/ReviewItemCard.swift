//
//  ReviewItemCard.swift
//  Sprung
//
//  Card for reviewing a single piece of generated content.
//

import SwiftUI

/// Card displaying generated content with approve/reject/edit actions
struct ReviewItemCard: View {
    let item: ReviewItem
    let onApprove: () -> Void
    let onReject: (String?) -> Void
    let onEdit: (String) -> Void

    @State private var isEditing = false
    @State private var editedText = ""
    @State private var showingRejectionSheet = false
    @State private var rejectionComment = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            contentView
            if isEditing {
                editingView
            }
            actionButtons
        }
        .padding()
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(statusBorder)
        .sheet(isPresented: $showingRejectionSheet) {
            rejectionCommentSheet
        }
    }

    // MARK: - Rejection Comment Sheet

    private var rejectionCommentSheet: some View {
        VStack(spacing: 16) {
            Text("Rejection Feedback")
                .font(.headline)

            Text("What should be different? Your feedback will guide regeneration.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextEditor(text: $rejectionComment)
                .font(.body)
                .frame(minHeight: 100)
                .padding(8)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.quaternary, lineWidth: 1)
                )

            HStack {
                Button("Cancel") {
                    showingRejectionSheet = false
                    rejectionComment = ""
                }
                .buttonStyle(.bordered)

                Button("Reject Without Comment") {
                    showingRejectionSheet = false
                    onReject(nil)
                    rejectionComment = ""
                }
                .buttonStyle(.bordered)

                Button("Submit & Regenerate") {
                    showingRejectionSheet = false
                    onReject(rejectionComment.isEmpty ? nil : rejectionComment)
                    rejectionComment = ""
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(rejectionComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label {
                Text(item.task.displayName)
                    .font(.headline)
            } icon: {
                Image(systemName: sectionIcon)
                    .foregroundStyle(sectionColor)
            }

            Spacer()

            if let action = item.userAction {
                actionBadge(for: action)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        switch item.generatedContent.type {
        case .workHighlights(_, let highlights),
             .volunteerDescription(_, _, let highlights),
             .projectDescription(_, _, let highlights, _):
            BulletListView(items: highlights)

        case .educationDescription(_, let description, let courses):
            VStack(alignment: .leading, spacing: 8) {
                Text(description)
                    .font(.body)
                if !courses.isEmpty {
                    Text("Courses: \(courses.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        case .objective(let summary):
            Text(summary)
                .font(.body)

        case .skillGroups(let groups):
            SkillGroupsPreview(groups: groups)

        case .titleSets(let titles):
            TitleSetsPreview(titleSets: titles)

        default:
            Text("Content preview not available")
                .foregroundStyle(.secondary)
                .italic()
        }
    }

    // MARK: - Editing

    private var editingView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Edit Content")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $editedText)
                .font(.body)
                .frame(minHeight: 100)
                .padding(8)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.quaternary, lineWidth: 1)
                )

            HStack {
                Button("Cancel") {
                    isEditing = false
                    editedText = ""
                }
                .buttonStyle(.bordered)

                Button("Save Changes") {
                    onEdit(editedText)
                    isEditing = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Actions

    private var actionButtons: some View {
        HStack(spacing: 12) {
            if item.userAction == nil {
                Button {
                    onApprove()
                } label: {
                    Label("Approve", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button {
                    isEditing = true
                    editedText = extractEditableText()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .buttonStyle(.bordered)

                Button {
                    showingRejectionSheet = true
                } label: {
                    Label("Reject", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
    }

    // MARK: - Helpers

    private var sectionIcon: String {
        switch item.task.section {
        case .work: return "briefcase.fill"
        case .education: return "graduationcap.fill"
        case .volunteer: return "heart.fill"
        case .projects: return "hammer.fill"
        case .skills: return "star.fill"
        case .custom: return "person.fill"
        default: return "doc.fill"
        }
    }

    private var sectionColor: Color {
        switch item.task.section {
        case .work: return .blue
        case .education: return .purple
        case .volunteer: return .pink
        case .projects: return .orange
        case .skills: return .yellow
        case .custom: return .green
        default: return .gray
        }
    }

    private var cardBackground: some ShapeStyle {
        Color(.controlBackgroundColor)
    }

    @ViewBuilder
    private var statusBorder: some View {
        if let action = item.userAction {
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor(for: action), lineWidth: 2)
        } else {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private func borderColor(for action: ReviewItem.UserAction) -> Color {
        switch action {
        case .approved, .edited:
            return .green.opacity(0.5)
        case .rejected, .rejectedWithComment:
            return .red.opacity(0.5)
        }
    }

    private func actionBadge(for action: ReviewItem.UserAction) -> some View {
        let (text, color): (String, Color) = {
            switch action {
            case .approved: return ("Approved", .green)
            case .edited: return ("Edited", .blue)
            case .rejected: return ("Rejected", .red)
            case .rejectedWithComment: return ("Rejected", .red)
            }
        }()

        return Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private func extractEditableText() -> String {
        switch item.generatedContent.type {
        case .workHighlights(_, let highlights):
            return highlights.map { "- \($0)" }.joined(separator: "\n")
        case .objective(let summary):
            return summary
        case .educationDescription(_, let description, _):
            return description
        case .volunteerDescription(_, let summary, _):
            return summary
        default:
            return ""
        }
    }
}

// MARK: - Supporting Views

private struct BulletListView: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("\u{2022}")
                        .foregroundStyle(.secondary)
                    Text(item)
                        .font(.body)
                }
            }
        }
    }
}

private struct SkillGroupsPreview: View {
    let groups: [SkillGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(groups, id: \.name) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    Text(group.keywords.joined(separator: ", "))
                        .font(.callout)
                }
            }
        }
    }
}

private struct TitleSetsPreview: View {
    let titleSets: [TitleSet]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(titleSets) { set in
                HStack {
                    Text(set.titles.joined(separator: " | "))
                        .font(.callout)
                    if set.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                    }
                }
            }
        }
    }
}
