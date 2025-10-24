import SwiftUI
import SwiftyJSON

struct OnboardingValidationReviewCard: View {
    enum Decision: String, CaseIterable, Identifiable {
        case approved
        case modified
        case rejected

        var id: String { rawValue }

        var label: String {
            switch self {
            case .approved: return "Approve"
            case .modified: return "Modify"
            case .rejected: return "Reject"
            }
        }
    }

    let prompt: OnboardingValidationPrompt
    let onSubmit: (_ status: Decision, _ updated: JSON?, _ notes: String?) -> Void
    let onCancel: () -> Void

    @State private var decision: Decision = .approved
    @State private var notes: String = ""
    @State private var updatedPayloadText: String = ""
    @State private var errorMessage: String?

    private var prettyPayload: String {
        if let raw = try? prompt.payload.rawData(options: [.prettyPrinted]),
           let string = String(data: raw, encoding: .utf8) {
            return string
        }
        return prompt.payload.description
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review \(prompt.dataType.capitalized)")
                .font(.headline)

            if let message = prompt.message, !message.isEmpty {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                Text(prettyPayload)
                    .font(.system(.body, design: .monospaced))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
            }
            .frame(minHeight: 160)

            Picker("Decision", selection: $decision) {
                ForEach(Decision.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)

            if decision == .modified {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Provide updated JSON")
                        .font(.headline)
                    Text("Enhanced editors for specific data types will arrive in a later milestone; for now edit the raw JSON directly.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $updatedPayloadText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.3))
                        )
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Notes (optional)")
                    .font(.headline)
                TextEditor(text: $notes)
                    .frame(minHeight: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.3))
                    )
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Submit Decision", action: submit)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .underPageBackgroundColor))
        )
    }

    private func submit() {
        var updatedJSON: JSON?

        if decision == .modified {
            let trimmed = updatedPayloadText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                errorMessage = "Provide updated JSON or choose a different decision."
                return
            }
            let parsed = JSON(parseJSON: trimmed)
            guard parsed != .null else {
                errorMessage = "The modified JSON could not be parsed. Please verify the syntax."
                return
            }
            updatedJSON = parsed
        }

        errorMessage = nil
        onSubmit(decision, updatedJSON, notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes)
        updatedPayloadText = ""
        notes = ""
    }
}
