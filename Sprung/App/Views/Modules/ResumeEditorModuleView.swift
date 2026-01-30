//
//  ResumeEditorModuleView.swift
//  Sprung
//
//  Resume Editor module with unified collapsible sidebar.
//

import SwiftUI

/// Resume Editor module - embeds existing resume editor with collapsible sidebar
struct ResumeEditorModuleView: View {
    @Environment(AppState.self) private var appState
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
    @State private var sheets = AppSheets()
    @State private var clarifyingQuestions: [ClarifyingQuestion] = []
    @State private var listingButtons = SaveButtons()
    @State private var hasVisitedResumeTab: Bool = false
    @State private var refPopup: Bool = false
    @State private var menuHandler = MenuNotificationHandler()

    // Sidebar collapse state - persisted
    @AppStorage("resumeEditorSidebarExpanded") private var isSidebarExpanded: Bool = true
    @AppStorage("resumeEditorSidebarWidth") private var sidebarWidth: Double = 280

    private let collapsedHandleWidth: CGFloat = 12
    private let minSidebarWidth: CGFloat = 200
    private let maxSidebarWidth: CGFloat = 400

    var body: some View {
        @Bindable var jobAppStore = jobAppStore
        @Bindable var navigationState = navigationState

        HStack(spacing: 0) {
            // Collapsible sidebar (skinny handle when collapsed)
            if isSidebarExpanded {
                sidebarContent
                    .frame(width: sidebarWidth)
                    .transition(.move(edge: .leading).combined(with: .opacity))

                // Draggable resize handle
                VerticalResizeHandle(
                    width: $sidebarWidth,
                    minWidth: minSidebarWidth,
                    maxWidth: maxSidebarWidth
                )
            } else {
                // Skinny collapsed handle
                CollapsedPanelHandle(edge: .leading, isExpanded: $isSidebarExpanded)
            }

            // Main content
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeInOut(duration: 0.2), value: isSidebarExpanded)
        // Reasoning stream overlay
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
        .appSheets(sheets: $sheets, clarifyingQuestions: $clarifyingQuestions, refPopup: $refPopup)
        .onChange(of: jobAppStore.selectedApp) { _, newValue in
            navigationState.saveSelectedJobApp(newValue)
            updateMyLetter()
            focusState.focusedJob = newValue
        }
        .onChange(of: focusState.focusedJob) { _, newFocusedJob in
            if let job = newFocusedJob, job.id != jobAppStore.selectedApp?.id {
                jobAppStore.selectedApp = job
            }
        }
        .onChange(of: focusState.focusedTab) { _, newTab in
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
        .onReceive(NotificationCenter.default.publisher(for: .toggleJobAppPane)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                isSidebarExpanded.toggle()
            }
        }
        .focusedValue(\.knowledgeCardsVisible, $showSlidingList)
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        @Bindable var jobAppStore = jobAppStore

        return VStack(spacing: 0) {
            // Sidebar header with collapse chevron
            HStack {
                Text("Jobs")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                PanelChevronToggle(edge: .leading, isExpanded: $isSidebarExpanded)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .rect(cornerRadius: 0))

            // Job list
            SidebarView(
                tabRefresh: $tabRefresh,
                selectedApp: $jobAppStore.selectedApp,
                showSlidingList: $showSlidingList
            )
        }
    }

    // MARK: - Detail Content

    private var detailContent: some View {
        @Bindable var navigationState = navigationState

        return VStack(alignment: .leading, spacing: 0) {
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
                emptyState
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "pencil.and.list.clipboard")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("Select a job application")
                .font(.title2)
                .foregroundColor(.secondary)

            if !isSidebarExpanded {
                Button("Show Sidebar") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSidebarExpanded = true
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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


