import Foundation
import Observation

@MainActor
@Observable
final class OnboardingInterviewWizardManager {
    private(set) var wizardStep: OnboardingWizardStep = .introduction
    private(set) var completedWizardSteps: Set<OnboardingWizardStep> = []
    private(set) var wizardStepStatuses: [OnboardingWizardStep: OnboardingWizardStepStatus] = [:]

    private var wizardProgress = InterviewWizardProgress()

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
        wizardStep = snapshot.currentStep
        completedWizardSteps = snapshot.completedSteps
        wizardStepStatuses = snapshot.statuses
    }
}
