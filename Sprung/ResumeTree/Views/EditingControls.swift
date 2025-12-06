//  EditingControls.swift
//  Sprung
//
//
import SwiftUI
struct EditingControls: View {
    @Binding var isEditing: Bool
    @Binding var tempName: String
    @Binding var tempValue: String
    let node: TreeNode
    var validationError: String?
    var allowNameEditing: Bool = true
    var saveChanges: () -> Void
    var cancelChanges: () -> Void
    var deleteNode: () -> Void
    var clearValidation: () -> Void
    @State private var isHoveringSave: Bool = false
    @State private var isHoveringCancel: Bool = false
    @State private var isHoveringDelete: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if node.allowsDeletion {
                    Button(action: {
                        isEditing = false
                        deleteNode()
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(isHoveringDelete ? .red : .secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onHover { isHoveringDelete = $0 }
                }
                VStack(alignment: .leading, spacing: 8) {
                    if allowNameEditing {
                        TextField("Name", text: $tempName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                            .onChange(of: tempName) { _, _ in clearValidation() }
                    }
                    Group {
                        valueEditor()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let validationError, !validationError.isEmpty {
                        Text(validationError)
                            .font(.footnote)
                            .foregroundColor(.red)
                    } else if let helper = helperText {
                        Text(helper)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 16) {
                Button(action: saveChanges) {
                    Label("Save", systemImage: "checkmark.circle.fill")
                        .foregroundColor(isHoveringSave ? .green : .secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .onHover { isHoveringSave = $0 }
                Button(action: cancelChanges) {
                    Label("Cancel", systemImage: "xmark.circle.fill")
                        .foregroundColor(isHoveringCancel ? .red : .secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .onHover { isHoveringCancel = $0 }
            }
        }
    }
    private func valueEditor() -> some View {
        let inputKind = node.schemaInputKind ?? node.parent?.schemaInputKind
        let requiresMultilineEditor = shouldUseMultilineEditor(for: inputKind)
        Logger.debug(
            """
            🛠 EditingControls.valueEditor \
            node=\(node.name.isEmpty ? "<unnamed>" : node.name) \
            schemaInputKind=\(inputKind?.rawValue ?? "nil") \
            parentInputKind=\(node.parent?.schemaInputKind?.rawValue ?? "nil") \
            requiresMultiline=\(requiresMultilineEditor) \
            tempValueLength=\(tempValue.count)
            """
        )
        return Group {
            switch inputKind {
            case .textarea, .markdown:
                CustomTextEditor(
                    sourceContent: $tempValue,
                    placeholder: node.schemaPlaceholder,
                    minimumHeight: 120,
                    maximumHeight: nil,
                    onChange: { clearValidation() }
                )
            case .chips:
                ChipsEditor(text: $tempValue, placeholder: node.schemaPlaceholder)
                    .onChange(of: tempValue) { _, _ in clearValidation() }
            case .toggle:
                Toggle("Enabled", isOn: Binding(
                    get: { tempValue.lowercased() == "true" },
                    set: { tempValue = $0 ? "true" : "false" }
                ))
                .toggleStyle(SwitchToggleStyle())
                .onChange(of: tempValue) { _, _ in clearValidation() }
            case .date:
                DatePicker(
                    node.schemaPlaceholder ?? "Select Date",
                    selection: Binding(
                        get: { stringToDate(tempValue) ?? Date() },
                        set: { tempValue = dateToString($0) }
                    ),
                    displayedComponents: .date
                )
                .onChange(of: tempValue) { _, _ in clearValidation() }
            case .number:
                TextField(node.schemaPlaceholder ?? "Value", text: Binding(
                    get: { tempValue },
                    set: { newValue in
                        let filtered = newValue.filter { $0.isNumber || $0 == "." }
                        tempValue = filtered
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: tempValue) { _, _ in clearValidation() }
            case .url, .email, .phone:
                TextField(node.schemaPlaceholder ?? "Value", text: $tempValue)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: tempValue) { _, _ in clearValidation() }
            case .select:
                selectionPicker(options: node.schemaValidationOptions)
                    .onChange(of: tempValue) { _, _ in clearValidation() }
            default:
                if requiresMultilineEditor {
                    CustomTextEditor(
                        sourceContent: $tempValue,
                        placeholder: node.schemaPlaceholder,
                        minimumHeight: 120,
                        maximumHeight: nil,
                        onChange: { clearValidation() }
                    )
                } else {
                    TextField(node.schemaPlaceholder ?? "Value", text: $tempValue)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onChange(of: tempValue) { _, _ in clearValidation() }
                }
            }
        }
    }
    private var helperText: String? {
        if node.schemaRepeatable {
            return "Repeatable field"
        }
        if let placeholder = node.schemaPlaceholder, placeholder.isEmpty == false {
            return placeholder
        }
        if node.schemaRequired {
            return "Required"
        }
        return nil
    }
    private func stringToDate(_ string: String) -> Date? {
        if string.isEmpty { return nil }
        if let iso = ISO8601DateFormatter().date(from: string) {
            return iso
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }
    private func dateToString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
    private func selectionPicker(options: [String]) -> AnyView {
        if options.count <= 3 {
            return AnyView(
                Picker(node.schemaPlaceholder ?? "Value", selection: $tempValue) {
                    ForEach(options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            )
        }
        return AnyView(
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(option) {
                        tempValue = option
                        clearValidation()
                    }
                }
            } label: {
                HStack {
                    Text(tempValue.isEmpty ? (node.schemaPlaceholder ?? "Select") : tempValue)
                        .foregroundColor(tempValue.isEmpty ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(6)
            }
        )
    }
    private func shouldUseMultilineEditor(
        for inputKind: TemplateManifest.Section.FieldDescriptor.InputKind?
    ) -> Bool {
        switch inputKind {
        case .textarea, .markdown:
            return true
        case nil:
            let multilineLengthThreshold = 80
            return tempValue.contains("\n")
                || node.value.contains("\n")
                || tempValue.count > multilineLengthThreshold
                || node.value.count > multilineLengthThreshold
        default:
            return false
        }
    }
}
// MARK: - Supporting Views
private struct ChipsEditor: View {
    @Binding var text: String
    var placeholder: String?
    @State private var chips: [String] = []
    @State private var newChip: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if chips.isEmpty {
                        Text(placeholder ?? "Add items")
                            .foregroundColor(.secondary)
                    }
                    ForEach(chips, id: \.self) { chip in
                        HStack(spacing: 4) {
                            Text(chip)
                            Button(action: { remove(chip) }) {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 12))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(12)
                    }
                }
            }
            HStack {
                TextField("Add item", text: $newChip)
                Button("Add") {
                    addChip()
                }
                .disabled(newChip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear { chips = parse(text: text) }
        .onChange(of: text) { _, newValue in
            let parsed = parse(text: newValue)
            if parsed != chips {
                chips = parsed
            }
        }
        .onChange(of: chips) { _, newValue in
            text = newValue.joined(separator: ", ")
        }
    }
    private func addChip() {
        let trimmed = newChip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        chips.append(trimmed)
        newChip = ""
    }
    private func remove(_ chip: String) {
        chips.removeAll { $0 == chip }
    }
    private func parse(text: String) -> [String] {
        text.split(whereSeparator: { ",;\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
