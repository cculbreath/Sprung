import Foundation

/// Wizard steps that correspond to the 4-phase interview structure
enum OnboardingWizardStep: String, CaseIterable, Hashable, Codable {
    case voice      // Phase 1: Voice & Context
    case story      // Phase 2: Career Story
    case evidence   // Phase 3: Evidence Collection
    case strategy   // Phase 4: Strategic Synthesis
}

/// Status of a wizard step
enum OnboardingWizardStepStatus: String, Codable {
    case pending
    case current
    case completed
}

extension OnboardingWizardStep {
    var title: String {
        switch self {
        case .voice:
            return "Voice"
        case .story:
            return "Story"
        case .evidence:
            return "Evidence"
        case .strategy:
            return "Strategy"
        }
    }
}
