//
//  AppDependencies.swift
//  PhysCloudResume
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
    let resModelStore: ResModelStore
    let enabledLLMStore: EnabledLLMStore
    let resumeExportCoordinator: ResumeExportCoordinator
    let templateStore: TemplateStore

    // MARK: - UI State
    let dragInfo: DragInfo
    let debugSettingsStore: DebugSettingsStore

    // MARK: - Core Services
    let appState: AppState
    let openRouterService: OpenRouterService
    let modelValidationService: ModelValidationService
    let coverLetterService: CoverLetterService
    let llmService: LLMService
    let llmFacade: LLMFacade
    let appEnvironment: AppEnvironment

    // MARK: - Init
    init(modelContext: ModelContext) {
        let debugSettingsStore = DebugSettingsStore()
        self.debugSettingsStore = debugSettingsStore
        Logger.debug("🏗️ AppDependencies: initializing with shared ModelContext", category: .appLifecycle)

        // Base stores
        let templateStore = TemplateStore(context: modelContext)
        self.templateStore = templateStore

        // Core export orchestration
        let resumeExportService = ResumeExportService(templateStore: templateStore)
        let resumeExportCoordinator = ResumeExportCoordinator(
            exportService: resumeExportService
        )
        self.resumeExportCoordinator = resumeExportCoordinator

        self.resStore = ResStore(context: modelContext, exportCoordinator: resumeExportCoordinator, templateStore: templateStore)
        self.resRefStore = ResRefStore(context: modelContext)
        self.coverRefStore = CoverRefStore(context: modelContext)

        // Dependent stores
        self.coverLetterStore = CoverLetterStore(context: modelContext, refStore: coverRefStore)
        self.jobAppStore = JobAppStore(context: modelContext, resStore: resStore, coverLetterStore: coverLetterStore)
        self.resModelStore = ResModelStore(context: modelContext, resStore: resStore)
        self.enabledLLMStore = EnabledLLMStore(modelContext: modelContext)

        // UI state
        self.dragInfo = DragInfo()

        // Core services
        let openRouterService = OpenRouterService()
        self.openRouterService = openRouterService

        let modelValidationService = ModelValidationService()
        self.modelValidationService = modelValidationService

        let appState = AppState(
            openRouterService: openRouterService,
            modelValidationService: modelValidationService
        )
        self.appState = appState
        appState.debugSettingsStore = debugSettingsStore

        let requestExecutor = LLMRequestExecutor()
        self.llmService = LLMService(requestExecutor: requestExecutor)
        // Phase 6: Introduce facade backed by SwiftOpenAI adapter and temporarily bridge conversation flows
        let client = SwiftOpenAIClient(executor: requestExecutor)
        self.llmFacade = LLMFacade(
            client: client,
            llmService: llmService,
            appState: appState,
            enabledLLMStore: enabledLLMStore,
            modelValidationService: appState.modelValidationService
        )

        let coverLetterService = CoverLetterService(
            llmFacade: llmFacade,
            exportCoordinator: resumeExportCoordinator
        )
        self.coverLetterService = coverLetterService

        self.appEnvironment = AppEnvironment(
            appState: appState,
            openRouterService: openRouterService,
            coverLetterService: coverLetterService,
            llmService: llmService,
            llmFacade: llmFacade,
            modelValidationService: modelValidationService,
            debugSettingsStore: debugSettingsStore,
            templateStore: templateStore,
            resumeExportCoordinator: resumeExportCoordinator,
            launchState: .ready
        )

        // Bootstrap sequence
        DatabaseMigrationHelper.checkAndMigrateIfNeeded(modelContext: modelContext)
        appState.initializeWithModelContext(modelContext, enabledLLMStore: enabledLLMStore)
        appState.llmService = llmService
        llmService.initialize(appState: appState, modelContext: modelContext)
        llmService.reconfigureClient()

        Logger.debug("✅ AppDependencies: ready", category: .appLifecycle)
    }
}
