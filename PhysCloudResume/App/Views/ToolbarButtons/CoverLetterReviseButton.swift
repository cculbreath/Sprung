// PhysCloudResume/App/Views/ToolbarButtons/CoverLetterReviseButton.swift
import SwiftUI

struct CoverLetterReviseButton: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
    @Environment(CoverLetterService.self) private var coverLetterService: CoverLetterService
    
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
        .buttonStyle( .automatic )
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
        .onReceive(NotificationCenter.default.publisher(for: .triggerReviseCoverLetterButton)) { _ in
            // Programmatically trigger the button action (from menu commands)
            showReviseCoverLetterSheet = true
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
            let isNewRevision = coverLetter.generated
            
            if isNewRevision {
                // For generated letters, we'll create a duplicate AFTER successful generation
                // For now, work with a temporary in-memory copy
                targetLetter = CoverLetter(
                    enabledRefs: coverLetter.enabledRefs,
                    jobApp: coverLetter.jobApp
                )
                targetLetter.includeResumeRefs = coverLetter.includeResumeRefs
                targetLetter.content = coverLetter.content
                targetLetter.generated = false
                targetLetter.editorPrompt = operation
                targetLetter.encodedMessageHistory = coverLetter.encodedMessageHistory
                targetLetter.currentMode = operation == .custom ? .revise : .rewrite
                
                // Don't add to store yet - wait for successful generation
            } else {
                // For existing ungenerated letters, update in place
                targetLetter = coverLetter
                targetLetter.editorPrompt = operation
                targetLetter.currentMode = operation == .custom ? .revise : .rewrite
            }
            
            // Try to generate the revision
            let generatedContent = try await coverLetterService.reviseCoverLetter(
                coverLetter: targetLetter,
                resume: resume,
                modelId: modelId,
                feedback: feedback,
                editorPrompt: operation
            )
            
            // Only if generation was successful, persist the letter
            if isNewRevision && !generatedContent.isEmpty {
                // Now create the actual duplicate that will be persisted
                let persistedLetter = coverLetterStore.createDuplicate(letter: coverLetter)
                persistedLetter.content = generatedContent
                persistedLetter.generated = true
                persistedLetter.editorPrompt = operation
                persistedLetter.currentMode = targetLetter.currentMode
                persistedLetter.generationModel = modelId
                persistedLetter.moddedDate = Date()
                
                // Update the name to include the revision type
                let baseModelName = AIModels.friendlyModelName(for: modelId) ?? modelId
                let revisionName = "\(baseModelName) - \(operation.operation.rawValue)"
                persistedLetter.setEditableName(revisionName)
                
                // Set as selected
                jobAppStore.selectedApp?.selectedCover = persistedLetter
                coverLetterStore.cL = persistedLetter
            }
            
            Logger.debug("✅ Cover letter revision completed successfully")
            
        } catch {
            Logger.error("Error during cover letter revision: \(error.localizedDescription)")
            // If we were working on a new revision, no draft was created
            // If we were updating an existing draft, it remains unchanged
        }
    }
}
