import AppKit
import SwiftUI
import UniformTypeIdentifiers
struct OnboardingInterviewInteractiveCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var coordinator: OnboardingInterviewCoordinator
    @Bindable var state: OnboardingInterviewViewModel
    let modelStatusDescription: String
    let onOpenSettings: () -> Void
    @State private var isToolPaneOccupied = false
    @State private var animateIn = false
    var body: some View {
        let cornerRadius: CGFloat = 28  // Reduced for more natural appearance
        return HStack(spacing: 0) {
            OnboardingInterviewToolPane(
                coordinator: coordinator,
                isOccupied: $isToolPaneOccupied
            )
            .frame(minWidth: 520, maxWidth: 620)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .opacity(animateIn ? 1 : 0)
            .scaleEffect(animateIn ? 1 : 0.96)
            .offset(x: animateIn ? 0 : -32)
            .blur(radius: animateIn ? 0 : 10)
            .animation(
                .interpolatingSpring(stiffness: 260, damping: 20).delay(0.06),
                value: animateIn
            )

            Divider()
                .opacity(animateIn ? 1 : 0)
                .scaleEffect(x: animateIn ? 1 : 0.5, y: 1, anchor: .center)
                .animation(.easeOut(duration: 0.18).delay(0.12), value: animateIn)

            OnboardingInterviewChatPanel(
                coordinator: coordinator,
                state: state,
                modelStatusDescription: modelStatusDescription,
                onOpenSettings: onOpenSettings
            )
            .opacity(animateIn ? 1 : 0)
            .scaleEffect(animateIn ? 1 : 0.97)
            .offset(x: animateIn ? 0 : 38)
            .blur(radius: animateIn ? 0 : 12)
            .animation(
                .interpolatingSpring(stiffness: 240, damping: 22).delay(0.14),
                value: animateIn
            )
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .frame(minHeight: 560)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.65))
                .shadow(color: Color.black.opacity(0.16), radius: 24, y: 18)
        )
        .opacity(animateIn ? 1 : 0)
        .scaleEffect(animateIn ? 1 : 0.94)
        .rotationEffect(.degrees(animateIn ? 0 : -1.6))
        .animation(
            .interpolatingSpring(stiffness: 250, damping: 18),
            value: animateIn
        )
        .onAppear {
            if reduceMotion {
                animateIn = true
                return
            }
            animateIn = true
        }
        .onDisappear {
            animateIn = false
        }
    }
}
