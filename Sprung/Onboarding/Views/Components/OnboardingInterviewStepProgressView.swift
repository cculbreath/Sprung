import SwiftUI

struct OnboardingInterviewStepProgressView: View {
    @Bindable var service: OnboardingInterviewService

    var body: some View {
        HStack(alignment: .center, spacing: 32) {
            ForEach(OnboardingWizardStep.allCases) { step in
                let status = service.wizardStepStatuses[step] ?? .pending
                HStack(spacing: 8) {
                    Image(systemName: progressIcon(for: status))
                        .foregroundStyle(progressColor(for: status))
                        .font(.title3)
                    Text(step.title)
                        .font(status == .current ? .headline : .subheadline)
                        .foregroundStyle(status == .pending ? Color.secondary : Color.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func progressIcon(for status: OnboardingWizardStepStatus) -> String {
        switch status {
        case .pending: return "circle"
        case .current: return "circle.inset.filled"
        case .completed: return "checkmark.circle.fill"
        }
    }

    private func progressColor(for status: OnboardingWizardStepStatus) -> Color {
        switch status {
        case .pending: return Color.secondary
        case .current: return Color.accentColor
        case .completed: return Color.green
        }
    }
}
