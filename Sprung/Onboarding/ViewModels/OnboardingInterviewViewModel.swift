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
    private let fallbackModelId: String
    private var hasInitialized = false

    init(
        fallbackModelId: String,
        defaultWebSearchAllowed: Bool = true
    ) {
        self.fallbackModelId = fallbackModelId
        self.webSearchAllowed = defaultWebSearchAllowed
    }

    var currentModelId: String {
        selectedModelId.isEmpty ? fallbackModelId : selectedModelId
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
