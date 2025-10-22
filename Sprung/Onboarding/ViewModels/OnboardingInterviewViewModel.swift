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
        service: OnboardingInterviewService,
        defaultModelId: String,
        defaultWebSearchAllowed: Bool,
        defaultWritingAnalysisAllowed: Bool,
        availableModelIds: [String]
    ) {
        if !hasInitialized {
            syncModelSelection(
                applyingDefaults: true,
                defaultModelId: defaultModelId,
                availableModelIds: availableModelIds
            )
            hasInitialized = true
        }

        if service.isActive {
            webSearchAllowed = service.allowWebSearch
            writingAnalysisAllowed = service.allowWritingAnalysis
        } else {
            webSearchAllowed = defaultWebSearchAllowed
            writingAnalysisAllowed = defaultWritingAnalysisAllowed
        }
    }

    func syncModelSelection(
        applyingDefaults: Bool,
        defaultModelId: String,
        availableModelIds: [String]
    ) {
        if !selectedModelId.isEmpty && !applyingDefaults {
            return
        }

        if availableModelIds.contains(defaultModelId) {
            selectedModelId = defaultModelId
        } else if availableModelIds.contains(fallbackModelId) {
            selectedModelId = fallbackModelId
        } else if let first = availableModelIds.first {
            selectedModelId = first
        } else {
            selectedModelId = fallbackModelId
        }
    }

    func handleDefaultModelChange(
        newValue: String,
        availableModelIds: [String]
    ) {
        syncModelSelection(
            applyingDefaults: true,
            defaultModelId: newValue,
            availableModelIds: availableModelIds
        )
    }

    func syncConsentFromService(_ service: OnboardingInterviewService) {
        guard service.isActive else { return }
        webSearchAllowed = service.allowWebSearch
        writingAnalysisAllowed = service.allowWritingAnalysis
    }

    func registerImportError(_ error: String) {
        importErrorText = error
        showImportError = true
    }

    func clearImportError() {
        importErrorText = nil
        showImportError = false
    }
}
