// PhysCloudResume/App/Views/Toolbar.swift
import SwiftUI
import AppKit

@ToolbarContentBuilder
func buildToolbar(
    selectedTab: Binding<TabList>,
    listingButtons: Binding<SaveButtons>,
    letterButtons: Binding<CoverLetterButtons>,
    resumeButtons: Binding<ResumeButtons>,
    refresh: Binding<Bool>
) -> some ToolbarContent {
    BuildToolbar(
        selectedTab: selectedTab,
        listingButtons: listingButtons,
        letterButtons: letterButtons,
        resumeButtons: resumeButtons,
        refresh: refresh
    )
}

struct BuildToolbar: ToolbarContent {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(\.appState) private var appState
    // @Environment(ResStore.self) private var resStore: ResStore // Not directly used here
    // @Environment(ResRefStore.self) private var resRefStore: ResRefStore // Not directly used here

    @Binding var selectedTab: TabList
    @State var saveIsHovering: Bool = false
    @Binding var listingButtons: SaveButtons
    @Binding var letterButtons: CoverLetterButtons
    @Binding var resumeButtons: ResumeButtons
    @Binding var refresh: Bool // Keep this if other parts of the toolbar use it

    @State private var showApplicationReviewSheetInToolbar: Bool = false

    // AppStorage for API keys to enable/disable model fetching
    @AppStorage("openAiApiKey") private var openAiApiKey: String = "none"

    private var selectedResumeBinding: Binding<Resume?> {
        Binding<Resume?>(
            get: { jobAppStore.selectedApp?.selectedRes },
            set: { newValue in
                if jobAppStore.selectedApp != nil {
                    jobAppStore.selectedApp!.selectedRes = newValue
                }
            }
        )
    }

    // MARK: - Main Body

    var body: some ToolbarContent {
        Group {
            // Always include these base items
            baseToolbarItems

            // Add OpenAI Model Picker here, visible for relevant tabs
            // This will be the first item on the right due to order of definition for .primaryAction
            if selectedTab != .listing && openAiApiKey != "none" {
                ToolbarItemGroup(placement: .primaryAction) { // Changed to .primaryAction
                    OpenAIModelSettingsView() // Directly embed the view
                        .frame(minWidth: 150, maxWidth: 250) // Adjust frame for toolbar
                }
            }

            // Conditionally include content based on app state and tab
            // These will appear to the right of the Model Picker
            if let selApp = jobAppStore.selectedApp {
                tabSpecificContent(for: selApp)
            }
        }
    }

    // MARK: - Base Toolbar Items

    @ToolbarContentBuilder
    private var baseToolbarItems: some ToolbarContent {
        if let selApp = jobAppStore.selectedApp {
            ToolbarItem(placement: .navigation) { selApp.statusTag }
            ToolbarItem(placement: .navigation) {
                twoTierTextToolbar(headline: selApp.jobPosition, caption: selApp.companyName)
            }
        }
        ToolbarItem(placement: .principal) { Spacer() } // This spacer pushes subsequent items to the right
    }

    // MARK: - Tab-specific Content

    @ToolbarContentBuilder
    private func tabSpecificContent(for selApp: JobApp) -> some ToolbarContent {
        // These items will be added after the OpenAIModelSettingsView for relevant tabs
        listingToolbarItem(for: selApp)
        resumeToolbarItem(for: selApp)
        coverLetterToolbarItem(for: selApp)
        submitAppToolbarItem(for: selApp)
    }

