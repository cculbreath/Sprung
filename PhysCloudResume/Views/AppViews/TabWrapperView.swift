import SwiftUI

struct TabWrapperView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(ResStore.self) private var resStore: ResStore
    @Environment(ResRefStore.self) private var resRefStore: ResRefStore
    @Environment(ResModelStore.self) private var resModelStore: ResModelStore
    @Environment(CoverRefStore.self) private var coverRefStore: CoverRefStore
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore

    @State private var listingButtons: SaveButtons = .init(edit: false, save: false, cancel: false)
    @Binding var selectedTab: TabList
    @State private var refPopup: Bool = false
    @State private var coverLetterButtons: CoverLetterButtons = .init(showInspector: true, runRequested: false)
    @State private var resumeButtons: ResumeButtons = .init(
        showResumeInspector: true, aiRunning: false
    )
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

                    ResumeViewSetup(resumeButtons: $resumeButtons, refresh: $tabRefresh, currentTab: selectedTab)
                        .tabItem {
                            Label(TabList.resume.rawValue, systemImage: "person.crop.rectangle.stack")
                        }
                        .tag(TabList.resume)

                    if jobAppStore.selectedApp?.hasAnyRes ?? false {
                        CoverLetterView(buttons: $coverLetterButtons)
                            .tabItem {
                                Label(TabList.coverLetter.rawValue, systemImage: "person.2.crop.square.stack")
                            }
                            .tag(TabList.coverLetter)
                            .disabled(
                                jobAppStore.selectedApp?.hasAnyRes == nil
                            ) // Disable tab if no selected job app
                        ResumeExportView()
                            .tabItem {
                                Label(TabList.submitApp.rawValue, systemImage: "paperplane")
                            }
                            .tag(TabList.submitApp)
                            .disabled(
                                jobAppStore.selectedApp?.selectedRes == nil
                            ) // Disable tab if no selected job app
                    }
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
                .onChange(of: jobAppStore.selectedApp?.hasAnyRes ?? false) { _, newVal in
                    print(newVal ? "tab resExists" : "change res doesn't exist")
                }
                .onChange(of: $tabRefresh.wrappedValue) { _, newvalue in print("Tab is is now + \(newvalue ? "true" : "false")") }
                .sheet(isPresented: $refPopup) {
                    ResRefView()
                        .padding()
                }
                .onAppear {
                    updateMyLetter()
                }
        }
    }

    func updateMyLetter() {
        print("update cover letter")
        if let selectedApp = jobAppStore.selectedApp {
            if let lastLetter = selectedApp.coverLetters.last {
                coverLetterStore.cL = lastLetter
            } else {
                coverLetterStore.cL = coverLetterStore.create(jobApp: selectedApp)
            }
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

struct CoverLetterButtons {
    var showInspector: Bool = false
    var runRequested: Bool = false
}

struct ResumeButtons {
    var showResumeInspector: Bool = false
    var aiRunning: Bool = false
}
