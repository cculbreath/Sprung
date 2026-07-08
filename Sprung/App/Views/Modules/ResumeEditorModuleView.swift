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
    @Environment(WindowCoordinator.self) private var windowCoordinator
    @Environment(UnifiedJobFocusState.self) private var focusState

    @State var tabRefresh: Bool = false
    /// Shared app-sheet state owned by UnifiedAppLayout. The shell presents the
    /// sheets and observes the menu/URL-scheme notifications (so they work in
    /// every module); this module only reads/writes the bits its tabs need.
    @Binding var sheets: AppSheets

    // Sidebar collapse state - persisted
    @AppStorage("resumeEditorSidebarExpanded") private var isSidebarExpanded: Bool = true
    @AppStorage("resumeEditorSidebarWidth") private var sidebarWidth: Double = 280
    // PDF preview visibility (owned by ResumeSplitView) — read here only to size
    // the dynamic window floor; hiding the preview lets the window get narrower.
    @AppStorage("pdfPreviewVisible") private var pdfPreviewVisible = true

    // Matches CollapsedPanelHandle.handleWidth — the skinny strip shown in place
    // of the jobs sidebar when it's collapsed.
    private let collapsedHandleWidth: CGFloat = 24
    private let minSidebarWidth: CGFloat = 200
    private let maxSidebarWidth: CGFloat = 400
    private let resizeHandleWidth: CGFloat = 9

    /// Width the detail column must always keep: resume editor min (300) +
    /// preview chevron bar (16) + PDF resize handle (9) + compressed-PDF
    /// floor (100). Nested HStacks can't negotiate this on their own — the
    /// outer stack hands the sidebar its full stored width before the detail
    /// column's minimums are known, overflowing the window and sliding the
    /// editor under the sidebar.
    private let detailMinBudget: CGFloat = 425

    @State private var moduleWidth: CGFloat = 0

    /// Stored sidebar width, capped so the detail column's minimum always
    /// fits in the measured module width.
    private var effectiveSidebarWidth: Double {
        guard moduleWidth > 0 else { return sidebarWidth }
        let cap = Double(moduleWidth - resizeHandleWidth - detailMinBudget)
        return min(sidebarWidth, max(cap, Double(minSidebarWidth)))
    }

    /// Live minimum CONTENT width for this module (excluding the icon bar),
    /// published up to UnifiedAppLayout as part of the window floor. Shrinks as
    /// the jobs sidebar and PDF preview are collapsed.
    private var moduleMinContentWidth: CGFloat {
        let sidebarPart = isSidebarExpanded
            ? (minSidebarWidth + resizeHandleWidth)
            : collapsedHandleWidth
        return sidebarPart + detailMinWidth
    }

    /// Minimum width of the detail column for the active tab. Mirrors the
    /// pane layouts in ResumeSplitView (resume) and CoverLetterView (cover),
    /// so no tab's expanded panes get clipped at the window floor.
    private var detailMinWidth: CGFloat {
        let primaryColumn: CGFloat = 300
        switch navigationState.selectedTab {
        case .resume:
            // editor + PDF chevron bar + (PDF handle + preview floor when shown)
            return primaryColumn + 16 + (pdfPreviewVisible ? (resizeHandleWidth + 100) : 0)
        case .coverLetter:
            // letter column + (divider + inspector when shown, per CoverLetterView)
            return primaryColumn + (sheets.showCoverLetterInspector ? (1 + 340) : 0)
        case .listing, .submitApp, .none:
            return primaryColumn
        }
    }

    var body: some View {
        @Bindable var jobAppStore = jobAppStore
        @Bindable var navigationState = navigationState

        HStack(spacing: 0) {
            // Collapsible sidebar (skinny handle when collapsed)
            if isSidebarExpanded {
                sidebarContent
                    .frame(width: effectiveSidebarWidth)
                    .transition(.move(edge: .leading).combined(with: .opacity))

                // Draggable resize handle
                VerticalResizeHandle(
                    width: $sidebarWidth,
                    minWidth: minSidebarWidth,
                    maxWidth: maxSidebarWidth,
                    displayedWidth: effectiveSidebarWidth
                )
            } else {
                // Skinny collapsed handle
                CollapsedPanelHandle(edge: .leading, isExpanded: $isSidebarExpanded)
            }

            // Main content
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Parent-driven width (the flexible detail column makes this stack
        // fill it), so measuring here can't feed back into child sizing.
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { moduleWidth = $0 }
        .moduleMinContentSize(CGSize(width: moduleMinContentWidth, height: 650))
        .animation(.easeInOut(duration: 0.2), value: isSidebarExpanded)
        .onChange(of: jobAppStore.selectedApp) { _, newValue in
            updateMyLetter()
            focusState.focusedJob = newValue
            NotificationCenter.default.post(name: .toolbarNeedsValidation, object: nil)
        }
        .onChange(of: focusState.focusedJob) { _, newFocusedJob in
            if let job = newFocusedJob, job.id != jobAppStore.selectedApp?.id {
                jobAppStore.selectedApp = job
            }
        }
        .onChange(of: focusState.focusedTab) { _, newTab in
            navigationState.selectedTab = newTab
        }
        .onChange(of: navigationState.selectedTab) { _, _ in
            NotificationCenter.default.post(name: .toolbarNeedsValidation, object: nil)
        }
        .onAppear {
            // Restore the persisted job focus (single source: UnifiedJobFocusState ->
            // unifiedFocusedJobId), then propagate it to the store selection below.
            focusState.restoreFocus(from: jobAppStore.jobApps)
            updateMyLetter()

            // Apply the focused job (restored above, or set by another module e.g.
            // Pipeline before this view appeared) to the store selection.
            if let job = focusState.focusedJob, job.id != jobAppStore.selectedApp?.id {
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
                selectedApp: $jobAppStore.selectedApp
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
                    tabRefresh: $tabRefresh,
                    sheets: $sheets
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


