//
//  TabWrapperView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/1/24.
//

import SwiftUI

struct TabWrapperView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore

    @State private var listingButtons: SaveButtons = .init(edit: false, save: false, cancel: false)
    @Binding var selectedTab: TabList
    @State private var refPopup: Bool = false
    @State private var coverLetterButtons: CoverLetterButtons = .init(showInspector: true, runRequested: false)
    @State private var resumeButtons: ResumeButtons = .init(
        showResumeInspector: false, aiRunning: false, showResumeReviewSheet: false
    )
    @State private var hasVisitedResumeTab: Bool = false
    @Binding var tabRefresh: Bool

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
                        resumeButtons: $resumeButtons,
                        refresh: $tabRefresh
                    )
                        .tabItem {
                            Label(TabList.resume.rawValue, systemImage: "person.crop.rectangle.stack")
                        }
                        .tag(TabList.resume)

                    CoverLetterView(buttons: $coverLetterButtons)
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
                    buildToolbar(
                        selectedTab: $selectedTab,
                        listingButtons: $listingButtons,
                        letterButtons: $coverLetterButtons,
                        resumeButtons: $resumeButtons,
                        refresh: $tabRefresh
                    )
                }

                .onChange(of: jobAppStore.selectedApp) { _, _ in
                    updateMyLetter()
                }
                .onChange(of: jobAppStore.selectedApp?.hasAnyRes ?? false) { _, _ in
                }
                .onChange(of: $tabRefresh.wrappedValue) { _, newvalue in Logger.debug("Tab is is now + \(newvalue ? "true" : "false")") }
                .onChange(of: selectedTab) { _, newTab in
                    // Track when the user switches to the resume tab
                    if newTab == .resume {
                        if !hasVisitedResumeTab {
                            // First visit to resume tab after launch - inspector should be hidden
                            resumeButtons.showResumeInspector = false
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
            // Reset editing state and allow editing regardless of generation status
            coverLetterButtons.isEditing = false
            coverLetterButtons.canEdit = true
        } else {
            coverLetterStore.cL = nil
            coverLetterButtons.isEditing = false
            coverLetterButtons.canEdit = false
        }
    }
}

struct SaveButtons {
    var edit: Bool = false
    var save: Bool = false
    var cancel: Bool = false
}

struct CoverLetterButtons {
    var showInspector: Bool = false
    var runRequested: Bool = false
    /// Indicates a choose-best operation is in flight
    var chooseBestRequested: Bool = false
    /// Toggle between editing raw text and previewing PDF
    var isEditing: Bool = false
    /// Whether the current cover letter is editable (i.e., already generated)
    var canEdit: Bool = true
}

struct ResumeButtons {
    var showResumeInspector: Bool = false
    var aiRunning: Bool = false
    var showResumeReviewSheet: Bool = false
}
