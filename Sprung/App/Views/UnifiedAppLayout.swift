//
//  UnifiedAppLayout.swift
//  Sprung
//
//  Top-level layout combining icon bar and module content.
//

import SwiftUI

/// Top-level layout combining icon bar and module content
struct UnifiedAppLayout: View {
    @Environment(ModuleNavigationService.self) private var navigation
    @Environment(WindowCoordinator.self) private var windowCoordinator
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(ReasoningStreamManager.self) private var reasoningStreamManager
    @Environment(ResumeReviseViewModel.self) private var resumeReviseViewModel
    @Environment(AppState.self) private var appState
    @Environment(EnabledLLMStore.self) private var enabledLLMStore

    @State private var showSetupWizard: Bool = false
    @State private var didPromptTemplateEditor = false
    @AppStorage("hasCompletedSetupWizard") private var hasCompletedSetupWizard = false

    var body: some View {
        HStack(spacing: 0) {
            // Icon bar (always visible)
            IconBarView()

            // Module content
            ModuleContentView(module: navigation.selectedModule)
        }
        .frame(minWidth: 1000, minHeight: 650)
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

        let hasOpenRouterKey = !(APIKeyManager.get(.openRouter)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasOpenAIKey = !(APIKeyManager.get(.openAI)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

        if !hasOpenRouterKey || !hasOpenAIKey {
            return true
        }

        guard !hasCompletedSetupWizard else { return false }

        let hasGeminiKey = !(APIKeyManager.get(.gemini)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasModels = !enabledLLMStore.enabledModels.isEmpty
        return !hasGeminiKey || !hasModels
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
    }
}
