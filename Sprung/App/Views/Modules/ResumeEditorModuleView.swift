//
//  ResumeEditorModuleView.swift
//  Sprung
//
//  Resume Editor module - wrapper for existing resume editing functionality.
//  This embeds the existing ContentView body (sidebar + tabs + PDF preview) unchanged.
//

import SwiftUI

/// Resume Editor module - embeds existing resume editor with sidebar and tabs
struct ResumeEditorModuleView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(JobAppStore.self) private var jobAppStore
    @Environment(CoverLetterStore.self) private var coverLetterStore
    @Environment(NavigationStateService.self) private var navigationState
    @Environment(ReasoningStreamManager.self) private var reasoningStreamManager
    @Environment(EnabledLLMStore.self) private var enabledLLMStore
    @Environment(ResumeReviseViewModel.self) private var resumeReviseViewModel
    @Environment(WindowCoordinator.self) private var windowCoordinator
    @Environment(UnifiedJobFocusState.self) private var focusState

    @State var tabRefresh: Bool = false
    @State var showSlidingList: Bool = false
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .doubleColumn
    @State private var sheets = AppSheets()
    @State private var clarifyingQuestions: [ClarifyingQuestion] = []
    @State private var listingButtons = SaveButtons()
    @State private var hasVisitedResumeTab: Bool = false
    @State private var refPopup: Bool = false
    @State private var menuHandler = MenuNotificationHandler()

    var body: some View {
        @Bindable var jobAppStore = jobAppStore
        @Bindable var navigationState = navigationState

        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            // --- Sidebar Column ---
            SidebarView(
                tabRefresh: $tabRefresh,
                selectedApp: $jobAppStore.selectedApp,
                showSlidingList: $showSlidingList
            )
            .frame(minWidth: 220, maxWidth: .infinity)
        } detail: {
            // --- Detail Column ---
            VStack(alignment: .leading) {
                if jobAppStore.selectedApp != nil {
                    AppWindowView(
                        selectedTab: $navigationState.selectedTab,
                        refPopup: $refPopup,
                        hasVisitedResumeTab: $hasVisitedResumeTab,
                        tabRefresh: $tabRefresh,
                        showSlidingList: $showSlidingList,
                        sheets: $sheets,
                        clarifyingQuestions: $clarifyingQuestions
                    )
                    .background {
                        Rectangle()
                            .fill(.clear)
                            .ignoresSafeArea(.all)
                    }
                } else {
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
            .toolbar(id: "sprungMainToolbar") {
                buildUnifiedToolbar(
                    selectedTab: $navigationState.selectedTab,
                    listingButtons: $listingButtons,
                    refresh: $tabRefresh,
                    sheets: $sheets,
                    clarifyingQuestions: $clarifyingQuestions,
                    showNewAppSheet: $sheets.showNewJobApp
                )
            }
        }
        // Reasoning stream overlay (for AI thinking display)
        .overlay {
            if reasoningStreamManager.isVisible && !resumeReviseViewModel.showParallelReviewQueueSheet {
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
        .appSheets(sheets: $sheets, clarifyingQuestions: $clarifyingQuestions, refPopup: $refPopup)
        .onChange(of: jobAppStore.selectedApp) { _, newValue in
            navigationState.saveSelectedJobApp(newValue)
            updateMyLetter()
            // Sync to unified focus state
            focusState.focusedJob = newValue
        }
        .onChange(of: focusState.focusedJob) { _, newFocusedJob in
            // Sync from unified focus state (when navigating from Pipeline)
            if let job = newFocusedJob, job.id != jobAppStore.selectedApp?.id {
                jobAppStore.selectedApp = job
            }
        }
        .onChange(of: focusState.focusedTab) { _, newTab in
            // Sync tab from unified focus state
            navigationState.selectedTab = newTab
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
            Logger.debug("ResumeEditorModuleView configuring MenuNotificationHandler", category: .ui)
            menuHandler.configure(
                jobAppStore: jobAppStore,
                coverLetterStore: coverLetterStore,
                sheets: $sheets,
                selectedTab: $navigationState.selectedTab,
                showSlidingList: $showSlidingList
            )
            navigationState.restoreSelectedJobApp(from: jobAppStore)
            updateMyLetter()
            hasVisitedResumeTab = false

            // Restore from unified focus state if available
            if let job = focusState.focusedJob, jobAppStore.selectedApp == nil {
                jobAppStore.selectedApp = job
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectJobApp)) { notification in
            if let jobAppId = notification.userInfo?["jobAppId"] as? UUID,
               let jobApp = jobAppStore.jobApps.first(where: { $0.id == jobAppId }) {
                jobAppStore.selectedApp = jobApp
            }
        }
        .focusedValue(\.knowledgeCardsVisible, $showSlidingList)
    }

    // MARK: - Helper Methods

    func updateMyLetter() {
        if let selectedApp = jobAppStore.selectedApp {
            let letter: CoverLetter
            if let lastLetter = selectedApp.coverLetters.last {
                letter = lastLetter
            } else {
                letter = coverLetterStore.create(jobApp: selectedApp)
            }
            coverLetterStore.cL = letter
        } else {
            coverLetterStore.cL = nil
        }
    }
}
