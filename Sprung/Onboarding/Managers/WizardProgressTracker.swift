//
//  WizardProgressTracker.swift
//  Sprung
//
//  Tracks wizard step progression for the onboarding interview UI.
//

import Foundation
import Observation

@MainActor
@Observable
final class WizardProgressTracker {
    // MARK: - Observable State

    private(set) var currentStep: OnboardingWizardStep = .introduction
    private(set) var completedSteps: Set<OnboardingWizardStep> = []
    private(set) var stepStatuses: [OnboardingWizardStep: OnboardingWizardStepStatus] = [:]

    // MARK: - Public API

    /// Sets the current wizard step and updates statuses accordingly.
    func setStep(_ step: OnboardingWizardStep) {
        let previousStep = currentStep
        currentStep = step
        stepStatuses[step] = .current

        if previousStep != step {
            stepStatuses[previousStep] = .completed
        }

        if step != .introduction {
            completedSteps.insert(step)
        }

        Logger.debug("[WizardStep] Set to \(step.rawValue)", category: .ai)
    }

    /// Updates the waiting state indicator for the current step.
    func updateWaitingState(_ waiting: String?) {
        switch waiting {
        case "selection", "validation", "upload":
            stepStatuses[currentStep] = .current
        case .none:
            stepStatuses[currentStep] = nil
        default:
            // Other waiting states don't affect step status
            break
        }
    }

    /// Resets wizard progress to initial state.
    func reset() {
        currentStep = .introduction
        completedSteps.removeAll()
        stepStatuses.removeAll()
        Logger.debug("[WizardStep] Reset to introduction", category: .ai)
    }
}