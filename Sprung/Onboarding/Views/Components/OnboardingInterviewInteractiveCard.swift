import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct OnboardingInterviewInteractiveCard: View {
    @Bindable var service: OnboardingInterviewService
    @Bindable var state: OnboardingInterviewViewModel
    let actions: OnboardingInterviewActionHandler
    let modelStatusDescription: String
    let onOpenSettings: () -> Void

    var body: some View {
        let cornerRadius: CGFloat = 32

        HStack(spacing: 0) {
            OnboardingInterviewToolPane(
                service: service,
                actions: actions
            )
            .frame(minWidth: 340, maxWidth: 420)
            .frame(maxHeight: .infinity, alignment: .topLeading)

            Divider()

            OnboardingInterviewChatPanel(
                service: service,
                state: state,
                actions: actions,
                modelStatusDescription: modelStatusDescription,
                onOpenSettings: onOpenSettings
            )
        }
        .padding(.vertical, 32)
        .padding(.horizontal, 28)
        .frame(minHeight: 540)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
