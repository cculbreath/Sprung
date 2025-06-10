// PhysCloudResume/App/Views/ToolbarButtons/CoverLetterReviseButton.swift
import SwiftUI

struct CoverLetterReviseButton: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
    
    @State private var showReviseCoverLetterSheet = false
    
    var body: some View {
        Button(action: {
            showReviseCoverLetterSheet = true
        }) {
            Label {
                Text("Revise")
            } icon: {
                Image(systemName: "text.append")
                    .font(.system(size: 14, weight: .light))
            }
        }
        .buttonStyle(.automatic)
        .help("Revise Cover Letter")
        .disabled(jobAppStore.selectedApp?.selectedCover?.generated != true)
        .sheet(isPresented: $showReviseCoverLetterSheet) {
            if let coverLetter = jobAppStore.selectedApp?.selectedCover {
                ReviseCoverLetterView(
                    coverLetter: coverLetter,
                    onRevise: { modelId, operation, feedback in
                        showReviseCoverLetterSheet = false
                        
                        Task {
                            await reviseCoverLetter(
                                modelId: modelId,
                                operation: operation,
                                feedback: feedback
                            )
                        }
                    }
                )
            }
        }
    }
    
    @MainActor
    private func reviseCoverLetter(modelId: String, operation: CoverLetterPrompts.EditorPrompts, feedback: String) async {
        guard let coverLetter = jobAppStore.selectedApp?.selectedCover,
              let resume = jobAppStore.selectedApp?.selectedRes else {
            return
        }
        
        do {
            let targetLetter: CoverLetter
            if coverLetter.generated {
                targetLetter = coverLetterStore.createDuplicate(letter: coverLetter)
                targetLetter.generated = false
                targetLetter.editorPrompt = operation
                
                jobAppStore.selectedApp?.selectedCover = targetLetter
                coverLetterStore.cL = targetLetter
            } else {
                targetLetter = coverLetter
                targetLetter.editorPrompt = operation
            }
            
            targetLetter.currentMode = operation == .custom ? .revise : .rewrite
            
            _ = try await CoverLetterService.shared.reviseCoverLetter(
                coverLetter: targetLetter,
                resume: resume,
                modelId: modelId,
                feedback: feedback,
                editorPrompt: operation
            )
            
            Logger.debug("✅ Cover letter revision completed successfully")
            
        } catch {
            Logger.error("Error during cover letter revision: \(error.localizedDescription)")
        }
    }
}
