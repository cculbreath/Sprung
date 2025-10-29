import Foundation

struct OnboardingPreferences {
    var allowWebSearch: Bool = true
    var allowWritingAnalysis: Bool = false
    var preferredModelId: String?
    var preferredBackend: LLMFacade.Backend = .openAI
}
