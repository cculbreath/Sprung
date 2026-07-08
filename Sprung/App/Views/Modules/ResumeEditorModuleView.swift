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

    /// Displayed sidebar width for a given available module width, computed
    /// synchronously inside the layout pass (from a GeometryReader) so it never
    /// lags behind a resize. The sidebar yields first when space is tight: it's
    /// capped so the detail column always keeps its per-tab minimum, which
    /// guarantees the panes sum to <= the available width and never overflow.
    private func sidebarDisplayWidth(_ available: CGFloat) -> CGFloat {
        guard isSidebarExpanded else { return collapsedHandleWidth }
        // Before first layout GeometryReader reports 0; show the stored width so
        // the sidebar doesn't flash to its minimum on every appearance.
        guard available > 0 else { return CGFloat(sidebarWidth) }
        let maxForSidebar = max(0, available - resizeHandleWidth - detailMinWidth)
        return min(CGFloat(sidebarWidth), maxForSidebar)
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
            // editor + PDF chevron bar + (PDF handle + preview floor when shown).
            // The 250 preview floor MUST match ResumeSplitView.minPdfPreviewWidth.
            return primaryColumn + 16 + (pdfPreviewVisible ? (resizeHandleWidth + 250) : 0)
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

        // GeometryReader gives the true available width up front, so panes are
        // sized within the same layout pass and can never overflow it (the
        // stuck, clipped state came from lagged onGeometryChange measurement).
        GeometryReader { geo in
            let sidebarW = sidebarDisplayWidth(geo.size.width)
            HStack(spacing: 0) {
                // Collapsible sidebar (skinny handle when collapsed)
                if isSidebarExpanded {
                    sidebarContent
                        .frame(width: sidebarW)
                        .transition(.move(edge: .leading).combined(with: .opacity))

                    // Draggable resize handle
                    VerticalResizeHandle(
                        width: $sidebarWidth,
                        minWidth: minSidebarWidth,
                        maxWidth: maxSidebarWidth,
                        displayedWidth: Double(sidebarW)
                    )
                } else {
                    // Skinny collapsed handle
                    CollapsedPanelHandle(edge: .leading, isExpanded: $isSidebarExpanded)
                }

                // Main content takes the remainder
                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
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


