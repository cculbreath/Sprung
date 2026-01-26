//
//  ResumeEditorModuleView.swift
//  Sprung
//
//  Resume Editor module with unified collapsible sidebar and Resumes drawer.
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
    @Environment(ResStore.self) private var resStore

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

    // Resumes drawer state
    @AppStorage("resumeEditorDrawerExpanded") private var isResumesDrawerExpanded: Bool = true
    @AppStorage("resumeEditorResumeListHeight") private var resumeListHeight: Double = 160

    private let collapsedHandleWidth: CGFloat = 12
    private let minSidebarWidth: CGFloat = 200
    private let maxSidebarWidth: CGFloat = 400
    private let minResumeListHeight: CGFloat = 80
    private let maxResumeListHeight: CGFloat = 300

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

            // Resumes drawer at bottom
            if jobAppStore.selectedApp != nil {
                resumesDrawer
            }
        }
    }

    // MARK: - Resumes Drawer

    private var resumesDrawer: some View {
        @Bindable var jobAppStore = jobAppStore

        return VStack(spacing: 0) {
            // Top shadow/separator for visual distinction
            Rectangle()
                .fill(Color.primary.opacity(0.2))
                .frame(height: 1)
                .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)

            // Disclosure header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isResumesDrawerExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isResumesDrawerExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Text("Resumes")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    // Resume count badge
                    if let selApp = jobAppStore.selectedApp, !selApp.resumes.isEmpty {
                        Text("\(selApp.resumes.count)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary))
                    }

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isResumesDrawerExpanded, let selApp = jobAppStore.selectedApp {
                @Bindable var selApp = selApp

                VStack(spacing: 0) {
                    // Resume list with resizable height
                    if !selApp.resumes.isEmpty {
                        // Drag handle at top of resume list
                        HorizontalResizeHandle(
                            height: $resumeListHeight,
                            minHeight: minResumeListHeight,
                            maxHeight: maxResumeListHeight,
                            inverted: true
                        )

                        ScrollView {
                            VStack(spacing: 2) {
                                ForEach(selApp.resumes) { resume in
                                    SidebarResumeRowView(
                                        resume: resume,
                                        isSelected: selApp.selectedRes?.id == resume.id,
                                        onSelect: { selApp.selectedRes = resume }
                                    )
                                }
                            }
                            .padding(.horizontal, 8)
                        }
                        .frame(height: resumeListHeight)
                    }

                    Divider()
                        .padding(.vertical, 8)

                    // Template picker and create button
                    VStack(spacing: 8) {
                        HStack {
                            Text("Select Template")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }

                        HStack(spacing: 8) {
                            TemplatePicker()
                                .frame(maxWidth: .infinity)

                            Button("Create Resume") {
                                createResume(for: selApp)
                            }
                            .buttonStyle(.automatic)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .clipped()
        .glassEffect(.regular, in: .rect(cornerRadius: 0))
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

    private func createResume(for jobApp: JobApp) {
        if let template = appEnvironment.templateStore.templates().first {
            if resStore.create(jobApp: jobApp, sources: [], template: template) != nil {
                tabRefresh.toggle()
            }
        }
    }

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

// MARK: - Sidebar Resume Row View

private struct SidebarResumeRowView: View {
    let resume: Resume
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 2) {
                Text(resume.createdDateString)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .white : .primary)

                Text(resume.template?.name ?? "No template")
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Template Picker

private struct TemplatePicker: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var selectedTemplate: String = ""

    var body: some View {
        Picker("", selection: $selectedTemplate) {
            ForEach(appEnvironment.templateStore.templates()) { template in
                Text(template.name).tag(template.name)
            }
        }
        .labelsHidden()
        .onAppear {
            if let first = appEnvironment.templateStore.templates().first {
                selectedTemplate = first.name
            }
        }
    }
}
