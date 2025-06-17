// PhysCloudResume/App/Views/ContentView.swift

import SwiftData
import SwiftUI

struct ContentView: View {
    // MARK: - Injected dependencies via SwiftUI Environment

    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
    @Environment(AppState.self) private var appState
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

    // App Storage remains here as it's app-level config
    @AppStorage("scrapingDogApiKey") var scrapingDogApiKey: String = "none"
    @AppStorage("availableStyles") var availableStylesString: String = "Typewriter"

    var body: some View {
        // Bindable references for selection binding
        @Bindable var jobAppStore = jobAppStore
        @Bindable var appState = appState

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
                    // Embed AppWindowView directly
                    AppWindowView(
                        selectedTab: $appState.selectedTab,
                        refPopup: $refPopup,
                        hasVisitedResumeTab: $hasVisitedResumeTab,
                        tabRefresh: $tabRefresh,
                        showSlidingList: $showSlidingList,
                        sheets: $sheets,
                        clarifyingQuestions: $clarifyingQuestions
                    )
//                        .navigationTitle(" ")
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
                    selectedTab: $appState.selectedTab,
                    listingButtons: $listingButtons,
                    refresh: $tabRefresh,
                    sheets: $sheets,
                    clarifyingQuestions: $clarifyingQuestions,
                    resumeReviseViewModel: appState.resumeReviseViewModel,
                    showNewAppSheet: $sheets.showNewJobApp,
                    showSlidingList: $showSlidingList
                )
            }
        }
        // Add reasoning stream view as overlay for AI thinking display (BEFORE sheets to ensure visibility)
        .overlay(alignment: .bottom) {
            if appState.globalReasoningStreamManager.isVisible {
                let _ = Logger.debug("🧠 [ContentView] About to render ReasoningStreamView")
                ReasoningStreamView(
                    isVisible: Binding(
                        get: { appState.globalReasoningStreamManager.isVisible },
                        set: { appState.globalReasoningStreamManager.isVisible = $0 }
                    ),
                    reasoningText: Binding(
                        get: { appState.globalReasoningStreamManager.reasoningText },
                        set: { appState.globalReasoningStreamManager.reasoningText = $0 }
                    )
                )
                .padding(.bottom, 10)
                .padding(.horizontal, 20)
                .zIndex(1000) // Ensure it's above other content
            }
        }
        // Apply sheet modifier
        .appSheets(sheets: $sheets, clarifyingQuestions: $clarifyingQuestions, refPopup: $refPopup)
        .onChange(of: jobAppStore.selectedApp) { _, newValue in
            // Sync selected app to AppState for template editor
            appState.selectedJobApp = newValue
            // Save selection for persistence
            appState.saveSelectedJobApp(newValue)
            updateMyLetter()
        }
        .onChange(of: appState.selectedTab) { _, newTab in
            if newTab == .resume {
                if !hasVisitedResumeTab {
                    sheets.showResumeInspector = false
                    hasVisitedResumeTab = true
                }
            }
        }
        .onAppear {
            Logger.debug("🟡 ContentView appeared - appState address: \(Unmanaged.passUnretained(appState).toOpaque())")
            
            // Restore persistent state
            appState.restoreSelectedJobApp(from: jobAppStore)
            
            // Initialize Resume Revise View Model
            appState.resumeReviseViewModel = ResumeReviseViewModel(
                llmService: LLMService.shared,
                appState: appState
            )
            
            // Initialize cover letter state
            updateMyLetter()
            hasVisitedResumeTab = false
            
            // Initial setup or logging can remain here
            if let storeURL = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent("Model.sqlite")
            {
                Logger.debug("Store URL: \(storeURL.path)")
            }
        }
        // Environment objects (like DragInfo) are inherited from ContentViewLaunch
    }
    
    // MARK: - Helper Methods
    
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
