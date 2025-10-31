import SwiftUI

struct ExtractionStatusCard: View {
    let extraction: OnboardingPendingExtraction

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)

            VStack(alignment: .leading, spacing: 8) {
                Text(extraction.title)
                    .font(.headline)
                Text(extraction.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if !extraction.progressItems.isEmpty {
                    ExtractionProgressChecklistView(items: extraction.progressItems)
                        .padding(.top, 4)
                }

                if !extraction.uncertainties.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Things to double-check:")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        ForEach(extraction.uncertainties, id: \.self) { item in
                            Text("• \(item)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .underPageBackgroundColor))
        )
    }
}
