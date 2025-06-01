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
    @Environment(AppState.self) private var appState: AppState
    // @Environment(ResStore.self) private var resStore: ResStore // Not directly used here
    // @Environment(ResRefStore.self) private var resRefStore: ResRefStore // Not directly used here

    @Binding var selectedTab: TabList
    @State var saveIsHovering: Bool = false
    @Binding var listingButtons: SaveButtons
    @Binding var letterButtons: CoverLetterButtons
    @Binding var resumeButtons: ResumeButtons
    @Binding var refresh: Bool // Keep this if other parts of the toolbar use it

    @State private var showApplicationReviewSheetInToolbar: Bool = false
    @State private var isUpdatingModel: Bool = false

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
        // Always include these base items
        baseToolbarItems

        // Consolidate all trailing items into a single group to ensure proper right-edge positioning
        if let selApp = jobAppStore.selectedApp {
            ToolbarItemGroup(placement: .primaryAction) {
                HStack(spacing: 8) {
                    // Add Model Picker for non-listing tabs
                    if selectedTab != .listing {
                        HStack(spacing: 8) {
                            ModelPickerView(
                                selectedModel: .init(
                                    get: { UserDefaults.standard.string(forKey: "preferredLLMModel") ?? AIModels.gpt4o_latest },
                                    set: { newValue in 
                                        isUpdatingModel = true
                                        UserDefaults.standard.set(newValue, forKey: "preferredLLMModel")
                                        // Update the LLM client for the new model
                                        Task { @MainActor in
                                            LLMRequestService.shared.updateClientForCurrentModel()
                                            // Add a small delay to show the loading indicator
                                            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                                            isUpdatingModel = false
                                        }
                                    }
                                ),
                                showRefreshButton: false,
                                useModelSelection: true  // Use user's model selection preferences
                            )
                            .environmentObject(ModelService.shared)
                            .environment(appState)
                            .frame(minWidth: 150, maxWidth: 250)
                            .disabled(isUpdatingModel)
                            
                            // Show loading indicator when updating model
                            if isUpdatingModel {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .help("Updating model...")
                            }
                        }
                    }
                    
                    // Tab-specific content
                    tabSpecificContentInline(for: selApp)
                }
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
    
    @ViewBuilder
    private func tabSpecificContentInline(for selApp: JobApp) -> some View {
        // Return appropriate content based on selected tab
        switch selectedTab {
        case .listing:
            if listingButtons.edit {
                saveButton()
            } else {
                toggleEditButton()
            }
        case .resume:
            if selApp.hasAnyRes {
                resumeToolbarContent(
                    buttons: $resumeButtons,
                    selectedResume: selectedResumeBinding
                )
            }
        case .coverLetter:
            coverLetterToolbarContent(buttons: $letterButtons)
        case .submitApp:
            applicationReviewButton(for: selApp)
        case .none:
            EmptyView()
        }
    }

    // This function builds the content for the cover letter tab's toolbar item group
    func coverLetterToolbarContent(buttons: Binding<CoverLetterButtons>) -> some View {
        HStack(spacing: 8) {
            // Get the existing view from our provider - this avoids creating it during rendering
            CoverLetterAiViewProvider.shared.getView(buttons: buttons, refresh: .constant(false))
            
            // Batch generation button
            Button(action: {
                buttons.wrappedValue.showBatchGeneration = true
            }) {
                Label("Batch Generate", systemImage: "square.stack.3d.up.fill")
            }
            .help("Generate cover letters with multiple models")

            Button(action: {
                buttons.wrappedValue.showInspector.toggle()
            }) {
                Label("Toggle Inspector", systemImage: "sidebar.right")
            }
            .help("Toggle Inspector Panel")
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
