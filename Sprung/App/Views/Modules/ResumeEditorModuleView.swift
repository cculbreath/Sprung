//
//  ResumeEditorModuleView.swift
//  Sprung
//
//  Resume Editor module with unified collapsible sidebar matching IconBar styling.
//

import SwiftUI

/// Resume Editor module - embeds existing resume editor with collapsible sidebar
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
    @State private var sheets = AppSheets()
    @State private var clarifyingQuestions: [ClarifyingQuestion] = []
    @State private var listingButtons = SaveButtons()
    @State private var hasVisitedResumeTab: Bool = false
    @State private var refPopup: Bool = false
    @State private var menuHandler = MenuNotificationHandler()

    // Sidebar collapse state - persisted
    @AppStorage("resumeEditorSidebarExpanded") private var isSidebarExpanded: Bool = true

    private let sidebarCollapsedWidth: CGFloat = 0
    private let sidebarExpandedWidth: CGFloat = 260

    var body: some View {
        @Bindable var jobAppStore = jobAppStore
        @Bindable var navigationState = navigationState

        HStack(spacing: 0) {
            // Collapsible sidebar
            if isSidebarExpanded {
                sidebarContent
                    .frame(width: sidebarExpandedWidth)
                    .transition(.move(edge: .leading).combined(with: .opacity))

                // Separator
                Rectangle()
                    .fill(Color(.separatorColor))
                    .frame(width: 1)
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
        .focusedValue(\.knowledgeCardsVisible, $showSlidingList)
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        @Bindable var jobAppStore = jobAppStore

        return VStack(spacing: 0) {
            // Sidebar header with collapse toggle
            HStack {
                Text("Jobs")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                PanelToggleButton(
                    edge: .leading,
                    isExpanded: $isSidebarExpanded,
                    collapsedIcon: "sidebar.left",
                    expandedIcon: "sidebar.left"
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Job list
            SidebarView(
                tabRefresh: $tabRefresh,
                selectedApp: $jobAppStore.selectedApp,
                showSlidingList: $showSlidingList
            )
        }
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Detail Content

    private var detailContent: some View {
        @Bindable var navigationState = navigationState

        return VStack(alignment: .leading, spacing: 0) {
            // Toolbar area with sidebar toggle when collapsed
            if !isSidebarExpanded {
                HStack {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSidebarExpanded = true
                        }
                    } label: {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Show sidebar")
                    .padding(.leading, 12)

                    Spacer()
                }
                .frame(height: 32)
                .background(Color(.windowBackgroundColor))

                Divider()
            }

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
            } else {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
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
