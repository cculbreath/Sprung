import Foundation

@MainActor
final class OnboardingInterviewWizardManager {
    // Callback to update service's observable properties
    private let onStateChanged: (WizardState) -> Void

    private var wizardProgress = InterviewWizardProgress()

    struct WizardState {
        var wizardStep: OnboardingWizardStep
        var completedWizardSteps: Set<OnboardingWizardStep>
        var wizardStepStatuses: [OnboardingWizardStep: OnboardingWizardStepStatus]
    }

    init(onStateChanged: @escaping (WizardState) -> Void) {
        self.onStateChanged = onStateChanged
    }

    func reset() {
        applySnapshot(wizardProgress.reset())
    }

    func markCompleted(_ step: OnboardingWizardStep) {
        applySnapshot(wizardProgress.markCompleted(step))
    }

    func transition(to step: OnboardingWizardStep) {
        applySnapshot(wizardProgress.transition(to: step))
    }

    func sync(with phase: OnboardingPhase) {
        applySnapshot(wizardProgress.sync(with: phase))
    }

    func currentSnapshot() {
        applySnapshot(wizardProgress.currentSnapshot())
    }

    private func applySnapshot(_ snapshot: InterviewWizardProgress.Snapshot) {
        onStateChanged(WizardState(
            wizardStep: snapshot.currentStep,
            completedWizardSteps: snapshot.completedSteps,
            wizardStepStatuses: snapshot.statuses
        ))
    }
}
