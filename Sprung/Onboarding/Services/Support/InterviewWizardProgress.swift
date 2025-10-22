import Foundation

struct InterviewWizardProgress {
    struct Snapshot {
        let currentStep: OnboardingWizardStep
        let completedSteps: Set<OnboardingWizardStep>
        let statuses: [OnboardingWizardStep: OnboardingWizardStepStatus]
    }

    private var currentStep: OnboardingWizardStep = .introduction
    private var completedSteps: Set<OnboardingWizardStep> = []

    init() {}

    mutating func reset() -> Snapshot {
        currentStep = .introduction
        completedSteps.removeAll()
        return snapshot()
    }

    mutating func transition(to step: OnboardingWizardStep) -> Snapshot {
        currentStep = step
        for prior in OnboardingWizardStep.allCases where prior.rawValue < step.rawValue {
            completedSteps.insert(prior)
        }
        return snapshot()
    }

    mutating func markCompleted(_ step: OnboardingWizardStep) -> Snapshot {
        completedSteps.insert(step)
        return snapshot()
    }

    mutating func sync(with phase: OnboardingPhase) -> Snapshot {
        transition(to: step(for: phase))
    }

    func step(for phase: OnboardingPhase) -> OnboardingWizardStep {
        switch phase {
        case .resumeIntake: return .resumeIntake
        case .artifactDiscovery: return .artifactDiscovery
        case .writingCorpus: return .writingCorpus
        case .wrapUp: return .wrapUp
        }
    }

    func currentSnapshot() -> Snapshot {
        snapshot()
    }

    private func snapshot() -> Snapshot {
        Snapshot(
            currentStep: currentStep,
            completedSteps: completedSteps,
            statuses: makeStatuses(current: currentStep, completed: completedSteps)
        )
    }

    private func makeStatuses(
        current: OnboardingWizardStep,
        completed: Set<OnboardingWizardStep>
    ) -> [OnboardingWizardStep: OnboardingWizardStepStatus] {
        var statuses: [OnboardingWizardStep: OnboardingWizardStepStatus] = [:]
        for step in OnboardingWizardStep.allCases {
            if step == current {
                statuses[step] = .current
            } else if completed.contains(step) {
                statuses[step] = .completed
            } else {
                statuses[step] = .pending
            }
        }
        return statuses
    }
}
