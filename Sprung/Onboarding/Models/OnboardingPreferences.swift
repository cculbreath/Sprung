import Foundation
struct OnboardingPreferences {
    var allowWebSearch: Bool = true
    var preferredModelId: String?
    var preferredBackend: LLMFacade.Backend = .openAI
}
