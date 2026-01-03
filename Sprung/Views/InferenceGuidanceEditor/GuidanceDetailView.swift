//
//  GuidanceDetailView.swift
//  Sprung
//
//  Detail view for viewing and editing a single inference guidance record.
//

import SwiftUI

struct GuidanceDetailView: View {
    let guidance: InferenceGuidance
    @Environment(InferenceGuidanceStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var editedPrompt: String = ""
    @State private var isEditing = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    LabeledContent("Node Key", value: guidance.nodeKey)
                    LabeledContent("Display Name", value: guidance.displayName)
                    LabeledContent("Source", value: guidance.source.rawValue.capitalized)
                    LabeledContent("Updated", value: guidance.updatedAt.formatted())
                    LabeledContent("Status", value: guidance.isEnabled ? "Enabled" : "Disabled")
                }

                Section("Prompt") {
                    if isEditing {
                        TextEditor(text: $editedPrompt)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 200)
                    } else {
                        Text(guidance.prompt)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }

                if let attachmentsJSON = guidance.attachmentsJSON {
                    Section("Attachments (JSON)") {
                        ScrollView(.horizontal, showsIndicators: true) {
                            Text(formatJSON(attachmentsJSON))
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 200)
                    }
                }

                Section("Rendered Prompt") {
                    ScrollView {
                        Text(guidance.renderedPrompt())
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 200)
                }
            }
            .navigationTitle(guidance.displayName)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    if isEditing {
                        Button("Save") {
                            guidance.prompt = editedPrompt
                            guidance.source = .user
                            store.update(guidance)
                            isEditing = false
                        }
                    } else {
                        Button("Edit") {
                            editedPrompt = guidance.prompt
                            isEditing = true
                        }
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    private func formatJSON(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: object, options: .prettyPrinted),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return json
        }
        return prettyString
    }
}
