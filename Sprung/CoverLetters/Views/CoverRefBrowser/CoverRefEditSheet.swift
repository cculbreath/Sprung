import SwiftUI

/// Edit sheet for CoverRef items (background facts and writing samples).
struct CoverRefEditSheet: View {
    let card: CoverRef?
    var defaultType: CoverRefType = .backgroundFact
    let onSave: (CoverRef) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var content: String = ""
    @State private var type: CoverRefType = .backgroundFact
    @State private var enabledByDefault: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(card == nil ? "Add Reference" : "Edit Reference")
                    .font(.title2.weight(.semibold))
                Spacer()
            }
            .padding(20)

            Divider()

            // Form
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Type picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Type")
                            .font(.subheadline.weight(.medium))
                        Picker("Type", selection: $type) {
                            Text("Background Fact").tag(CoverRefType.backgroundFact)
                            Text("Writing Sample").tag(CoverRefType.writingSample)
                        }
                        .pickerStyle(.segmented)
                    }

                    // Name field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name")
                            .font(.subheadline.weight(.medium))
                        TextField("Enter name", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Content field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Content")
                            .font(.subheadline.weight(.medium))
                        TextEditor(text: $content)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 200)
                            .padding(8)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Enabled by default toggle
                    Toggle("Enabled by default", isOn: $enabledByDefault)
                        .toggleStyle(.checkbox)
                }
                .padding(20)
            }

            Divider()

            // Actions
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button(card == nil ? "Add" : "Save") {
                    saveCard()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || content.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(20)
        }
        .frame(width: 500, height: 550)
        .onAppear {
            if let card {
                name = card.name
                content = card.content
                type = card.type
                enabledByDefault = card.enabledByDefault
            } else {
                type = defaultType
            }
        }
    }

    private func saveCard() {
        if let existingCard = card {
            existingCard.name = name
            existingCard.content = content
            existingCard.type = type
            existingCard.enabledByDefault = enabledByDefault
            onSave(existingCard)
        } else {
            let newCard = CoverRef(
                name: name,
                content: content,
                enabledByDefault: enabledByDefault,
                type: type
            )
            onSave(newCard)
        }
    }
}
