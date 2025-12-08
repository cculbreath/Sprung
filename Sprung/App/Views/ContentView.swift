// Sprung/App/Views/ContentView.swift
import SwiftData
import SwiftUI
import AppKit
struct ContentView: View {
    // MARK: - Injected dependencies via SwiftUI Environment
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
    @Environment(NavigationStateService.self) private var navigationState
    @Environment(ReasoningStreamManager.self) private var reasoningStreamManager
    // DragInfo is inherited from ContentViewLaunch
    // States managed by ContentView
    @State var tabRefresh: Bool = false
    @State var showSlidingList: Bool = false
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .doubleColumn
    @State private var sheets = AppSheets()
    @State private var clarifyingQuestions: [ClarifyingQuestion] = []
    @State private var listingButtons = SaveButtons()
    @State private var hasVisitedResumeTab: Bool = false
    @State private var refPopup: Bool = false
    @State private var didPromptTemplateEditor = false
    @State private var menuHandler = MenuNotificationHandler()
    var body: some View {
        // Bindable references for selection binding
        @Bindable var jobAppStore = jobAppStore
        @Bindable var navigationState = navigationState
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            // --- Sidebar Column ---
            SidebarView(
                tabRefresh: $tabRefresh,
                selectedApp: $jobAppStore.selectedApp, // Pass selection binding
                showSlidingList: $showSlidingList // Pass sliding list state
            )
            .frame(minWidth: 220, maxWidth: .infinity) // Keep min width for sidebar
        } detail: {
            // --- Detail Column ---
            VStack(alignment: .leading) {
                if jobAppStore.selectedApp != nil {
                    // Embed AppWindowView directly with background extension
                    AppWindowView(
                        selectedTab: $navigationState.selectedTab,
                        refPopup: $refPopup,
                        hasVisitedResumeTab: $hasVisitedResumeTab,
                        tabRefresh: $tabRefresh,
                        showSlidingList: $showSlidingList,
                        sheets: $sheets,
                        clarifyingQuestions: $clarifyingQuestions
                    )
                    // Enable background extension for inspector overlay
                    .background {
                        // Background content that extends under the inspector
                        Rectangle()
                            .fill(.clear)
                            .ignoresSafeArea(.all)
                    }
                } else {
                    // Placeholder when no job application is selected
                    VStack {
                        Spacer()
                        Text("Select a job application from the sidebar to begin")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 200, maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            // Main application toolbar is attached here to be visible regardless of job app selection
            .toolbar(id: "mainToolbarV2") {
                buildUnifiedToolbar(
                    selectedTab: $navigationState.selectedTab,
                    listingButtons: $listingButtons,
                    refresh: $tabRefresh,
                    sheets: $sheets,
                    clarifyingQuestions: $clarifyingQuestions,
                    showNewAppSheet: $sheets.showNewJobApp,
                    showSlidingList: $showSlidingList
                )
            }
        }
        // Add reasoning stream view as overlay modal for AI thinking display
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
                    modelName: reasoningStreamManager.modelName
                )
                .zIndex(1000) // Ensure it's above all other content
                .onAppear {
                    Logger.verbose(
                        "🧠 [ContentView] Preparing ReasoningStreamView modal",
                        category: .ui
                    )
                }
            }
        }
        .overlay(alignment: .center) {
            if appEnvironment.requiresTemplateSetup {
                TemplateSetupOverlay()
            }
        }
        // Apply sheet modifier
        .appSheets(sheets: $sheets, clarifyingQuestions: $clarifyingQuestions, refPopup: $refPopup)
        .onChange(of: jobAppStore.selectedApp) { _, newValue in
            // Sync selected app to AppState for template editor
            navigationState.saveSelectedJobApp(newValue)
            updateMyLetter()
        }
        .onChange(of: navigationState.selectedTab) { _, newTab in
            if newTab == .resume {
                if !hasVisitedResumeTab {
                    sheets.showResumeInspector = false
                    hasVisitedResumeTab = true
                }
            }
        }
        .onAppear {
            Logger.debug("🎯 ContentView configuring MenuNotificationHandler", category: .ui)
            menuHandler.configure(
                jobAppStore: jobAppStore,
                coverLetterStore: coverLetterStore,
                sheets: $sheets,
                selectedTab: $navigationState.selectedTab,
                showSlidingList: $showSlidingList
            )
            Logger.debug(
                "🟡 ContentView appeared - restoring navigation state",
                category: .ui
            )
            // Restore persistent state
            navigationState.restoreSelectedJobApp(from: jobAppStore)
            // Initialize cover letter state
            updateMyLetter()
            hasVisitedResumeTab = false
            // Initial setup or logging can remain here
            if let storeURL = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent("Model.sqlite") {
                Logger.debug("Store URL: \(storeURL.path)")
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
        .focusedValue(\.knowledgeCardsVisible, $showSlidingList)
        // Environment objects (like DragInfo) are inherited from ContentViewLaunch
    }
    // MARK: - Helper Methods
    private func openTemplateEditor() {
        presentTemplateEditorWindow()
    }
    func updateMyLetter() {
        if let selectedApp = jobAppStore.selectedApp {
            // Determine or create the cover letter
            let letter: CoverLetter
            if let lastLetter = selectedApp.coverLetters.last {
                letter = lastLetter
            } else {
                letter = coverLetterStore.create(jobApp: selectedApp)
            }
            coverLetterStore.cL = letter
            // Note: Individual views now manage their own editing state
        } else {
            coverLetterStore.cL = nil
        }
    }
}
private struct TemplateSetupOverlay: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Add a Template to Get Started")
                .font(.headline)
            Text("No resume templates are available. Open the Template Editor to create or import one before continuing.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 360)
            Button("Open Template Editor") {
                openTemplateEditor()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .background(.regularMaterial)
        .cornerRadius(16)
        .shadow(radius: 8)
    }
    private func openTemplateEditor() {
        presentTemplateEditorWindow()
    }
}
private func presentTemplateEditorWindow() {
    Task { @MainActor in
        NotificationCenter.default.post(name: .showTemplateEditor, object: nil)
#if os(macOS)
        if NSApp.sendAction(#selector(AppDelegate.showTemplateEditorWindow), to: nil, from: nil) {
            return
        }
        if let delegate = NSApplication.shared.delegate as? AppDelegate {
            delegate.showTemplateEditorWindow()
            return
        }
#endif
    }
}
