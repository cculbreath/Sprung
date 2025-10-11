//
//  AppDependencies.swift
//  Sprung
//
//  Lightweight dependency injection container for stable store lifetimes.
//  Ensures stores are created once per scene, not recreated on view updates.
//

import Foundation
import SwiftUI
import SwiftData
import Observation

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
        TemplateSeedMigration.runIfNeeded(
            context: modelContext,
            templateStore: templateStore,
            templateSeedStore: templateSeedStore
        )
        TemplateTextResetMigration.runIfNeeded(templateStore: templateStore)

        // Core export orchestration
        let resumeExportService = ResumeExportService(templateStore: templateStore)
        let resumeExportCoordinator = ResumeExportCoordinator(
            exportService: resumeExportService
        )
        self.resumeExportCoordinator = resumeExportCoordinator

        self.resStore = ResStore(
            context: modelContext,
            exportCoordinator: resumeExportCoordinator,
            templateStore: templateStore,
            templateSeedStore: templateSeedStore
        )
        self.resRefStore = ResRefStore(context: modelContext)
        self.coverRefStore = CoverRefStore(context: modelContext)
        self.reasoningStreamManager = ReasoningStreamManager()

        // Dependent stores
        self.coverLetterStore = CoverLetterStore(context: modelContext, refStore: coverRefStore)
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
        // Phase 6: Introduce facade backed by SwiftOpenAI adapter and temporarily bridge conversation flows
        let client = SwiftOpenAIClient(executor: requestExecutor)
        let llmFacade = LLMFacade(
            client: client,
            llmService: llmService,
            openRouterService: openRouterService,
            enabledLLMStore: enabledLLMStore,
            modelValidationService: appState.modelValidationService
        )

        let coverLetterService = CoverLetterService(
            llmFacade: llmFacade,
            exportCoordinator: resumeExportCoordinator
        )

        let resumeReviseViewModel = ResumeReviseViewModel(
            llmFacade: llmFacade,
            openRouterService: openRouterService,
            reasoningStreamManager: reasoningStreamManager,
            exportCoordinator: resumeExportCoordinator
        )
        self.resumeReviseViewModel = resumeReviseViewModel

        self.appEnvironment = AppEnvironment(
            appState: appState,
            navigationState: navigationState,
            openRouterService: openRouterService,
            coverLetterService: coverLetterService,
            llmFacade: llmFacade,
            debugSettingsStore: debugSettingsStore,
            templateStore: templateStore,
            templateSeedStore: templateSeedStore,
            resumeExportCoordinator: resumeExportCoordinator,
            launchState: .ready
        )

        let migrationCoordinator = DatabaseMigrationCoordinator(
            appState: appState,
            openRouterService: openRouterService,
            enabledLLMStore: enabledLLMStore,
            modelValidationService: modelValidationService
        )
        migrationCoordinator.performStartupMigrations(modelContext: modelContext)

        llmService.initialize(
            appState: appState,
            modelContext: modelContext,
            enabledLLMStore: enabledLLMStore,
            openRouterService: openRouterService
        )
        llmService.reconfigureClient()

        Logger.debug("✅ AppDependencies: ready", category: .appLifecycle)
    }
}
