import SwiftUI
struct OnboardingInterviewStepProgressView: View {
    @Bindable var coordinator: OnboardingInterviewCoordinator
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Note: Wizard step status tracking is handled by WizardProgressTracker
            // This view shows the actual progress from the tracker
            let tracker = coordinator.wizardTracker
            ForEach(OnboardingWizardStep.allCases, id: \.self) { step in
                let status = tracker.stepStatuses[step]
                    ?? (tracker.currentStep == step ? .current
                        : (tracker.completedSteps.contains(step) ? .completed : .pending))
                OnboardingStepProgressItem(title: step.title, status: status)
            }
        }
    }
}
private struct OnboardingStepProgressItem: View {
    let title: String
    let status: OnboardingWizardStepStatus
    @State private var measuredLabelWidth: CGFloat = 0
    @State private var animatedProgress: CGFloat = 0
    private let bubbleSize: CGFloat = 18
    private let capsuleHeight: CGFloat = 30
    private let horizontalPadding: CGFloat = 16
    private let verticalPadding: CGFloat = 8
    private let contentSpacing: CGFloat = 8
    var body: some View {
        let font = status == .current ? Font.headline : Font.subheadline
        let textColor: Color = status == .pending ? .secondary : .primary
        let bubbleColor = indicatorColor(for: status)
        let targetProgress = progress(for: status)
        let textWidth = measuredLabelWidth
        let baseWidth = textWidth + horizontalPadding
        let bubbleContribution = (bubbleSize + contentSpacing) * animatedProgress
        let currentWidth = baseWidth + bubbleContribution
        let spacing = animatedProgress > 0 ? contentSpacing : 0
        ZStack(alignment: .leading) {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
                        .shadow(color: Color.white.opacity(0.4), radius: 1.5, x: 0, y: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 6)
            HStack(spacing: spacing) {
                if animatedProgress > 0 {
                    ZStack {
                        Circle()
                            .fill(bubbleColor.gradient)
                        if status == .completed {
                            Image(systemName: "checkmark")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: bubbleSize, height: bubbleSize)
                    .glassEffect(.regular, in: .capsule)
                    .scaleEffect(animatedProgress, anchor: .center)
                    .opacity(animatedProgress)
                    .shadow(color: bubbleColor.opacity(0.45 * Double(animatedProgress)), radius: 8, x: 0, y: 4)
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.25 * animatedProgress), lineWidth: 0.8)
                    }
                }
                Text(title)
                    .font(font)
                    .foregroundStyle(textColor)
                    .frame(maxWidth: .infinity, alignment: animatedProgress > 0 ? .leading : .center)
            }
            .padding(.horizontal, horizontalPadding / 2)
            .padding(.vertical, verticalPadding / 2)
            .frame(height: capsuleHeight)
        }
        .frame(width: currentWidth, height: capsuleHeight)
        .glassEffect(.regular, in: .capsule)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            StepLabelWidthReader(text: title, font: font, width: $measuredLabelWidth)
        )
        .onAppear {
            animatedProgress = targetProgress
        }
        .onChange(of: status) {
            let newProgress = progress(for: status)
            withAnimation(.bouncy(duration: 0.65, extraBounce: 0.15)) {
                animatedProgress = newProgress
            }
        }
    }
    private func progress(for status: OnboardingWizardStepStatus) -> CGFloat {
        switch status {
        case .pending:
            return 0
        case .current, .completed:
            return 1
        }
    }
    private func indicatorColor(for status: OnboardingWizardStepStatus) -> Color {
        switch status {
        case .pending:
            return Color.blue.opacity(0.45)
        case .current:
            return Color.accentColor
        case .completed:
            return Color.green
        }
    }
}
private struct StepLabelWidthReader: View {
    let text: String
    let font: Font
    @Binding var width: CGFloat
    var body: some View {
        Text(text)
            .font(font)
            .padding(.horizontal, 4)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: StepLabelWidthKey.self, value: proxy.size.width)
                }
            )
            .hidden()
            .onPreferenceChange(StepLabelWidthKey.self) { newValue in
                guard abs(width - newValue) > 0.5 else { return }
                width = newValue
            }
    }
}
private struct StepLabelWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
