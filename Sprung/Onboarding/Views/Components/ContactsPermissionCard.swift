import SwiftUI

struct ContactsPermissionCard: View {
    let request: OnboardingContactsFetchRequest
    let onAllow: () -> Void
    let onDecline: () -> Void

    @State private var isProcessing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Use macOS Contacts?")
                .font(.headline)

            Text("The assistant can read your macOS Contacts “Me” card to prefill your Applicant Profile.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if !request.requestedFields.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Requested fields")
                        .font(.headline)
                    Text(request.requestedFields.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Not Now", action: onDecline)
                Button {
                    guard !isProcessing else { return }
                    isProcessing = true
                    onAllow()
                } label: {
                    if isProcessing {
                        ProgressView()
                    } else {
                        Text("Allow")
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .underPageBackgroundColor))
        )
    }
}
