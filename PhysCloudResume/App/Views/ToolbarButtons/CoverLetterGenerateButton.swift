// PhysCloudResume/App/Views/ToolbarButtons/CoverLetterGenerateButton.swift
import SwiftUI

struct CoverLetterGenerateButton: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
    
    @State private var isGeneratingCoverLetter = false
    @State private var showCoverLetterModelSheet = false
    @State private var selectedCoverLetterModel = ""
    
    var body: some View {
        Button(action: {
            showCoverLetterModelSheet = true
        }) {
            Label {
                Text("Cover Letter")
            } icon: {
                if isGeneratingCoverLetter {
                    Image("custom.append.page.badge.plus")
                        .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing)
                    .font(.system(size: 14, weight: .light))                } else {
                    Image("custom.append.page.badge.plus")
                            .font(.system(size: 14, weight: .light))
                }
            }
        }
        .font(.system(size: 14, weight: .light))
        .buttonStyle( .automatic )
        .help("Generate Cover Letter")
        .disabled(jobAppStore.selectedApp?.selectedRes == nil)
        .sheet(isPresented: $showCoverLetterModelSheet) {
            if let jobApp = jobAppStore.selectedApp {
                GenerateCoverLetterView(
                    jobApp: jobApp,
                    onGenerate: { modelId, selectedRefs, includeResumeRefs in
                        selectedCoverLetterModel = modelId
                        showCoverLetterModelSheet = false
                        isGeneratingCoverLetter = true
                        
                        Task {
                            await generateCoverLetter(
                                modelId: modelId,
                                selectedRefs: selectedRefs,
                                includeResumeRefs: includeResumeRefs
                            )
                        }
                    }
                )
            }
        }
    }
    
    @MainActor
    private func generateCoverLetter(modelId: String, selectedRefs: [CoverRef], includeResumeRefs: Bool) async {
        guard let jobApp = jobAppStore.selectedApp,
              let resume = jobApp.selectedRes else {
            isGeneratingCoverLetter = false
            return
        }
        
        do {
            try await CoverLetterService.shared.generateNewCoverLetter(
                jobApp: jobApp,
                resume: resume,
                modelId: modelId,
                coverLetterStore: coverLetterStore,
                selectedRefs: selectedRefs,
                includeResumeRefs: includeResumeRefs
            )
            
            isGeneratingCoverLetter = false
            
        } catch {
            Logger.error("Error generating cover letter: \(error.localizedDescription)")
            isGeneratingCoverLetter = false
        }
    }
}
