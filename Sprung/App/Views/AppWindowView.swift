//
//  AppWindowView.swift
//  Sprung
//
//  Created by Christopher Culbreath on 9/1/24.
//  Renamed from TabWrapperView to better reflect responsibility
//
import SwiftUI
import AppKit
struct AppWindowView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
    @Environment(AppState.self) private var appState: AppState
    @State private var listingButtons: SaveButtons = .init(edit: false, save: false, cancel: false)
    @Binding var selectedTab: TabList
    @Binding var refPopup: Bool
    @Binding var hasVisitedResumeTab: Bool
    @Binding var tabRefresh: Bool
    @Binding var showSlidingList: Bool

    // Centralized sheet state management for all app windows/modals
    @Binding var sheets: AppSheets
    @Binding var clarifyingQuestions: [ClarifyingQuestion]
    var body: some View {
        @Bindable var jobAppStore = jobAppStore
        mainContent
    }

    private var mainContent: some View {
        VStack {
            if jobAppStore.selectedApp != nil {
                tabView
            } else {
                // Show empty state when no job app is selected
                VStack {
                    Spacer()
                    Text("Select a job application from the sidebar to begin")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .id($tabRefresh.wrappedValue)
        .modifier(AppWindowViewModifiers(
            jobAppStore: jobAppStore,
            sheets: $sheets,
            refPopup: $refPopup,
            coverLetterStore: coverLetterStore,
            appState: appState,
            selectedTab: $selectedTab,
            hasVisitedResumeTab: $hasVisitedResumeTab,
            updateMyLetter: updateMyLetter
        ))
    }

    private var tabView: some View {
        TabView(selection: $selectedTab) {
            JobAppDetailView(tab: $selectedTab, buttons: $listingButtons)
                .tabItem {
                    Label(TabList.listing.rawValue, systemImage: "newspaper")
                }
                .tag(TabList.listing)
            ResumeSplitView(
                isWide: .constant(true),
                tab: $selectedTab,
                showResumeInspector: $sheets.showResumeInspector,
                refresh: $tabRefresh,
                sheets: $sheets,
                clarifyingQuestions: $clarifyingQuestions
            )
                .tabItem {
                    Label(TabList.resume.rawValue, systemImage: "person.crop.rectangle.stack")
                }
                .tag(TabList.resume)
            CoverLetterView(showCoverLetterInspector: $sheets.showCoverLetterInspector)
                .tabItem {
                    Label(TabList.coverLetter.rawValue, systemImage: "person.2.crop.square.stack")
                }
                .tag(TabList.coverLetter)
                .disabled(!(jobAppStore.selectedApp?.hasAnyRes ?? false))

            ResumeExportView()
                .tabItem {
                    Label(TabList.submitApp.rawValue, systemImage: "paperplane")
                }
                .tag(TabList.submitApp)
                .disabled(jobAppStore.selectedApp?.selectedRes == nil)
        }
    }

    // MARK: - Toolbar Action Methods
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
struct SaveButtons {
    var edit: Bool = false
    var save: Bool = false
    var cancel: Bool = false
}
// MARK: - View Modifiers
struct AppWindowViewModifiers: ViewModifier {
    let jobAppStore: JobAppStore
    @Binding var sheets: AppSheets
    @Binding var refPopup: Bool
    let coverLetterStore: CoverLetterStore
    let appState: AppState
    @Binding var selectedTab: TabList
    @Binding var hasVisitedResumeTab: Bool
    let updateMyLetter: () -> Void

    func body(content: Content) -> some View {
        let step1: some View = content
            .onChange(of: jobAppStore.selectedApp) { _, _ in
                updateMyLetter()
            }
            .onChange(of: jobAppStore.selectedApp?.hasAnyRes ?? false) { _, _ in
            }
            .onChange(of: selectedTab) { _, newTab in
                if newTab == .resume {
                    if !hasVisitedResumeTab {
                        sheets.showResumeInspector = false
                        hasVisitedResumeTab = true
                    }
                }
            }
            .onAppear {
                updateMyLetter()
                hasVisitedResumeTab = false
            }

        let step2: some View = step1
            .sheet(isPresented: $refPopup) {
                ResRefView()
                    .padding()
            }
            .sheet(isPresented: $sheets.showResumeReview) {
                if let selectedResume = jobAppStore.selectedApp?.selectedRes {
                    ResumeReviewSheet(selectedResume: .constant(selectedResume))
                }
            }

        let step3: some View = step2
            .sheet(isPresented: $sheets.showMultiModelChooseBest) {
                if jobAppStore.selectedApp != nil,
                   let currentCoverLetter = coverLetterStore.cL {
                    MultiModelChooseBestCoverLetterSheet(coverLetter: .constant(currentCoverLetter))
                }
            }
            .sheet(isPresented: $sheets.showNewJobApp) {
                NewAppSheetView(isPresented: $sheets.showNewJobApp)
                .environment(jobAppStore)
            }
            .sheet(isPresented: $sheets.showApplicationReview) {
                if let selApp = jobAppStore.selectedApp,
                   let currentResume = selApp.selectedRes,
                   let currentCoverLetter = selApp.selectedCover,
                   currentCoverLetter.generated {
                    ApplicationReviewSheet(
                        jobApp: selApp,
                        resume: currentResume,
                        availableCoverLetters: selApp.coverLetters.filter { $0.generated }.sorted { $0.moddedDate > $1.moddedDate }
                    )
                }
            }
            .sheet( isPresented: $sheets.showBatchCoverLetter) {
                BatchCoverLetterView()
                    .environment(appState)
                    .environment(jobAppStore)
                    .environment(coverLetterStore)
            }

        return step3
    }
}
