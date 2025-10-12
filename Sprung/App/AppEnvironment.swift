//
//  AppEnvironment.swift
//  Sprung
//
//  Defines the core long-lived services that are injected through the SwiftUI
//  environment. Owned and assembled by AppDependencies to keep construction
//  centralized and explicit.
//

import Observation

@MainActor
@Observable
final class AppEnvironment {
    let appState: AppState
    let navigationState: NavigationStateService
    let openRouterService: OpenRouterService
    let coverLetterService: CoverLetterService
    let llmFacade: LLMFacade
    let debugSettingsStore: DebugSettingsStore
    let templateStore: TemplateStore
    let templateSeedStore: TemplateSeedStore
    let resumeExportCoordinator: ResumeExportCoordinator
    let applicantProfileStore: ApplicantProfileStore
    let onboardingInterviewService: OnboardingInterviewService
    var launchState: LaunchState

    init(
        appState: AppState,
        navigationState: NavigationStateService,
        openRouterService: OpenRouterService,
        coverLetterService: CoverLetterService,
        llmFacade: LLMFacade,
        debugSettingsStore: DebugSettingsStore,
        templateStore: TemplateStore,
        templateSeedStore: TemplateSeedStore,
        resumeExportCoordinator: ResumeExportCoordinator,
        applicantProfileStore: ApplicantProfileStore,
        onboardingInterviewService: OnboardingInterviewService,
        launchState: LaunchState
    ) {
        self.appState = appState
        self.navigationState = navigationState
        self.openRouterService = openRouterService
        self.coverLetterService = coverLetterService
        self.llmFacade = llmFacade
        self.debugSettingsStore = debugSettingsStore
        self.templateStore = templateStore
        self.templateSeedStore = templateSeedStore
        self.resumeExportCoordinator = resumeExportCoordinator
        self.applicantProfileStore = applicantProfileStore
        self.onboardingInterviewService = onboardingInterviewService
        self.launchState = launchState
    }
}

extension AppEnvironment {
    enum LaunchState: Equatable {
        case ready
        case readOnly(message: String)

        var isReadOnly: Bool {
            if case .readOnly = self {
                return true
            }
            return false
        }
    }
}
