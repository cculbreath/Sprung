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
    /// Resets wizard progress to initial state.
    func reset() {
        currentStep = .introduction
        completedSteps.removeAll()
        stepStatuses.removeAll()
        Logger.debug("[WizardStep] Reset to introduction", category: .ai)
    }
    /// Synchronizes tracker state with authoritative onboarding state.
    /// - Parameters:
    ///   - currentStep: The current step reported by the coordinator.
    ///   - completedSteps: All steps marked as completed by the coordinator.
    func synchronize(currentStep: OnboardingWizardStep, completedSteps: Set<OnboardingWizardStep>) {
        self.currentStep = currentStep
        self.completedSteps = completedSteps
        stepStatuses.removeAll()
        stepStatuses[currentStep] = .current
        for step in completedSteps where step != currentStep {
            stepStatuses[step] = .completed
        }
        Logger.debug("[WizardStep] Synced from coordinator: \(currentStep.rawValue)", category: .ai)
    }
}