    @ToolbarContentBuilder
    private func listingToolbarItem(for _: JobApp) -> some ToolbarContent {
        if selectedTab == .listing {
            ToolbarItem(placement: .primaryAction) {
                Group {
                    if listingButtons.edit {
                        saveButton()
                    } else {
                        toggleEditButton()
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private func resumeToolbarItem(for selApp: JobApp) -> some ToolbarContent {
        if selectedTab == .resume {
            ToolbarItem(placement: .primaryAction) {
                Group {
                    if selApp.hasAnyRes {
                        resumeToolbarContent(
                            buttons: $resumeButtons,
                            selectedResume: selectedResumeBinding
                        )
                    } else {
                        EmptyView()
                    }
                }
            }
        }
    }

    // This function builds the content for the resume tab's toolbar item group
    func resumeToolbarContent(buttons: Binding<ResumeButtons>, selectedResume: Binding<Resume?>) -> some View {
        HStack(spacing: 8) { // HStack to arrange buttons horizontally
            // AI resume enhancement feature (the "squiggle")
            if selectedResume.wrappedValue?.rootNode != nil {
                AiFunctionView(res: selectedResume)
            }

            // AI resume review feature
            Button {
                buttons.wrappedValue.showResumeReviewSheet.toggle()
            } label: {
                Label("Review Resume", systemImage: "character.magnify")
            }
            .help("AI Resume Review")
            .disabled(selectedResume.wrappedValue == nil)
            .sheet(isPresented: Binding(
                get: { buttons.wrappedValue.showResumeReviewSheet },
                set: { buttons.wrappedValue.showResumeReviewSheet = $0 }
            )) {
                ResumeReviewSheet(selectedResume: selectedResume)
            }

            // Resume inspector toggle
            Button(action: {
                buttons.wrappedValue.showResumeInspector.toggle()
            }) {
                Label("Toggle Inspector", systemImage: "sidebar.right")
            }
        }
    }

    @ToolbarContentBuilder
    private func coverLetterToolbarItem(for selApp: JobApp) -> some ToolbarContent {
        if selectedTab == .coverLetter {
            if selApp.selectedCover != nil {
                // CoverLetterToolbar is now shown as an overlay in CoverLetterView
                // so we don't need to show it in the window toolbar
                ToolbarItem(placement: .primaryAction) {
                    EmptyView()
                }
            } else {
                ToolbarItem(placement: .primaryAction) {
                    EmptyView()
                }
            }
        }
    }

    @ToolbarContentBuilder
    private func submitAppToolbarItem(for selApp: JobApp) -> some ToolbarContent {
        if selectedTab == .submitApp {
            ToolbarItem(placement: .primaryAction) {
                applicationReviewButton(for: selApp)
            }
        }
    }

    // Helper function to simplify the application review button logic
    private func applicationReviewButton(for selApp: JobApp) -> some View {
        Button {
            showApplicationReviewSheetInToolbar.toggle()
        } label: {
            Label("Review Application", systemImage: "character.magnify")
        }
        .disabled(
            selApp.selectedRes == nil ||
                selApp.selectedCover == nil ||
                selApp.selectedCover?.generated != true
        )
        .help("Review the current application packet (resume and cover letter)")
        .sheet(isPresented: $showApplicationReviewSheetInToolbar) {
            applicationReviewSheet(for: selApp)
        }
    }

    // Helper function to extract the sheet content
    private func applicationReviewSheet(for selApp: JobApp) -> some View {
        Group {
            if let currentResume = selApp.selectedRes,
               let currentCoverLetter = selApp.selectedCover,
               currentCoverLetter.generated
            {
                ApplicationReviewSheet(
                    jobApp: selApp,
                    resume: currentResume,
                    availableCoverLetters: selApp.coverLetters.filter { $0.generated }.sorted { $0.moddedDate > $1.moddedDate }
                )
            } else {
                Text("Cannot review: Ensure a resume is selected and a cover letter has been generated.")
                    .padding().frame(minWidth: 300, minHeight: 100)
            }
        }
    }

    // --- Helper functions for simple View-returning buttons ---
    func twoTierTextToolbar(headline: String, caption: String, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment) {
            Text(headline).font(.headline).lineLimit(1)
            Text(caption).font(.caption).lineLimit(1)
        }
    }

    func saveButton() -> some View {
        Button(action: { listingButtons.save.toggle() }) {
            Image(systemName: "checkmark.circle")
                .imageScale(.large)
                .foregroundColor(saveIsHovering ? .accentColor : .primary)
                .onHover { hovering in saveIsHovering = hovering }
        }
        .help("Save Changes")
    }

    func toggleEditButton() -> some View {
        Button(action: { listingButtons.edit.toggle() }) {
            Image(systemName: "pencil.and.list.clipboard")
                .imageScale(.large)
                .foregroundColor(listingButtons.edit ? .accentColor : .primary)
        }
        .help(listingButtons.edit ? "Finish Editing" : "Edit Job Application Details")
    }
}
