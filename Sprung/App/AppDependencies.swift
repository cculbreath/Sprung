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
    let knowledgeCardStore: KnowledgeCardStore
    let skillStore: SkillStore
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
    let candidateDossierStore: CandidateDossierStore
    let artifactRecordStore: ArtifactRecordStore
    let onboardingCoordinator: OnboardingInterviewCoordinator
    let reasoningStreamManager: ReasoningStreamState
    let searchOpsCoordinator: DiscoveryCoordinator
    let guidanceStore: InferenceGuidanceStore
    let titleSetStore: TitleSetStore
    let backgroundActivityTracker: BackgroundActivityTracker
    let experienceEntryRefinementService: ExperienceEntryRefinementService
    /// App-managed LinkedIn MCP server (uvx child process) + the LinkedIn
    /// board's one-time risk-consent flag. Started lazily via
    /// `ensureRunning()` on first search; stopped in
    /// `AppDelegate.applicationWillTerminate`.
    let linkedInMCPServer: LinkedInMCPServerService
    // MARK: - UI State
    let dragInfo: DragInfo
    let debugSettingsStore: DebugSettingsStore
    // MARK: - Module Navigation
    let moduleNavigation: ModuleNavigationService
    let focusState: UnifiedJobFocusState
    let windowCoordinator: WindowCoordinator
    let globalKeyboardHandler: GlobalKeyboardHandler
    // MARK: - Core Services
    let appEnvironment: AppEnvironment
    /// The shared SwiftData container backing every store, exposed so the
    /// secondary-window host can inject `.modelContainer(_:)` without a separate
    /// hand-off.
    let modelContainer: ModelContainer
    // MARK: - Init
    init(modelContext: ModelContext) {
        self.modelContainer = modelContext.container
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
        self.candidateDossierStore = CandidateDossierStore(context: modelContext)
        self.artifactRecordStore = ArtifactRecordStore(context: modelContext)
        let guidanceStore = InferenceGuidanceStore(context: modelContext)
        self.guidanceStore = guidanceStore
        self.titleSetStore = TitleSetStore(context: modelContext)
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
            experienceDefaultsStore: experienceDefaultsStore
        )
        self.knowledgeCardStore = KnowledgeCardStore(context: modelContext)
        self.skillStore = SkillStore(context: modelContext)
        self.coverRefStore = CoverRefStore(context: modelContext)
        self.reasoningStreamManager = ReasoningStreamState()
        // Dependent stores
        self.coverLetterStore = CoverLetterStore(
            context: modelContext,
            refStore: coverRefStore,
            applicantProfileStore: applicantProfileStore
        )
        // Created here without its background preprocessor: the preprocessor
        // needs the LLMFacade (and thus enabledLLMStore), which are built below,
        // while DiscoveryCoordinator below needs jobAppStore to already exist —
        // a genuine cycle. The preprocessor is wired in a deferred second phase
        // (see "Job App Preprocessor" below). Safe because JobAppStore holds it
        // as a guarded optional: every preprocessing entry point no-ops with a
        // warning if it has not been set, so jobAppStore is never "half-usable".
        self.jobAppStore = JobAppStore(context: modelContext, resStore: resStore, coverLetterStore: coverLetterStore)
        self.enabledLLMStore = EnabledLLMStore(modelContext: modelContext)
        self.navigationState = NavigationStateService()
        // UI state
        self.dragInfo = DragInfo()

        // Module navigation services
        let focusState = UnifiedJobFocusState()
        self.focusState = focusState
        let windowCoordinator = WindowCoordinator(focusState: focusState)
        self.windowCoordinator = windowCoordinator
        let moduleNavigation = ModuleNavigationService()
        self.moduleNavigation = moduleNavigation
        windowCoordinator.moduleNavigation = moduleNavigation
        self.globalKeyboardHandler = GlobalKeyboardHandler(windowCoordinator: windowCoordinator)
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
        appState.llmService = llmService
        // Create DocumentExtractionService (PDFKit/native text extraction for storage)
        let documentExtractionService = DocumentExtractionService()
        // Register OpenAI backend if API key is configured
        if let openAIKey = APIKeyStore.get(.openAI)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !openAIKey.isEmpty {
            _ = LLMFacadeFactory.registerOpenAI(
                facade: llmFacade,
                apiKey: openAIKey,
                debugEnabled: Logger.isVerboseEnabled
            )
        }

        // Register Anthropic backend if API key is configured
        if let anthropicKey = APIKeyStore.get(.anthropic)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !anthropicKey.isEmpty {
            _ = LLMFacadeFactory.registerAnthropic(
                facade: llmFacade,
                apiKey: anthropicKey,
                debugEnabled: Logger.isDebugEnabled
            )
        }

        let coverLetterService = CoverLetterService(
            llmFacade: llmFacade,
            exportCoordinator: resumeExportCoordinator,
            applicantProfileStore: applicantProfileStore,
            coverRefStore: coverRefStore
        )
        let interviewDataStore = InterviewDataStore()
        let preferences = OnboardingPreferences()
        let onboardingCoordinator = OnboardingInterviewCoordinator(
            llmFacade: llmFacade,
            documentExtractionService: documentExtractionService,
            applicantProfileStore: applicantProfileStore,
            knowledgeCardStore: knowledgeCardStore,
            skillStore: skillStore,
            coverRefStore: coverRefStore,
            experienceDefaultsStore: experienceDefaultsStore,
            guidanceStore: guidanceStore,
            sessionStore: onboardingSessionStore,
            dataStore: interviewDataStore,
            candidateDossierStore: candidateDossierStore,
            preferences: preferences,
            reasoningStreamManager: reasoningStreamManager
        )
        self.onboardingCoordinator = onboardingCoordinator

        // Background Activity Tracker (for monitoring LLM operations)
        let backgroundActivityTracker = BackgroundActivityTracker()
        self.backgroundActivityTracker = backgroundActivityTracker

        // LinkedIn MCP server lifecycle (no child process is spawned here —
        // only ensureRunning() ever starts it).
        self.linkedInMCPServer = LinkedInMCPServerService()

        // Discovery Coordinator
        let searchOpsCoordinator = DiscoveryCoordinator(
            modelContext: modelContext,
            jobAppStore: jobAppStore,
            candidateDossierStore: candidateDossierStore,
            knowledgeCardStore: knowledgeCardStore,
            skillStore: skillStore
        )
        searchOpsCoordinator.configureLLMService(llmFacade: llmFacade)
        self.searchOpsCoordinator = searchOpsCoordinator
        // Surface event-discovery runs in the background-activity UI. Must
        // follow configureLLMService (which creates the agent service) and
        // runs before init returns, so it's in place before the launch-time
        // weekly auto-run's Task gets a chance to start.
        searchOpsCoordinator.setActivityTracker(backgroundActivityTracker)
        // Job Scout: the LinkedIn board participates only through the
        // app-lifetime MCP server (consent flag + lifecycle) — same setter
        // pattern as lead enrichment below. Wired before the auto-run's Task
        // body can execute, like the tracker above.
        searchOpsCoordinator.jobScout.setLinkedInServerService(linkedInMCPServer)

        // Single-entry refinement reuses the SGM generators; built here where every
        // store it needs (and the facade) already exists.
        self.experienceEntryRefinementService = ExperienceEntryRefinementService(
            knowledgeCardStore: knowledgeCardStore,
            skillStore: skillStore,
            applicantProfileStore: applicantProfileStore,
            coverRefStore: coverRefStore,
            candidateDossierStore: candidateDossierStore,
            titleSetStore: titleSetStore,
            llmFacade: llmFacade
        )

        // Job App Preprocessor (background processing for job requirements and
        // card selection). Deferred second phase of jobAppStore wiring: this is
        // the earliest point where every input exists (llmFacade, skillStore,
        // backgroundActivityTracker, knowledgeCardStore). Must run before any
        // jobAppStore preprocessing is triggered — which only happens on user
        // action, well after init returns.
        let jobAppPreprocessor = JobAppPreprocessor(llmFacade: llmFacade)
        jobAppPreprocessor.setSkillStore(skillStore)
        jobAppPreprocessor.setActivityTracker(backgroundActivityTracker)
        jobAppStore.setPreprocessor(jobAppPreprocessor, knowledgeCardStore: knowledgeCardStore)
        // Lead enrichment (the background full-posting fetch for MCP-imported
        // leads) reports per-lead progress to the same tracker. LinkedIn leads
        // enrich through the local MCP server rather than web fetch (authwall).
        jobAppStore.leadEnrichment.setActivityTracker(backgroundActivityTracker)
        jobAppStore.leadEnrichment.setLinkedInServerService(linkedInMCPServer)

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
            modelContainer: modelContext.container,
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
        if let openAIKey = APIKeyStore.get(.openAI)?.trimmingCharacters(in: .whitespacesAndNewlines),
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

        // Re-check Anthropic key and update facade (interview + document analysis)
        if let anthropicKey = APIKeyStore.get(.anthropic)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !anthropicKey.isEmpty {
            _ = LLMFacadeFactory.registerAnthropic(
                facade: appEnvironment.llmFacade,
                apiKey: anthropicKey,
                debugEnabled: Logger.isDebugEnabled
            )
            Logger.info("✅ Anthropic service registered with LLMFacade (new key)", category: .appLifecycle)
        } else {
            Logger.info("⚠️ Anthropic API key not configured", category: .appLifecycle)
        }
    }
}
