import Foundation
import Observation
@MainActor
@Observable
final class OnboardingInterviewViewModel {
    var selectedModelId: String = ""
    var userInput: String = ""
    var shouldAutoScroll = true
    var webSearchAllowed: Bool
    var showImportError = false
    var importErrorText: String?
    private var hasInitialized = false

    init(defaultWebSearchAllowed: Bool = true) {
        self.webSearchAllowed = defaultWebSearchAllowed
    }

    func configureIfNeeded(
        coordinator: OnboardingInterviewCoordinator?,
        defaultModelId: String,
        defaultWebSearchAllowed: Bool
    ) {
        if !hasInitialized {
            selectedModelId = defaultModelId
            hasInitialized = true
        }
        Task {
            if let coordinator = coordinator, coordinator.ui.isActive {
                await MainActor.run {
                    webSearchAllowed = coordinator.ui.preferences.allowWebSearch
                }
            } else {
                webSearchAllowed = defaultWebSearchAllowed
            }
        }
    }

    func handleDefaultModelChange(newValue: String) {
        selectedModelId = newValue
    }

    func clearImportError() {
        importErrorText = nil
        showImportError = false
    }
}
