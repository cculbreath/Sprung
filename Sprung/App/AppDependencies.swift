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
    let experienceDefaultsStore: ExperienceDefaultsStore
    let careerKeywordStore: CareerKeywordStore
    let applicantProfileStore: ApplicantProfileStore
    let onboardingSessionStore: OnboardingSessionStore
    let documentExtractionService: DocumentExtractionService
    let onboardingCoordinator: OnboardingInterviewCoordinator
    private let llmService: OpenRouterServiceBackend
    let reasoningStreamManager: ReasoningStreamManager
    let resumeReviseViewModel: ResumeReviseViewModel
    let searchOpsCoordinator: DiscoveryCoordinator
    // MARK: - UI State
    let dragInfo: DragInfo
    let debugSettingsStore: DebugSettingsStore
    // MARK: - Core Services
    let appEnvironment: AppEnvironment
    // MARK: - Init
    init(modelContext: ModelContext) {
        let debugSettingsStore = DebugSettingsStore()
        self.debugSettingsStore = debugSettingsStore
        #if DEBUG
        print("🚀 [STARTUP] Logger minimumLevel: \(Logger.minimumLevel), debugSettingsStore.logLevelSetting: \(debugSettingsStore.logLevelSetting)")
        #endif
        Logger.info("🏗️ AppDependencies: initializing with shared ModelContext", category: .appLifecycle)
        // Base stores
        let templateStore = TemplateStore(context: modelContext)
        self.templateStore = templateStore
        let experienceDefaultsStore = ExperienceDefaultsStore(context: modelContext)
        self.experienceDefaultsStore = experienceDefaultsStore
        let careerKeywordStore = CareerKeywordStore()
        self.careerKeywordStore = careerKeywordStore
        TemplateDefaultsImporter(templateStore: templateStore).installDefaultsIfNeeded()
        let applicantProfileStore = ApplicantProfileStore(context: modelContext)
        self.applicantProfileStore = applicantProfileStore
        self.onboardingSessionStore = OnboardingSessionStore(context: modelContext)
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

        // Create LLMFacade using factory - centralizes construction of internal types
        let (llmFacade, llmService) = LLMFacadeFactory.create(
            openRouterService: openRouterService,
            enabledLLMStore: enabledLLMStore,
            modelValidationService: appState.modelValidationService
        )
        self.llmService = llmService
        appState.llmService = llmService
        // Create DocumentExtractionService with LLMFacade (unified LLM interface)
        let documentExtractionService = DocumentExtractionService(llmFacade: llmFacade)
        self.documentExtractionService = documentExtractionService
        // Register OpenAI backend if API key is configured
        if let openAIKey = APIKeyManager.get(.openAI)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !openAIKey.isEmpty {
            _ = LLMFacadeFactory.registerOpenAI(
                facade: llmFacade,
                apiKey: openAIKey,
                debugEnabled: Logger.isVerboseEnabled
            )
        }

        // Register Gemini backend for document extraction
        // GoogleAIService handles API key internally via APIKeyManager
        _ = LLMFacadeFactory.registerGemini(facade: llmFacade)
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
            applicantProfileStore: applicantProfileStore,
            resRefStore: resRefStore
        )
        self.resumeReviseViewModel = resumeReviseViewModel
        let interviewDataStore = InterviewDataStore()
        let preferences = OnboardingPreferences()
        let onboardingCoordinator = OnboardingInterviewCoordinator(
            llmFacade: llmFacade,
            documentExtractionService: documentExtractionService,
            applicantProfileStore: applicantProfileStore,
            resRefStore: resRefStore,
            coverRefStore: coverRefStore,
            experienceDefaultsStore: experienceDefaultsStore,
            sessionStore: onboardingSessionStore,
            dataStore: interviewDataStore,
            preferences: preferences
        )
        self.onboardingCoordinator = onboardingCoordinator

        // Discovery Coordinator
        let searchOpsCoordinator = DiscoveryCoordinator(
            modelContext: modelContext,
            jobAppStore: jobAppStore,
            interviewDataStore: interviewDataStore
        )
        searchOpsCoordinator.configureLLMService(llmFacade: llmFacade)
        self.searchOpsCoordinator = searchOpsCoordinator

        // Job App Preprocessor (background processing for job requirements and card selection)
        let jobAppPreprocessor = JobAppPreprocessor(llmFacade: llmFacade)
        jobAppStore.setPreprocessor(jobAppPreprocessor, resRefStore: resRefStore)

        self.appEnvironment = AppEnvironment(
            appState: appState,
            navigationState: navigationState,
            openRouterService: openRouterService,
            coverLetterService: coverLetterService,
            llmFacade: llmFacade,
            debugSettingsStore: debugSettingsStore,
            templateStore: templateStore,
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
        // Initialize LLMService after other dependencies are set up
        LLMFacadeFactory.initialize(
            llmService: llmService,
            appState: appState,
            modelContext: modelContext,
            enabledLLMStore: enabledLLMStore,
            openRouterService: openRouterService
        )
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
        // Re-check OpenAI key and update facade
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
            // Register new service with LLMFacade - all components using the facade will get the updated service
            appEnvironment.llmFacade.registerOpenAIService(openAIService)
            Logger.info("✅ OpenAI service registered with LLMFacade (new key)", category: .appLifecycle)
        } else {
            // Key removed or empty - components will fail gracefully when trying to use OpenAI features
            Logger.info("⚠️ OpenAI API key not configured", category: .appLifecycle)
        }
    }
}
