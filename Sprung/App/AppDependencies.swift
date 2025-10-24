//
//  AppDependencies.swift
//  Sprung
//
//  Lightweight dependency injection container for stable store lifetimes.
//  Ensures stores are created once per scene, not recreated on view updates.
//

import Foundation
import Observation
import SwiftData
import SwiftOpenAI
import SwiftUI

@Observable
@MainActor
final class AppDependencies {
    // MARK: - Stores
    let resStore: ResStore
    let resRefStore: ResRefStore
    let coverRefStore: CoverRefStore
    let coverLetterStore: CoverLetterStore
    let jobAppStore: JobAppStore
    let enabledLLMStore: EnabledLLMStore
    let navigationState: NavigationStateService
    let resumeExportCoordinator: ResumeExportCoordinator
    let templateStore: TemplateStore
    let templateSeedStore: TemplateSeedStore
    let experienceDefaultsStore: ExperienceDefaultsStore
    let careerKeywordStore: CareerKeywordStore
    let applicantProfileStore: ApplicantProfileStore
    let onboardingArtifactStore: OnboardingArtifactStore
    let onboardingInterviewService: OnboardingInterviewService
    let llmService: LLMService
    let reasoningStreamManager: ReasoningStreamManager
    let resumeReviseViewModel: ResumeReviseViewModel

    // MARK: - UI State
    let dragInfo: DragInfo
    let debugSettingsStore: DebugSettingsStore

    // MARK: - Core Services
    let appEnvironment: AppEnvironment

    // MARK: - Init
    init(modelContext: ModelContext) {
        let debugSettingsStore = DebugSettingsStore()
        self.debugSettingsStore = debugSettingsStore
        Logger.debug("🏗️ AppDependencies: initializing with shared ModelContext", category: .appLifecycle)

        // Base stores
        let templateStore = TemplateStore(context: modelContext)
        self.templateStore = templateStore
        let templateSeedStore = TemplateSeedStore(context: modelContext)
        self.templateSeedStore = templateSeedStore
        let experienceDefaultsStore = ExperienceDefaultsStore(context: modelContext)
        self.experienceDefaultsStore = experienceDefaultsStore
        let careerKeywordStore = CareerKeywordStore()
        self.careerKeywordStore = careerKeywordStore

        TemplateDefaultsImporter(
            templateStore: templateStore,
            templateSeedStore: templateSeedStore
        ).installDefaultsIfNeeded()

        let applicantProfileStore = ApplicantProfileStore(context: modelContext)
        self.applicantProfileStore = applicantProfileStore
        let onboardingArtifactStore = OnboardingArtifactStore(context: modelContext)
        self.onboardingArtifactStore = onboardingArtifactStore

        // Core export orchestration
        let resumeExportService = ResumeExportService(
            templateStore: templateStore,
            applicantProfileStore: applicantProfileStore
        )
        let resumeExportCoordinator = ResumeExportCoordinator(
            exportService: resumeExportService
        )
        self.resumeExportCoordinator = resumeExportCoordinator

        self.resStore = ResStore(
            context: modelContext,
            exportCoordinator: resumeExportCoordinator,
            applicantProfileStore: applicantProfileStore,
            templateSeedStore: templateSeedStore,
            experienceDefaultsStore: experienceDefaultsStore
        )
        self.resRefStore = ResRefStore(context: modelContext)
        self.coverRefStore = CoverRefStore(context: modelContext)
        self.reasoningStreamManager = ReasoningStreamManager()

        // Dependent stores
        self.coverLetterStore = CoverLetterStore(
            context: modelContext,
            refStore: coverRefStore,
            applicantProfileStore: applicantProfileStore
        )
        self.jobAppStore = JobAppStore(context: modelContext, resStore: resStore, coverLetterStore: coverLetterStore)
        self.enabledLLMStore = EnabledLLMStore(modelContext: modelContext)
        self.navigationState = NavigationStateService()

        // UI state
        self.dragInfo = DragInfo()

        // Core services
        let openRouterService = OpenRouterService()
        let modelValidationService = ModelValidationService()

        let appState = AppState(
            openRouterService: openRouterService,
            modelValidationService: modelValidationService
        )
        appState.debugSettingsStore = debugSettingsStore

        let requestExecutor = LLMRequestExecutor()
        let llmService = LLMService(requestExecutor: requestExecutor)
        self.llmService = llmService
        // Bridge SwiftOpenAI responses into the unified LLM facade until AppLLM fully owns conversation flows.
        let client = SwiftOpenAIClient(executor: requestExecutor)
        let llmFacade = LLMFacade(
            client: client,
            llmService: llmService,
            openRouterService: openRouterService,
            enabledLLMStore: enabledLLMStore,
            modelValidationService: appState.modelValidationService
        )

        var openAIConversationService: OpenAIResponsesConversationService?
        var onboardingOpenAIService: OpenAIService?

        if let openAIKey = APIKeyManager.get(.openAI)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !openAIKey.isEmpty {
            let debugEnabled = Logger.isVerboseEnabled
            let openAIService = OpenAIServiceFactory.service(apiKey: openAIKey, debugEnabled: debugEnabled)
            let openAIClient = OpenAIResponsesClient(service: openAIService)
            llmFacade.registerClient(openAIClient, for: .openAI)
            let conversationService = OpenAIResponsesConversationService(service: openAIService)
            llmFacade.registerConversationService(conversationService, for: .openAI)
            openAIConversationService = conversationService
            onboardingOpenAIService = openAIService
            Logger.info("✅ OpenAI backend registered for onboarding conversations", category: .appLifecycle)
        }

        let coverLetterService = CoverLetterService(
            llmFacade: llmFacade,
            exportCoordinator: resumeExportCoordinator,
            applicantProfileStore: applicantProfileStore
        )

        let resumeReviseViewModel = ResumeReviseViewModel(
            llmFacade: llmFacade,
            openRouterService: openRouterService,
            reasoningStreamManager: reasoningStreamManager,
            exportCoordinator: resumeExportCoordinator,
            applicantProfileStore: applicantProfileStore
        )
        self.resumeReviseViewModel = resumeReviseViewModel

        let onboardingInterviewService = OnboardingInterviewService(openAIService: onboardingOpenAIService)
        self.onboardingInterviewService = onboardingInterviewService

        self.appEnvironment = AppEnvironment(
            appState: appState,
            navigationState: navigationState,
            openRouterService: openRouterService,
            coverLetterService: coverLetterService,
            llmFacade: llmFacade,
            debugSettingsStore: debugSettingsStore,
            templateStore: templateStore,
            templateSeedStore: templateSeedStore,
            experienceDefaultsStore: experienceDefaultsStore,
            careerKeywordStore: careerKeywordStore,
            resumeExportCoordinator: resumeExportCoordinator,
            applicantProfileStore: applicantProfileStore,
            onboardingInterviewService: onboardingInterviewService,
            launchState: .ready
        )

        let migrationCoordinator = DatabaseMigrationCoordinator(
            appState: appState,
            openRouterService: openRouterService,
            enabledLLMStore: enabledLLMStore,
            modelValidationService: modelValidationService
        )
        migrationCoordinator.performStartupMigrations()

        llmService.initialize(
            appState: appState,
            modelContext: modelContext,
            enabledLLMStore: enabledLLMStore,
            openRouterService: openRouterService
        )
        llmService.reconfigureClient()

        appEnvironment.requiresTemplateSetup = templateStore.templates().isEmpty
        Logger.debug("✅ AppDependencies: ready", category: .appLifecycle)
    }
}
