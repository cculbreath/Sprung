import SwiftUI

/// Displays a structured change proposal from the revision agent for user review.
/// Each change can be accepted, rejected, or sent back with feedback individually;
/// the decision controls are freely reversible until the user submits.
struct RevisionProposalView: View {
    let proposal: ChangeProposal
    let onRespond: (ProposalResponse) -> Void

    @State private var kinds: [ItemDecision.Kind]
    @State private var feedbacks: [String]
    @State private var editedTexts: [String]

    init(proposal: ChangeProposal, onRespond: @escaping (ProposalResponse) -> Void) {
        self.proposal = proposal
        self.onRespond = onRespond
        _kinds = State(initialValue: Array(repeating: .accept, count: proposal.changes.count))
        _feedbacks = State(initialValue: Array(repeating: "", count: proposal.changes.count))
        // Pre-fill the inline editor with the proposed "after" text so the user tweaks
        // rather than starts blank (falls back to the "before" text for removals).
        _editedTexts = State(initialValue: proposal.changes.map { $0.afterPreview ?? $0.beforePreview ?? "" })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Summary
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(.blue)
                Text(proposal.summary)
                    .font(.body)
                    .textSelection(.enabled)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.blue.opacity(0.06))
            )

            // Changes list
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(proposal.changes.enumerated()), id: \.offset) { index, change in
                    changeRow(index: index, change: change)
                }
            }

            // Batch action buttons
            HStack(spacing: 8) {
                Button("Reject All") { setAll(.reject) }
                    .buttonStyle(.bordered)
                Button("Accept All") { setAll(.accept) }
                    .buttonStyle(.bordered)

                Spacer()

                Button(submitLabel) { submit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        )
    }

    // MARK: - Change Row

    @ViewBuilder
    private func changeRow(index: Int, change: ProposeChangesTool.ChangeDetail) -> some View {
        let kind = kinds.indices.contains(index) ? kinds[index] : .accept
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                changeBadge(change.type)
                Text(change.section)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                decisionControl(index: index)
            }

            Text(change.description)
                .font(.callout)
                .textSelection(.enabled)

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

            // Inline editor: edit the proposed text directly; applied verbatim (no agent rephrasing).
            if kind == .edit, editedTexts.indices.contains(index) {
                TextField("Edit the new text — applied exactly as written", text: $editedTexts[index], axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(2...12)
                    .font(.callout)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.background)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.indigo.opacity(0.4))
                            )
                    )
            }

            // Inline feedback field for this item (shown only while in feedback mode;
            // the note persists if the user toggles modes, so nothing is lost).
            if kind == .feedback, feedbacks.indices.contains(index) {
                TextField("What should change about this item?", text: $feedbacks[index], axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .font(.callout)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.background)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.blue.opacity(0.4))
                            )
                    )
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(rowTint(for: kind))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(rowStroke(for: kind))
                )
        )
    }

    // MARK: - Per-item Decision Control

    @ViewBuilder
    private func decisionControl(index: Int) -> some View {
        let current = kinds.indices.contains(index) ? kinds[index] : .accept
        HStack(spacing: 4) {
            decisionButton(index: index, kind: .accept, label: "Accept", systemImage: "checkmark", tint: .green, current: current)
            decisionButton(index: index, kind: .edit, label: "Edit", systemImage: "pencil", tint: .indigo, current: current)
            decisionButton(index: index, kind: .feedback, label: "Feedback", systemImage: "text.bubble", tint: .blue, current: current)
            decisionButton(index: index, kind: .reject, label: "Reject", systemImage: "xmark", tint: .red, current: current)
        }
    }

    @ViewBuilder
    private func decisionButton(index: Int, kind: ItemDecision.Kind, label: String, systemImage: String, tint: Color, current: ItemDecision.Kind) -> some View {
        let selected = current == kind
        Button {
            guard kinds.indices.contains(index) else { return }
            kinds[index] = kind
        } label: {
            HStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .semibold))
                Text(label)
                    .font(.caption2.weight(.medium))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(selected ? .white : tint)
            .background(
                Capsule().fill(selected ? tint : tint.opacity(0.10))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(label)
    }

    // MARK: - Submit

    private var canSubmit: Bool {
        // Feedback items need a note; edit items need non-empty replacement text.
        for (i, kind) in kinds.enumerated() {
            switch kind {
            case .feedback:
                let text = feedbacks.indices.contains(i) ? feedbacks[i] : ""
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
            case .edit:
                let text = editedTexts.indices.contains(i) ? editedTexts[i] : ""
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
            case .accept, .reject:
                break
            }
        }
        return true
    }

    private var submitLabel: String {
        let rejects = kinds.filter { $0 == .reject }.count
        let notes = kinds.filter { $0 == .feedback }.count
        if rejects == 0 && notes == 0 { return "Accept All" }
        if kinds.allSatisfy({ $0 == .reject }) { return "Reject All" }
        return "Submit Review"
    }

    private func setAll(_ kind: ItemDecision.Kind) {
        kinds = Array(repeating: kind, count: proposal.changes.count)
    }

    private func submit() {
        if kinds.allSatisfy({ $0 == .accept }) {
            onRespond(.accepted)
            return
        }
        if kinds.allSatisfy({ $0 == .reject }) {
            onRespond(.rejected)
            return
        }
        let items: [ItemDecision] = kinds.enumerated().map { index, kind in
            let note = feedbacks.indices.contains(index) ? feedbacks[index] : ""
            let edited = editedTexts.indices.contains(index) ? editedTexts[index] : ""
            return ItemDecision(
                index: index,
                section: proposal.changes[index].section,
                kind: kind,
                feedback: kind == .feedback ? note : nil,
                editedText: kind == .edit ? edited : nil
            )
        }
        onRespond(.itemized(items))
    }

    // MARK: - Styling helpers

    private func rowTint(for kind: ItemDecision.Kind) -> Color {
        switch kind {
        case .accept: return Color.gray.opacity(0.10)
        case .reject: return Color.red.opacity(0.06)
        case .feedback: return Color.blue.opacity(0.06)
        case .edit: return Color.indigo.opacity(0.06)
        }
    }

    private func rowStroke(for kind: ItemDecision.Kind) -> Color {
        switch kind {
        case .accept: return .clear
        case .reject: return Color.red.opacity(0.25)
        case .feedback: return Color.blue.opacity(0.25)
        case .edit: return Color.indigo.opacity(0.25)
        }
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
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
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
