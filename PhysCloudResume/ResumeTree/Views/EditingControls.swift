
//  EditingControls.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 1/29/25.
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button(action: {
                    isEditing = false
                    deleteNode()
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(isHoveringDelete ? .red : .secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .onHover { isHoveringDelete = $0 }

                VStack(alignment: .leading, spacing: 8) {
                    if allowNameEditing {
                        TextField("Name", text: $tempName)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: tempName) { _, _ in clearValidation() }
                    }

                    valueEditor()

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

    @ViewBuilder
    private func valueEditor() -> some View {
        switch node.schemaInputKind {
        case .textarea, .markdown:
            PlaceholderTextEditor(text: $tempValue, placeholder: node.schemaPlaceholder, onChange: { clearValidation() })
                .frame(minHeight: 120)
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
            .onChange(of: tempValue) { _, _ in clearValidation() }
        case .url, .email, .phone:
            TextField(node.schemaPlaceholder ?? "Value", text: $tempValue)
                .textFieldStyle(.roundedBorder)
                .onChange(of: tempValue) { _, _ in clearValidation() }
        case .select:
            selectionPicker(options: node.schemaValidationOptions)
            .onChange(of: tempValue) { _, _ in clearValidation() }
        default:
            TextField(node.schemaPlaceholder ?? "Value", text: $tempValue)
                .textFieldStyle(.roundedBorder)
                .onChange(of: tempValue) { _, _ in clearValidation() }
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

    @ViewBuilder
    private func selectionPicker(options: [String]) -> some View {
        if options.count <= 3 {
            Picker(node.schemaPlaceholder ?? "Value", selection: $tempValue) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.segmented)
        } else {
            Picker(node.schemaPlaceholder ?? "Value", selection: $tempValue) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .pickerStyle(.menu)
        }
    }
}

// MARK: - Supporting Views

private struct PlaceholderTextEditor: View {
    @Binding var text: String
    var placeholder: String?
    var onChange: (() -> Void)?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if (text.isEmpty) {
                Text(placeholder ?? "Enter value")
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
            }
            TextEditor(text: $text)
                .padding(4)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(6)
                .onChange(of: text) { _, _ in onChange?() }
        }
    }
}

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
