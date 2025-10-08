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

    // MARK: - UI State
    let dragInfo: DragInfo
    let debugSettingsStore: DebugSettingsStore

    // MARK: - Singletons (kept for now; refactor in later phases)
    private let appState: AppState
    let llmService: LLMService
    let llmFacade: LLMFacade

    // MARK: - Init
    init(modelContext: ModelContext) {
        let debugSettingsStore = DebugSettingsStore()
        self.debugSettingsStore = debugSettingsStore
        Logger.debug("🏗️ AppDependencies: initializing with shared ModelContext", category: .appLifecycle)

        // Base stores
        self.resStore = ResStore(context: modelContext)
        self.resRefStore = ResRefStore(context: modelContext)
        self.coverRefStore = CoverRefStore(context: modelContext)

        // Dependent stores
        self.coverLetterStore = CoverLetterStore(context: modelContext, refStore: coverRefStore)
        self.jobAppStore = JobAppStore(context: modelContext, resStore: resStore, coverLetterStore: coverLetterStore)
        self.resModelStore = ResModelStore(context: modelContext, resStore: resStore)
        self.enabledLLMStore = EnabledLLMStore(modelContext: modelContext)

        // UI state
        self.dragInfo = DragInfo()

        // Singletons (Phase 6 refactor target)
        self.appState = AppState.shared
        self.appState.debugSettingsStore = debugSettingsStore
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

        // Bootstrap sequence
        DatabaseMigrationHelper.checkAndMigrateIfNeeded(modelContext: modelContext)
        appState.initializeWithModelContext(modelContext, enabledLLMStore: enabledLLMStore)
        appState.llmService = llmService
        llmService.initialize(appState: appState, modelContext: modelContext)
        llmService.reconfigureClient()
        CoverLetterService.shared.configure(llmFacade: llmFacade)

        Logger.debug("✅ AppDependencies: ready", category: .appLifecycle)
    }
}
