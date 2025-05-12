// PhysCloudResume/App/Views/Toolbar.swift
import SwiftUI

struct BuildToolbar: ToolbarContent {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    // @Environment(ResStore.self) private var resStore: ResStore
    // @Environment(ResRefStore.self) private var resRefStore: ResRefStore

    @Binding var selectedTab: TabList
    @State var saveIsHovering: Bool = false
    @Binding var listingButtons: SaveButtons
    @Binding var letterButtons: CoverLetterButtons
    @Binding var resumeButtons: ResumeButtons
    @Binding var refresh: Bool

    @State private var showApplicationReviewSheetInToolbar: Bool = false

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

    // Breaking this down to avoid type checker blowup
    var body: some ToolbarContent {
        Group {
            // Always include these base items
            baseToolbarItems

            // Conditionally include content based on app state and tab
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
        ToolbarItem(placement: .principal) { Spacer() }
    }

    // MARK: - Tab-specific Content

    @ToolbarContentBuilder
    private func tabSpecificContent(for selApp: JobApp) -> some ToolbarContent {
        // By separating cases into individual toolbarItem functions with no conditional returns,
        // we avoid complex type checking
        listingToolbarItem(for: selApp)
        resumeToolbarItem(for: selApp)
        coverLetterToolbarItem(for: selApp)
        submitAppToolbarItem(for: selApp)
    }

    // Separate each tab's toolbar item with minimal conditional logic
    @ToolbarContentBuilder
    private func listingToolbarItem(for _: JobApp) -> some ToolbarContent {
        // Only create this toolbar item if we're on the listing tab
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
        // Only create this toolbar item if we're on the resume tab
        if selectedTab == .resume {
            ToolbarItem(placement: .primaryAction) {
                Group {
                    if selApp.hasAnyRes {
                        // Restore the original resumeToolbarContent functionality
                        // Assuming the resumeToolbarContent function was intended to use ResumeToolbar
                        // If this doesn't compile, you'll need to adjust based on your actual ResumeToolbar implementation
                        resumeToolbarContent(
                            buttons: $resumeButtons,
                            selectedResume: selectedResumeBinding
                        )
                    } else {
                        Text("No resume to display")
                    }
                }
            }
        }
    }

    // Re-adding this function that might have been in the original code
    // If this helper method doesn't exist in your codebase, you should replace the call above with direct ResumeToolbar usage
    func resumeToolbarContent(buttons: Binding<ResumeButtons>, selectedResume: Binding<Resume?>) -> some View {
        HStack(spacing: 8) { // Group the buttons for consistent alignment
            // AI resume enhancement feature
            if selectedResume.wrappedValue?.rootNode != nil {
                AiFunctionView(res: selectedResume)
            } else {
                // Optional: Add a placeholder or empty view if no resume is selected
                // to help maintain layout consistency, though often omitting it is fine.
                // For example: Text(" ").opacity(0)
            }

            // AI resume review feature
            Button {
                buttons.wrappedValue.showResumeReviewSheet.toggle()
            } label: {
                Label("Review Resume", systemImage: "character.magnify") // Or your current icon, e.g., "doc.text.viewfinder"
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
            // Removed .onAppear as it's not directly related to the toolbar structure itself.
        }
    }

    @ToolbarContentBuilder
    private func coverLetterToolbarItem(for selApp: JobApp) -> some ToolbarContent {
        // Only create this toolbar item if we're on the cover letter tab
        if selectedTab == .coverLetter {
            if selApp.selectedCover != nil {
                // The CoverLetterToolbar now returns ToolbarContent directly
                CoverLetterToolbar(
                    buttons: $letterButtons,
                    refresh: $refresh
                )
            } else {
                ToolbarItem(placement: .primaryAction) {
                    Text("No Cover Letter Available")
                }
            }
        }
    }

    @ToolbarContentBuilder
    private func submitAppToolbarItem(for selApp: JobApp) -> some ToolbarContent {
        // Only create this toolbar item if we're on the submit app tab
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

// The free function `buildToolbar` which instantiates `BuildToolbar`.
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
