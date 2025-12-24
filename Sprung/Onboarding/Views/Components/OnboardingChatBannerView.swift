import SwiftUI

/// Banner shown at the top of the chat panel for model availability warnings
struct OnboardingChatBannerView: View {
    let text: String
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange)
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            Spacer()
            Button("Change in Settings…") {
                onOpenSettings()
            }
            .buttonStyle(.link)
            Button(action: {
                onDismiss()
            }, label: {
                Image(systemName: "xmark")
                    .imageScale(.small)
            })
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
    }
}
