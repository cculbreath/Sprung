//
//  WizardProgressTracker.swift
//  Sprung
//
//  Tracks wizard step progression for the onboarding interview UI.
//  Maps interview phases and objectives to visual wizard steps.
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
    func updateWaitingState(_ waiting: InterviewSession.Waiting?) {
        switch waiting {
        case .selection, .validation, .upload:
            stepStatuses[currentStep] = .current
        case .none:
            stepStatuses[currentStep] = nil
        }
    }

    /// Synchronizes wizard progress from an interview session.
    func syncProgress(from session: InterviewSession) {
        completedSteps.removeAll()
        stepStatuses.removeAll()

        let objectives = session.objectivesDone
        var newCurrentStep: OnboardingWizardStep = .resumeIntake

        // Determine completed steps based on objectives
        if objectives.contains("applicant_profile") {
            completedSteps.insert(.resumeIntake)
        }

        if objectives.contains("skeleton_timeline") {
            newCurrentStep = .artifactDiscovery
        }

        // Map phases to wizard steps
        switch session.phase {
        case .phase1CoreFacts:
            if !objectives.contains("skeleton_timeline") {
                newCurrentStep = .resumeIntake
            }

        case .phase2DeepDive:
            completedSteps.insert(.resumeIntake)
            if objectives.contains("skeleton_timeline") {
                completedSteps.insert(.artifactDiscovery)
            }
            newCurrentStep = .artifactDiscovery

        case .phase3WritingCorpus:
            completedSteps.insert(.resumeIntake)
            completedSteps.insert(.artifactDiscovery)
            newCurrentStep = .writingCorpus

        case .complete:
            completedSteps.insert(.resumeIntake)
            completedSteps.insert(.artifactDiscovery)
            completedSteps.insert(.writingCorpus)
            newCurrentStep = .wrapUp
        }

        // Update step statuses
        for step in completedSteps {
            stepStatuses[step] = .completed
        }

        currentStep = newCurrentStep
        stepStatuses[newCurrentStep] = .current

        Logger.debug("[WizardStep] Synced from session: \(newCurrentStep.rawValue)", category: .ai)
    }

    /// Resets wizard progress to initial state.
    func reset() {
        currentStep = .introduction
        completedSteps.removeAll()
        stepStatuses.removeAll()
        Logger.debug("[WizardStep] Reset to introduction", category: .ai)
    }
}
