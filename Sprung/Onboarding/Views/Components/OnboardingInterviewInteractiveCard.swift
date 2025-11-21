import AppKit
import SwiftUI
import UniformTypeIdentifiers
struct OnboardingInterviewInteractiveCard: View {
    @Bindable var coordinator: OnboardingInterviewCoordinator
    @Bindable var state: OnboardingInterviewViewModel
    let modelStatusDescription: String
    let onOpenSettings: () -> Void
    @State private var isToolPaneOccupied = false
    var body: some View {
        let cornerRadius: CGFloat = 28  // Reduced for more natural appearance
        return HStack(spacing: 0) {
            OnboardingInterviewToolPane(
                coordinator: coordinator,
                isOccupied: $isToolPaneOccupied
            )
            .frame(minWidth: 340, maxWidth: 420)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            Divider()
            OnboardingInterviewChatPanel(
                coordinator: coordinator,
                state: state,
                modelStatusDescription: modelStatusDescription,
                onOpenSettings: onOpenSettings
            )
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 32)
        .frame(minHeight: 560)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.65))
                .shadow(color: Color.black.opacity(0.16), radius: 24, y: 18)
        )
        .padding(.horizontal, 64)
    }
}
