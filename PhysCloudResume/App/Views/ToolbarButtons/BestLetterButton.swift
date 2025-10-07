// PhysCloudResume/App/Views/ToolbarButtons/BestLetterButton.swift
import SwiftUI

struct BestLetterButton: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(LLMFacade.self) private var llmFacade
    
    @State private var showBestLetterModelSheet = false
    @State private var selectedBestLetterModel = ""
    @State private var isProcessingBestLetter = false
    @State private var showBestLetterAlert = false
    @State private var bestLetterResult: BestCoverLetterResponse?
    
    var body: some View {
        Button(action: {
            showBestLetterModelSheet = true
        }) {
            if isProcessingBestLetter {
                Label("Best Letter", systemImage: "gearshape")
                    .symbolEffect(.rotate, options: .repeating)
                    .font(.system(size: 14, weight: .light))
            } else {
                Label("Best Letter", systemImage: "medal")
                    .font(.system(size: 14, weight: .light))
            }
        }
        .buttonStyle( .automatic )
        .help("Choose Best Cover Letter")
        .disabled((jobAppStore.selectedApp?.coverLetters.filter { $0.generated }.count ?? 0) < 2)
        .sheet(isPresented: $showBestLetterModelSheet) {
            ModelSelectionSheet(
                title: "Choose Model for Best Cover Letter Selection",
                requiredCapability: .structuredOutput,
                operationKey: "best_letter",
                isPresented: $showBestLetterModelSheet,
                onModelSelected: { modelId in
                    selectedBestLetterModel = modelId
                    showBestLetterModelSheet = false
                    isProcessingBestLetter = true
                    
                    Task {
                        await startBestLetterSelection(modelId: modelId)
                    }
                }
            )
        }
        .alert("Best Cover Letter Selection", isPresented: $showBestLetterAlert) {
            Button("OK") {
                if let result = bestLetterResult,
                   let bestUuid = result.bestLetterUuid,
                   let uuid = UUID(uuidString: bestUuid),
                   let jobApp = jobAppStore.selectedApp,
                   let selectedLetter = jobApp.coverLetters.first(where: { $0.id == uuid }) {
                    jobApp.selectedCover = selectedLetter
                    Logger.debug("📝 Updated selected cover letter to: \(selectedLetter.sequencedName)")
                }
            }
        } message: {
            if let result = bestLetterResult {
                Text("Analysis: \(result.strengthAndVoiceAnalysis)\n\nVerdict: \(result.verdict)")
            }
        }
    }
    
    @MainActor
    private func startBestLetterSelection(modelId: String) async {
        guard let jobApp = jobAppStore.selectedApp else {
            isProcessingBestLetter = false
            return
        }
        
        do {
            let service = BestCoverLetterService(llmFacade: llmFacade)
            let result = try await service.selectBestCoverLetter(
                jobApp: jobApp, 
                modelId: modelId
            )
            
            isProcessingBestLetter = false
            bestLetterResult = result
            showBestLetterAlert = true
            
            Logger.debug("✅ Best cover letter selection completed: \(result.bestLetterUuid ?? "score voting mode")")
            
        } catch {
            isProcessingBestLetter = false
            Logger.error("Error in best letter selection: \(error.localizedDescription)")
            
            bestLetterResult = BestCoverLetterResponse(
                strengthAndVoiceAnalysis: "Error occurred during selection",
                bestLetterUuid: "",
                verdict: "Selection failed: \(error.localizedDescription)"
            )
            showBestLetterAlert = true
        }
    }
}
