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
        let cornerRadius: CGFloat = 28  // Reduced for more natural appearance

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
        .padding(.vertical, 28)  // Reduced vertical padding
        .padding(.horizontal, 32)  // Slightly reduced horizontal padding
        .frame(minHeight: 540)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.65))
                .shadow(color: Color.black.opacity(0.16), radius: 24, y: 18)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.38), lineWidth: 0.9)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
