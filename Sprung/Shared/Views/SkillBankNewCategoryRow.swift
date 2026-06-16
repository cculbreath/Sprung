import SwiftUI

/// Inline editor row for creating a brand-new category in the Skills Bank browser.
/// The name text is bound to the parent; commit/cancel are callbacks since the
/// follow-on flow (expand + begin adding a skill) lives in the parent.
struct SkillBankNewCategoryRow: View {
    @Binding var newCategoryName: String
    let onCommit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.badge.plus")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            TextField("Category name...", text: $newCategoryName)
                .font(.subheadline.weight(.medium))
                .textFieldStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.accentColor, lineWidth: 1)
                )
                .onSubmit { onCommit() }

            Button {
                onCommit()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
            .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}
