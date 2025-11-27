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
    let documentExtractionService: DocumentExtractionService
    let onboardingCoordinator: OnboardingInterviewCoordinator
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
        let documentExtractionService = DocumentExtractionService(requestExecutor: requestExecutor)
        self.documentExtractionService = documentExtractionService
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
        var onboardingOpenAIService: OpenAIService?
        if let openAIKey = APIKeyManager.get(.openAI)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !openAIKey.isEmpty {
            let debugEnabled = Logger.isVerboseEnabled
            let responsesConfiguration = URLSessionConfiguration.default
            // Give slow or lossy networks more time to connect and stream response events from OpenAI.
            responsesConfiguration.timeoutIntervalForRequest = 180
            responsesConfiguration.timeoutIntervalForResource = 600
            responsesConfiguration.waitsForConnectivity = true
            let responsesSession = URLSession(configuration: responsesConfiguration)
            let responsesHTTPClient = URLSessionHTTPClientAdapter(urlSession: responsesSession)
            let openAIService = OpenAIServiceFactory.service(
                apiKey: openAIKey,
                httpClient: responsesHTTPClient,
                debugEnabled: debugEnabled
            )
            let openAIClient = OpenAIResponsesClient(service: openAIService)
            llmFacade.registerClient(openAIClient, for: .openAI)
            let conversationService = OpenAIResponsesConversationService(service: openAIService)
            llmFacade.registerConversationService(conversationService, for: .openAI)
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
        let interviewDataStore = InterviewDataStore()
        let checkpoints = Checkpoints()
        let preferences = OnboardingPreferences()
        let onboardingCoordinator = OnboardingInterviewCoordinator(
            openAIService: onboardingOpenAIService,
            documentExtractionService: documentExtractionService,
            applicantProfileStore: applicantProfileStore,
            dataStore: interviewDataStore,
            checkpoints: checkpoints,
            preferences: preferences
        )
        self.onboardingCoordinator = onboardingCoordinator
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
            onboardingCoordinator: onboardingCoordinator,
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
        setupNotificationObservers()
        Logger.debug("✅ AppDependencies: ready", category: .appLifecycle)
    }
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .apiKeysChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleAPIKeysChanged()
            }
        }
    }
    private func handleAPIKeysChanged() {
        Logger.info("🔑 API keys changed - refreshing services", category: .appLifecycle)
        // Re-check OpenAI key
        if let openAIKey = APIKeyManager.get(.openAI)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !openAIKey.isEmpty {
            let debugEnabled = Logger.isVerboseEnabled
            let responsesConfiguration = URLSessionConfiguration.default
            responsesConfiguration.timeoutIntervalForRequest = 180
            responsesConfiguration.timeoutIntervalForResource = 600
            responsesConfiguration.waitsForConnectivity = true
            let responsesSession = URLSession(configuration: responsesConfiguration)
            let responsesHTTPClient = URLSessionHTTPClientAdapter(urlSession: responsesSession)
            let openAIService = OpenAIServiceFactory.service(
                apiKey: openAIKey,
                httpClient: responsesHTTPClient,
                debugEnabled: debugEnabled
            )
            // Update Onboarding Coordinator
            onboardingCoordinator.updateOpenAIService(openAIService)
            Logger.info("✅ Onboarding OpenAIService updated with new key", category: .appLifecycle)
        } else {
            // Key removed or empty
            onboardingCoordinator.updateOpenAIService(nil)
            Logger.info("⚠️ Onboarding OpenAIService cleared (no key)", category: .appLifecycle)
        }
    }
}
