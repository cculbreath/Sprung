// PhysCloudResume/App/Views/UnifiedToolbar.swift
import SwiftUI
import AppKit

/// Unified toolbar with all buttons visible, using disabled state instead of hiding
@ToolbarContentBuilder
func buildUnifiedToolbar(
    selectedTab: Binding<TabList>,
    listingButtons: Binding<SaveButtons>,
    letterButtons: Binding<CoverLetterButtons>,
    resumeButtons: Binding<ResumeButtons>,
    refresh: Binding<Bool>
) -> some ToolbarContent {
    UnifiedToolbar(
        selectedTab: selectedTab,
        listingButtons: listingButtons,
        letterButtons: letterButtons,
        resumeButtons: resumeButtons,
        refresh: refresh
    )
}

struct UnifiedToolbar: ToolbarContent {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(AppState.self) private var appState: AppState
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
    
    @Binding var selectedTab: TabList
    @Binding var listingButtons: SaveButtons
    @Binding var letterButtons: CoverLetterButtons
    @Binding var resumeButtons: ResumeButtons
    @Binding var refresh: Bool
    
    @State private var showNewAppSheet = false
    @State private var showApplicationReviewSheet = false
    @State private var showResumeReviewSheet = false
    @State private var showClarifyingQuestionsSheet = false
    @State private var showChooseBestCoverLetterSheet = false
    @State private var showMultiModelChooseBestSheet = false
    @State private var isGeneratingResume = false
    @State private var isGeneratingCoverLetter = false
    @State private var clarifyingQuestions: [ClarifyingQuestion] = []
    
    @AppStorage("scrapingDogApiKey") var scrapingDogApiKey: String = "none"
    
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
    
