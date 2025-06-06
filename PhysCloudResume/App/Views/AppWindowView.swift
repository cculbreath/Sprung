//
//  AppWindowView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/1/24.
//  Renamed from TabWrapperView to better reflect responsibility
//

import SwiftUI

struct AppWindowView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
    @Environment(\.appState) private var appState: AppState

    @State private var listingButtons: SaveButtons = .init(edit: false, save: false, cancel: false)
    @Binding var selectedTab: TabList
    @State private var refPopup: Bool = false
    @State private var hasVisitedResumeTab: Bool = false
    @Binding var tabRefresh: Bool
    
    // Centralized sheet state management for all app windows/modals
    @State private var sheets = AppSheets()
    @State private var clarifyingQuestions: [ClarifyingQuestion] = []
    
    // Revision workflow - managed by ResumeReviseViewModel
    @State private var resumeReviseViewModel: ResumeReviseViewModel?

    var body: some View {
        @Bindable var jobAppStore = jobAppStore
        if let jobApp = jobAppStore.selectedApp {
            @Bindable var jobApp = jobApp

            VStack {
                // Simple direct binding to selectedTab - no restrictions or custom logic
                let tabBinding = $selectedTab

                TabView(selection: tabBinding) {
                    JobAppDetailView(tab: $selectedTab, buttons: $listingButtons)
                        .tabItem {
                            Label(TabList.listing.rawValue, systemImage: "newspaper")
                        }
                        .tag(TabList.listing)

                    ResumeSplitView(
                        isWide: .constant(true), // You may want to make this configurable
                        tab: $selectedTab,
                        showResumeInspector: $sheets.showResumeInspector,
                        refresh: $tabRefresh
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
                        .disabled(
                            !jobAppStore.selectedApp!.hasAnyRes
                        ) // Disable tab if no resumes available
                        
                    ResumeExportView()
                        .tabItem {
                            Label(TabList.submitApp.rawValue, systemImage: "paperplane")
                        }
                        .tag(TabList.submitApp)
                        .disabled(
                            jobAppStore.selectedApp?.selectedRes == nil
                        ) // Disable tab if no selected resume
                }
                .padding(.all)

            }.id($tabRefresh.wrappedValue)
                .toolbar {
                    buildUnifiedToolbar(
                        selectedTab: $selectedTab,
                        listingButtons: $listingButtons,
                        refresh: $tabRefresh,
                        sheets: $sheets,
                        clarifyingQuestions: $clarifyingQuestions,
                        resumeReviseViewModel: resumeReviseViewModel
                    )
                }
                .toolbarBackground(.visible, for: .windowToolbar)
                .onChange(of: jobAppStore.selectedApp) { _, _ in
                    updateMyLetter()
                }
                .onChange(of: jobAppStore.selectedApp?.hasAnyRes ?? false) { _, _ in
                }
                .onChange(of: $tabRefresh.wrappedValue) { _, newvalue in Logger.debug("Tab is is now + \(newvalue ? "true" : "false")") }
                .onAppear {
                    // Initialize ResumeReviseViewModel when view appears
                    if resumeReviseViewModel == nil {
                        resumeReviseViewModel = ResumeReviseViewModel(llmService: LLMService.shared, appState: appState)
                    }
                }
                .onChange(of: selectedTab) { _, newTab in
                    // Track when the user switches to the resume tab
                    if newTab == .resume {
                        if !hasVisitedResumeTab {
                            // First visit to resume tab after launch - inspector should be hidden
                            sheets.showResumeInspector = false
                            hasVisitedResumeTab = true
                        }
                        // After first visit, we don't change the inspector state here
                        // so it retains its previous state
                    }
                }
                .sheet(isPresented: $refPopup) {
                    ResRefView()
                        .padding()
                }
                .sheet(isPresented: $sheets.showResumeReview) {
                    if let selectedResume = jobAppStore.selectedApp?.selectedRes {
                        ResumeReviewSheet(selectedResume: .constant(selectedResume))
                    }
                }
                .sheet(isPresented: Binding(
                    get: { resumeReviseViewModel?.showResumeRevisionSheet ?? false },
                    set: { resumeReviseViewModel?.showResumeRevisionSheet = $0 }
                )) {
                    if let selectedResume = jobAppStore.selectedApp?.selectedRes,
                       let viewModel = resumeReviseViewModel {
                        RevisionReviewView(
                            viewModel: viewModel,
                            resume: .constant(selectedResume)
                        )
                        .frame(minWidth: 650)
                    }
                }
                .sheet(isPresented: $sheets.showMultiModelChooseBest) {
                    if jobAppStore.selectedApp != nil,
                       let currentCoverLetter = coverLetterStore.cL {
                        MultiModelChooseBestCoverLetterSheet(coverLetter: .constant(currentCoverLetter))
                    }
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
                .sheet(isPresented: $sheets.showBatchCoverLetter) {
                    BatchCoverLetterView()
                        .environment(appState)
                        .environment(jobAppStore)
                        .environment(coverLetterStore)
                }
                .onAppear {
                    updateMyLetter()
                    // Reset the visited flag when the view appears
                    hasVisitedResumeTab = false
                }
        }
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

struct SaveButtons {
    var edit: Bool = false
    var save: Bool = false
    var cancel: Bool = false
}


