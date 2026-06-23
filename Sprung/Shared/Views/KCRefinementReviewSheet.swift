import SwiftUI

/// Reviews an AI refinement field-by-field before any change touches the card.
/// Each changed field shows its before/after values with Accept / Reject / Retry.
/// Only accepted fields are written on Apply; everything else keeps its original.
struct KCRefinementReviewSheet: View {
    let cardTitle: String
    /// Re-refine one field with feedback; returns the new value, or nil on failure.
    let onRetry: (KCField, String) async -> KCFieldValue?
    let onApply: ([KCFieldDiff]) -> Void
    let onCancel: () -> Void

    @State private var diffs: [KCFieldDiff]
    @State private var expandedRetry: KCField?
    @State private var feedbackText: [String: String] = [:]
    @State private var retryingField: KCField?
    @State private var retryError: [String: String] = [:]

    init(
        cardTitle: String,
        diffs: [KCFieldDiff],
        onRetry: @escaping (KCField, String) async -> KCFieldValue?,
        onApply: @escaping ([KCFieldDiff]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.cardTitle = cardTitle
        self.onRetry = onRetry
        self.onApply = onApply
        self.onCancel = onCancel
        _diffs = State(initialValue: diffs)
    }

    private var acceptedCount: Int { diffs.filter { $0.decision == .accepted }.count }
    private var rejectedCount: Int { diffs.filter { $0.decision == .rejected }.count }
    private var pendingCount: Int { diffs.filter { $0.decision == .pending }.count }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()

            if diffs.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach($diffs) { $diff in
                            fieldRow($diff)
                        }
                    }
                    .padding(20)
                }
            }

            Divider()
            footerSection
        }
        .frame(width: 760, height: 820)
        .background(Color(nsColor: .windowBackgroundColor))
        .onKeyPress(.escape) {
            onCancel()
            return .handled
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Review Refinements")
                    .font(.title2.weight(.semibold))
                Text(cardTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if !diffs.isEmpty {
                HStack(spacing: 8) {
                    Button("Accept All") { setAll(.accepted) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Reject All") { setAll(.rejected) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No changes")
                .font(.headline)
            Text("The refinement produced no differences from the current card.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Field Row

    private func fieldRow(_ diff: Binding<KCFieldDiff>) -> some View {
        let field = diff.wrappedValue.field
        let isRetrying = retryingField == field

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(diff.wrappedValue.label)
                    .font(.headline)
                Spacer()
                decisionBadge(diff.wrappedValue.decision)
            }

            HStack(alignment: .top, spacing: 12) {
                valueColumn(
                    title: "Before",
                    text: diff.wrappedValue.beforeValue.display,
                    tint: .red,
                    struckThrough: diff.wrappedValue.decision == .accepted
                )
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .padding(.top, 28)
                valueColumn(
                    title: "After",
                    text: diff.wrappedValue.afterValue.display,
                    tint: .green,
                    struckThrough: diff.wrappedValue.decision == .rejected
                )
            }

            actionRow(diff, isRetrying: isRetrying)

            if expandedRetry == field {
                retryInput(diff, isRetrying: isRetrying)
            }

            if let error = retryError[field.id] {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor(diff.wrappedValue.decision), lineWidth: 1)
        )
    }

    private func valueColumn(title: String, text: String, tint: Color, struckThrough: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            ScrollView {
                Text(text)
                    .font(.caption)
                    .strikethrough(struckThrough, color: .secondary)
                    .foregroundStyle(struckThrough ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .frame(height: 150)
            .background(tint.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity)
    }

    private func actionRow(_ diff: Binding<KCFieldDiff>, isRetrying: Bool) -> some View {
        let field = diff.wrappedValue.field
        return HStack(spacing: 8) {
            Button {
                diff.wrappedValue.decision = .accepted
            } label: {
                Label("Accept", systemImage: "checkmark")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.green)
            .disabled(diff.wrappedValue.decision == .accepted)

            Button {
                diff.wrappedValue.decision = .rejected
            } label: {
                Label("Reject", systemImage: "xmark")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.red)
            .disabled(diff.wrappedValue.decision == .rejected)

            Button {
                if expandedRetry == field {
                    expandedRetry = nil
                } else {
                    expandedRetry = field
                }
            } label: {
                Label("Retry", systemImage: "arrow.trianglehead.2.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.blue)
            .disabled(isRetrying)

            if isRetrying {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
            }

            Spacer()
        }
    }

    private func retryInput(_ diff: Binding<KCFieldDiff>, isRetrying: Bool) -> some View {
        let field = diff.wrappedValue.field
        let binding = Binding(
            get: { feedbackText[field.id] ?? "" },
            set: { feedbackText[field.id] = $0 }
        )
        return HStack(spacing: 6) {
            TextField("What should change about \(field.label.lowercased())?", text: binding)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .onSubmit { runRetry(diff) }

            Button("Re-refine") { runRetry(diff) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isRetrying || (feedbackText[field.id]?.trimmingCharacters(in: .whitespaces).isEmpty ?? true))
        }
        .padding(.top, 4)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            if !diffs.isEmpty {
                Text("\(acceptedCount) accepted · \(rejectedCount) rejected · \(pendingCount) pending")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if pendingCount > 0 {
                    Text("Pending fields keep their original value.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Cancel", action: onCancel)
                .buttonStyle(.bordered)

            Button("Apply \(acceptedCount) Change\(acceptedCount == 1 ? "" : "s")") {
                onApply(diffs)
            }
            .buttonStyle(.borderedProminent)
            .disabled(acceptedCount == 0)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(20)
    }

    // MARK: - Helpers

    private func setAll(_ decision: KCFieldDiff.Decision) {
        for index in diffs.indices {
            diffs[index].decision = decision
        }
    }

    private func runRetry(_ diff: Binding<KCFieldDiff>) {
        let field = diff.wrappedValue.field
        let feedback = (feedbackText[field.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !feedback.isEmpty, retryingField == nil else { return }

        retryError[field.id] = nil
        retryingField = field

        Task {
            let result = await onRetry(field, feedback)
            retryingField = nil
            if let result {
                diff.wrappedValue.afterValue = result
                diff.wrappedValue.decision = .pending
                feedbackText[field.id] = ""
                expandedRetry = nil
            } else {
                retryError[field.id] = "Re-refine failed — please try again."
            }
        }
    }

    private func decisionBadge(_ decision: KCFieldDiff.Decision) -> some View {
        let (text, color): (String, Color) = {
            switch decision {
            case .pending: return ("Pending", .secondary)
            case .accepted: return ("Accepted", .green)
            case .rejected: return ("Rejected", .red)
            }
        }()
        return Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func borderColor(_ decision: KCFieldDiff.Decision) -> Color {
        switch decision {
        case .pending: return Color(nsColor: .separatorColor)
        case .accepted: return .green.opacity(0.4)
        case .rejected: return .red.opacity(0.3)
        }
    }
}