    var body: some ToolbarContent {
        // Left side - Navigation items (sidebar handled automatically by NavigationSplitView)
        
        if let selApp = jobAppStore.selectedApp {
            ToolbarItem(placement: .navigation) { 
                selApp.statusTag 
            }
            
            ToolbarItem(placement: .navigation) {
                VStack(alignment: .leading) {
                    Text(selApp.jobPosition).font(.headline).lineLimit(1)
                    Text(selApp.companyName).font(.caption).lineLimit(1)
                }
            }
        }
        
        // Center spacer
        ToolbarItem(placement: .principal) { 
            Spacer() 
        }
        
        // Right side - All action buttons  
        ToolbarItemGroup(placement: .primaryAction) {
            HStack(spacing: 8) {
                // Show Sources
                Button(action: {
                    // TODO: Implement show sources functionality
                }) {
                    Image(systemName: "newspaper")
                }
                .help("Show Sources")
                
                // Job Management
                RecommendJobButton()
                
                Button(action: {
                    showNewAppSheet = true
                }) {
                    Image(systemName: "note.text.badge.plus")
                }
                .help("New Job Application")
                .sheet(isPresented: $showNewAppSheet) {
                    NewAppSheetView(isPresented: $showNewAppSheet)
                        .environment(jobAppStore)
                }
                
                Divider()
                
                // Resume Operations
                Button(action: {
                    if let resume = selectedResumeBinding.wrappedValue {
                        isGeneratingResume = true
                        // Trigger AI resume generation
                    }
                }) {
                    if isGeneratingResume {
                        Image(systemName: "wand.and.rays")
                            .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing)
                    } else {
                        Image(systemName: "wand.and.sparkles")
                    }
                }
                .help("Create Resume Revisions")
                .disabled(selectedResumeBinding.wrappedValue?.rootNode == nil)
                
                Button(action: {
                    clarifyingQuestions = []
                    showClarifyingQuestionsSheet = true
                }) {
                    if isGeneratingResume {
                        Image("custom.wand.and.rays.inverse.badge.questionmark")
                            .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing)
                    } else {
                        Image("custom.wand.and.sparkles.badge.questionmark")
                    }
                }
                .help("Create Resume Revisions with Clarifying Questions")
                .disabled(selectedResumeBinding.wrappedValue?.rootNode == nil)
                .sheet(isPresented: $showClarifyingQuestionsSheet) {
                    ClarifyingQuestionsSheet(
                        questions: clarifyingQuestions,
                        isPresented: $showClarifyingQuestionsSheet,
                        onSubmit: { answers in
                            showClarifyingQuestionsSheet = false
                        }
                    )
                }
                
                Button(action: {
                    showResumeReviewSheet = true
                }) {
                    Image(systemName: "character.magnify")
                }
                .help("AI Resume Review")
                .disabled(selectedResumeBinding.wrappedValue == nil)
                .sheet(isPresented: $showResumeReviewSheet) {
                    ResumeReviewSheet(selectedResume: selectedResumeBinding)
                }
                
                Divider()
                
                // Cover Letter Operations
                Button(action: {
                    if let cL = coverLetterStore.cL {
                        isGeneratingCoverLetter = true
                        let newCL = coverLetterStore.createDuplicate(letter: cL)
                        newCL.currentMode = .generate
                        coverLetterStore.cL = newCL
                    }
                }) {
                    Image("custom.append.page.badge.plus")
                }
                .help("Generate Cover Letter")
                .disabled(jobAppStore.selectedApp?.selectedRes == nil)
                
                Button(action: {
                    letterButtons.showBatchGeneration = true
                }) {
                    Image(systemName: "square.stack.3d.up.fill")
                }
                .help("Batch Cover Letter Operations")
                .disabled(jobAppStore.selectedApp?.selectedRes == nil)
                
                Button(action: {
                    showChooseBestCoverLetterSheet = true
                }) {
                    Image(systemName: "medal")
                }
                .help("Choose Best Cover Letter")
                .disabled((jobAppStore.selectedApp?.coverLetters.filter { $0.generated }.count ?? 0) < 2)
                .sheet(isPresented: $showChooseBestCoverLetterSheet) {
                    if let jobApp = jobAppStore.selectedApp {
                        ChooseBestCoverLetterSheet(jobApp: jobApp)
                    }
                }
                
                Button(action: {
                    showMultiModelChooseBestSheet = true
                }) {
                    Image("custom.medal.square.stack")
                }
                .help("Multi-model Choose Best Cover Letter")
                .disabled((jobAppStore.selectedApp?.coverLetters.filter { $0.generated }.count ?? 0) < 2)
                .sheet(isPresented: $showMultiModelChooseBestSheet) {
                    if let jobApp = jobAppStore.selectedApp,
                       let currentCoverLetter = coverLetterStore.cL {
                        MultiModelChooseBestCoverLetterSheet(coverLetter: .constant(currentCoverLetter))
                    }
                }
                
                TTSButton()
                    .disabled(coverLetterStore.cL?.generated != true)
                
                Divider()
                
                // Application Review
                Button(action: {
                    showApplicationReviewSheet = true
                }) {
                    Image(systemName: "mail.and.text.magnifyingglass")
                }
                .help("Review Application")
                .disabled(
                    jobAppStore.selectedApp?.selectedRes == nil ||
                    jobAppStore.selectedApp?.selectedCover == nil ||
                    jobAppStore.selectedApp?.selectedCover?.generated != true
                )
                .sheet(isPresented: $showApplicationReviewSheet) {
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
                
                Button(action: {
                    resumeButtons.showResumeInspector.toggle()
                }) {
                    Image(systemName: "sidebar.right")
                }
                .help("Show Resume Inspector")
                .disabled(selectedTab != .resume)
            }
        }
    }
}

// TTS Button extracted from existing implementation
struct TTSButton: View {
    @Environment(CoverLetterStore.self) private var coverLetterStore
    @AppStorage("ttsEnabled") var ttsEnabled: Bool = false
    
    var body: some View {
        if ttsEnabled {
            // Implementation would come from existing TTS button
            Button(action: {
                // TTS action
            }) {
                Image(systemName: "speaker.wave.2")
            }
            .help("Read Cover Letter")
        }
    }
}

// Placeholder for Choose Best Cover Letter Sheet
struct ChooseBestCoverLetterSheet: View {
    let jobApp: JobApp
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack {
            Text("Choose Best Cover Letter")
                .font(.title2)
                .padding()
            
            // Implementation would include model selection and processing
            
            Button("Close") {
                dismiss()
            }
            .padding()
        }
        .frame(width: 600, height: 400)
    }
}