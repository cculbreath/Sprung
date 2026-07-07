//
//  UnifiedAppLayout.swift
//  Sprung
//
//  Top-level layout combining icon bar and module content.
//

import SwiftUI

/// Top-level layout combining icon bar and module content.
///
/// Also the always-alive owner of the app's command surface: the shared
/// `AppSheets` state, the `MenuNotificationHandler` observers, and the headless
/// toolbar-button views live HERE — above the `.id(module)` switch — so menu
/// commands, toolbar items, and the `sprung://capture-job` URL scheme work no
/// matter which module is frontmost. (They were previously registered inside
/// ResumeEditorModuleView and silently died whenever another module was up.)
struct UnifiedAppLayout: View {
    @Environment(ModuleNavigationService.self) private var navigation
    @Environment(WindowCoordinator.self) private var windowCoordinator
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(ReasoningStreamState.self) private var reasoningStreamManager
    @Environment(AppState.self) private var appState
    @Environment(EnabledLLMStore.self) private var enabledLLMStore
    @Environment(JobAppStore.self) private var jobAppStore
    @Environment(CoverLetterStore.self) private var coverLetterStore
    @Environment(NavigationStateService.self) private var navigationState

    @State private var showSetupWizard: Bool = false
    @State private var didPromptTemplateEditor = false
    @State private var sheets = AppSheets()
    @State private var menuHandler = MenuNotificationHandler()
    @AppStorage("hasCompletedSetupWizard") private var hasCompletedSetupWizard = false

    var body: some View {
        HStack(spacing: 0) {
            // Icon bar (always visible)
            IconBarView()

            // Module content
            ModuleContentView(module: navigation.selectedModule, sheets: $sheets)
        }
        .frame(minWidth: 1000, minHeight: 650)
        // Headless toolbar-button views: kept alive at the shell so their
        // notification-driven sheets/alerts present from menu and toolbar
        // commands in every module (single observer per trigger).
        .background {
            VStack(spacing: 0) {
                BestJobButton()
                CoverLetterGenerateButton()
            }
            .frame(width: 0, height: 0)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        // Single presenter for all shared app sheets, and the sole observer of
        // .captureJobFromURL — alive for the lifetime of the main window. Any
        // capture-job URL that arrived before this mounted is buffered by
        // AppDelegate.CaptureURLBuffer and delivered via the ready-signal in onAppear
        // below, so a cold launch via the URL scheme never drops the capture.
        .appSheets(sheets: $sheets)
        // Global reasoning stream overlay (shared across all modules)
        .overlay {
            if reasoningStreamManager.isVisible {
                ReasoningStreamView(
                    isVisible: Binding(
                        get: { reasoningStreamManager.isVisible },
                        set: { reasoningStreamManager.isVisible = $0 }
                    ),
                    reasoningText: Binding(
                        get: { reasoningStreamManager.reasoningText },
                        set: { reasoningStreamManager.reasoningText = $0 }
                    ),
                    isStreaming: Binding(
                        get: { reasoningStreamManager.isStreaming },
                        set: { reasoningStreamManager.isStreaming = $0 }
                    ),
                    errorMessage: Binding(
                        get: { reasoningStreamManager.errorMessage },
                        set: { reasoningStreamManager.errorMessage = $0 }
                    ),
                    modelName: reasoningStreamManager.modelName
                )
                .zIndex(1000)
            }
        }
        // Module navigation keyboard shortcuts
        .moduleNavigationShortcuts()
        // Template setup overlay
        .overlay(alignment: .center) {
            if appEnvironment.requiresTemplateSetup {
                TemplateSetupOverlayUnified()
            }
        }
        // Setup wizard sheet
        .sheet(isPresented: $showSetupWizard) {
            SetupWizardSheetUnified(onComplete: {
                hasCompletedSetupWizard = true
                showSetupWizard = false
            })
        }
        .onAppear {
            @Bindable var navigationState = navigationState
            menuHandler.configure(
                jobAppStore: jobAppStore,
                coverLetterStore: coverLetterStore,
                moduleNavigation: navigation,
                sheets: $sheets,
                selectedTab: $navigationState.selectedTab
            )
            // Ready signal: the .appSheets modifier below (AppSheetsModifier's
            // .onReceive for .captureJobFromURL) mounts as part of this same body
            // evaluation, so this is the deterministic point to drain any capture-job
            // URL that arrived during a cold launch, before this view existed to hear it.
            if let delegate = NSApplication.shared.delegate as? AppDelegate {
                delegate.mainWindowCaptureConsumerDidMount()
            }
            if shouldShowSetupWizard() {
                showSetupWizard = true
            }
            if appEnvironment.requiresTemplateSetup && !didPromptTemplateEditor {
                openTemplateEditor()
                didPromptTemplateEditor = true
            }
        }
        .onChange(of: appEnvironment.requiresTemplateSetup) { _, requiresSetup in
            if requiresSetup {
                openTemplateEditor()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .apiKeysChanged)) { _ in
            if shouldShowSetupWizard() {
                showSetupWizard = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSetupWizard)) { _ in
            showSetupWizard = true
        }
        .onChange(of: enabledLLMStore.enabledModels.count) { _, _ in
            if shouldShowSetupWizard() {
                showSetupWizard = true
            }
        }
    }

    // MARK: - Helpers

    private func shouldShowSetupWizard() -> Bool {
        guard !appEnvironment.launchState.isReadOnly else { return false }

        let hasOpenRouterKey = !(APIKeyStore.get(.openRouter)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasOpenAIKey = !(APIKeyStore.get(.openAI)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasAnthropicKey = !(APIKeyStore.get(.anthropic)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

        // Anthropic is the backbone key (interview, document analysis, resume
        // revision, Discovery agent) — a missing one hard-re-prompts on every
        // launch, exactly like a missing OpenRouter/OpenAI key.
        if !hasOpenRouterKey || !hasOpenAIKey || !hasAnthropicKey {
            return true
        }

        guard !hasCompletedSetupWizard else { return false }

        let hasModels = !enabledLLMStore.enabledModels.isEmpty
        return !hasModels
    }

    private func openTemplateEditor() {
        Task { @MainActor in
            NotificationCenter.default.post(name: .showTemplateEditor, object: nil)
            if let delegate = NSApplication.shared.delegate as? AppDelegate {
                delegate.showTemplateEditorWindow()
            }
        }
    }
}

// MARK: - Template Setup Overlay

private struct TemplateSetupOverlayUnified: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Add a Template to Get Started")
                .font(.headline)
            Text("No resume templates are available. Open the Template Editor to create or import one before continuing.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 360)
            Button("Open Template Editor") {
                Task { @MainActor in
                    NotificationCenter.default.post(name: .showTemplateEditor, object: nil)
                    if let delegate = NSApplication.shared.delegate as? AppDelegate {
                        delegate.showTemplateEditorWindow()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .background(.regularMaterial)
        .cornerRadius(16)
        .shadow(radius: 8)
    }
}

// MARK: - Setup Wizard Sheet

private struct SetupWizardSheetUnified: View {
    let onComplete: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(EnabledLLMStore.self) private var enabledLLMStore
    @Environment(AppEnvironment.self) private var appEnvironment

    var body: some View {
        SetupWizardView(onFinish: onComplete)
            .environment(appState)
            .environment(enabledLLMStore)
            .environment(appEnvironment.openRouterService)
            .environment(appEnvironment.llmFacade)
    }
}
