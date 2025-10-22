import SwiftUI
import SwiftyJSON

struct ExtractionReviewSheet: View {
    let extraction: OnboardingPendingExtraction
    let onConfirm: (JSON, String?) -> Void
    let onCancel: () -> Void

    @State private var jsonText: String
    @State private var notes: String = ""
    @State private var errorMessage: String?

    init(
        extraction: OnboardingPendingExtraction,
        onConfirm: @escaping (JSON, String?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.extraction = extraction
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self._jsonText = State(
            initialValue: extraction.rawExtraction.rawString(options: .prettyPrinted)
                ?? extraction.rawExtraction.description
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review Résumé Extraction")
                .font(.title2)
                .bold()

            if !extraction.uncertainties.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Uncertain Fields")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    ForEach(extraction.uncertainties, id: \.self) { item in
                        Label(item, systemImage: "questionmark.circle")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Text("Raw Extraction (editable JSON)")
                .font(.headline)

            TextEditor(text: $jsonText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 240)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2))
                )

            TextField("Notes for the assistant (optional)", text: $notes)
                .textFieldStyle(.roundedBorder)

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                Button("Confirm") {
                    guard let data = jsonText.data(using: .utf8),
                          let json = try? JSON(data: data) else {
                        errorMessage = "JSON is invalid. Please correct it before confirming."
                        return
                    }
                    onConfirm(json, notes.isEmpty ? nil : notes)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 480)
    }
}
