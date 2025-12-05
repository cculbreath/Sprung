import Foundation
import Observation
@MainActor
@Observable
final class OnboardingInterviewViewModel {
    var selectedModelId: String = ""
    var userInput: String = ""
    var shouldAutoScroll = true
    var webSearchAllowed: Bool
    var writingAnalysisAllowed: Bool
    var showImportError = false
    var importErrorText: String?
    private let fallbackModelId: String
    private var hasInitialized = false
    init(
        fallbackModelId: String,
        defaultWebSearchAllowed: Bool = true,
        defaultWritingAnalysisAllowed: Bool = true
    ) {
        self.fallbackModelId = fallbackModelId
        self.webSearchAllowed = defaultWebSearchAllowed
        self.writingAnalysisAllowed = defaultWritingAnalysisAllowed
    }
    var currentModelId: String {
        selectedModelId.isEmpty ? fallbackModelId : selectedModelId
    }
    func configureIfNeeded(
        coordinator: OnboardingInterviewCoordinator?,
        defaultModelId: String,
        defaultWebSearchAllowed: Bool,
        defaultWritingAnalysisAllowed: Bool
    ) {
        if !hasInitialized {
            selectedModelId = defaultModelId
            hasInitialized = true
        }
        Task {
            if let coordinator = coordinator, coordinator.ui.isActive {
                await MainActor.run {
                    webSearchAllowed = coordinator.ui.preferences.allowWebSearch
                    writingAnalysisAllowed = coordinator.ui.preferences.allowWritingAnalysis
                }
            } else {
                webSearchAllowed = defaultWebSearchAllowed
                writingAnalysisAllowed = defaultWritingAnalysisAllowed
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
