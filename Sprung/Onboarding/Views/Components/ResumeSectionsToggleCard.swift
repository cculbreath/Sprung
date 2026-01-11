import SwiftUI
struct ResumeSectionsToggleCard: View {
    let request: OnboardingSectionToggleRequest
    let onConfirm: ([String], [CustomFieldDefinition]) -> Void
    let onCancel: () -> Void
    @State private var draft: ExperienceDefaultsDraft
    @State private var customFields: [CustomFieldDefinition] = []
    @State private var showAddCustomField = false

    init(
        request: OnboardingSectionToggleRequest,
        existingDraft: ExperienceDefaultsDraft,
        onConfirm: @escaping ([String], [CustomFieldDefinition]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.request = request
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        var initial = existingDraft
        let proposedKeys = Set(request.proposedSections.compactMap { ExperienceSectionKey.fromOnboardingIdentifier($0) })
        if !proposedKeys.isEmpty {
            initial.setEnabledSections(proposedKeys)
        }
        _draft = State(initialValue: initial)
    }
    private var suggestedSections: [ExperienceSectionKey] {
        let identifiers = request.availableSections
        return identifiers.compactMap { ExperienceSectionKey.fromOnboardingIdentifier($0) }
    }
    private var recommendedSections: Set<ExperienceSectionKey> {
        Set(request.proposedSections.compactMap { ExperienceSectionKey.fromOnboardingIdentifier($0) })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Select Résumé Sections")
                .font(.headline)
            if let rationale = request.rationale, !rationale.isEmpty {
                Text(rationale)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text("Choose the sections that apply to your résumé. You can adjust these later if needed.")
                .font(.callout)
            if !suggestedSections.isEmpty {
                Text("Suggested sections: \(suggestedSections.map { $0.metadata.title }.joined(separator: ", "))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 16) {
                    ResumeSectionToggleGrid(draft: $draft, recommended: recommendedSections)

                    Divider()

                    // Custom Fields Section
                    CustomFieldsSection(
                        customFields: $customFields,
                        showAddCustomField: $showAddCustomField
                    )
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxHeight: 400)
            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Confirm Sections", action: {
                    let enabled = draft.enabledSectionKeys().map(\.rawValue)
                    onConfirm(enabled, customFields)
                })
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

// MARK: - Custom Fields Section

private struct CustomFieldsSection: View {
    @Binding var customFields: [CustomFieldDefinition]
    @Binding var showAddCustomField: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Custom Fields")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Button {
                    showAddCustomField = true
                } label: {
                    Label("Add", systemImage: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.link)
            }

            Text("Define custom fields to generate (e.g., objective statement, target roles)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if customFields.isEmpty {
                Text("No custom fields defined")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(customFields) { field in
                    CustomFieldRow(field: field) {
                        customFields.removeAll { $0.id == field.id }
                    }
                }
            }
        }
        .sheet(isPresented: $showAddCustomField) {
            AddCustomFieldSheet { newField in
                customFields.append(newField)
                showAddCustomField = false
            } onCancel: {
                showAddCustomField = false
            }
        }
    }
}

private struct CustomFieldRow: View {
    let field: CustomFieldDefinition
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(field.key)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Text(field.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(6)
    }
}

private struct AddCustomFieldSheet: View {
    @State private var key: String = "custom."
    @State private var description: String = ""
    let onAdd: (CustomFieldDefinition) -> Void
    let onCancel: () -> Void

    private var isValid: Bool {
        key.hasPrefix("custom.") && key.count > 7 && !description.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Custom Field")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Field Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("custom.objective", text: $key)
                    .textFieldStyle(.roundedBorder)
                Text("Must start with \"custom.\" (e.g., custom.objective, custom.targetRoles)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Description (guides content generation)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $description)
                    .frame(height: 80)
                    .font(.body)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                Text("e.g., \"3-5 sentence summary of candidate's positions, goals and interest in position\"")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Add Field") {
                    let field = CustomFieldDefinition(key: key, description: description)
                    onAdd(field)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
        }
        .padding()
        .frame(width: 400)
    }
}
private struct ResumeSectionToggleGrid: View {
    @Binding var draft: ExperienceDefaultsDraft
    let recommended: Set<ExperienceSectionKey>
    private let columns = [
        GridItem(.flexible(minimum: 140), spacing: 12),
        GridItem(.flexible(minimum: 140), spacing: 12)
    ]
    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
            ForEach(ExperienceSectionKey.allCases) { key in
                Toggle(isOn: key.metadata.toggleBinding(in: $draft)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(key.metadata.title)
                            .font(.subheadline)
                            .fontWeight(recommended.contains(key) ? .semibold : .regular)
                        if let subtitle = key.metadata.subtitle {
                            Text(subtitle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
    }
}
