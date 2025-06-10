// PhysCloudResume/App/Views/ToolbarButtons/BestJobButton.swift
import SwiftUI

struct BestJobButton: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(AppState.self) private var appState: AppState
    
    @State private var showBestJobModelSheet = false
    @State private var selectedBestJobModel = ""
    @State private var isProcessingBestJob = false
    @State private var showBestJobAlert = false
    @State private var bestJobResult: String?
    
    var body: some View {
        Button(action: {
            showBestJobModelSheet = true
        }) {
            if isProcessingBestJob {
                Label("Best Job", systemImage: "sparkle").fontWeight(.bold).foregroundColor(.blue)
                    .symbolEffect(.rotate.byLayer)
                    .font(.system(size: 14, weight: .light))

            } else {
                Label("Best Job", systemImage: "medal")
                    .font(.system(size: 14, weight: .light))

            }
        }
        .buttonStyle( .automatic )
        .help("Find the best job match based on your qualifications")
        .disabled(isProcessingBestJob)
        .sheet(isPresented: $showBestJobModelSheet) {
            ModelSelectionSheet(
                title: "Choose Model for Job Recommendation",
                requiredCapability: .structuredOutput,
                operationKey: "best_job",
                isPresented: $showBestJobModelSheet,
                onModelSelected: { modelId in
                    selectedBestJobModel = modelId
                    showBestJobModelSheet = false
                    isProcessingBestJob = true
                    
                    Task {
                        await startBestJobRecommendation(modelId: modelId)
                    }
                }
            )
        }
        .alert("Job Recommendation", isPresented: $showBestJobAlert) {
            Button("OK") {
                bestJobResult = nil
            }
        } message: {
            if let result = bestJobResult {
                Text(result)
            }
        }
    }
    
    @MainActor
    private func startBestJobRecommendation(modelId: String) async {
        guard let selectedResume = jobAppStore.selectedApp?.selectedRes else {
            isProcessingBestJob = false
            bestJobResult = "Please select a resume first"
            showBestJobAlert = true
            return
        }

        do {
            let service = JobRecommendationService(llmService: LLMService.shared)
            
            let (jobId, reason) = try await service.fetchRecommendation(
                jobApps: jobAppStore.jobApps,
                resume: selectedResume,
                modelId: modelId
            )

            if let recommendedJob = jobAppStore.jobApps.first(where: { $0.id == jobId }) {
                jobAppStore.selectedApp = recommendedJob
                appState.recommendedJobId = jobId
                bestJobResult = "Recommended: \(recommendedJob.jobPosition) at \(recommendedJob.companyName)\n\nReason: \(reason)"
                showBestJobAlert = true
            } else {
                bestJobResult = "Recommended job not found"
                showBestJobAlert = true
            }

            isProcessingBestJob = false
            
        } catch {
            Logger.error("JobRecommendation Error: \(error)")
            
            if let llmError = error as? LLMError {
                switch llmError {
                case .unauthorized(let modelId):
                    bestJobResult = "Access denied for model '\(modelId)'.\n\nThis model may require special authorization or billing setup. Try using a different model like GPT-4.1 instead."
                default:
                    bestJobResult = "Error: \(error.localizedDescription)"
                }
            } else {
                bestJobResult = "Error: \(error.localizedDescription)"
            }
            
            showBestJobAlert = true
            isProcessingBestJob = false
        }
    }
}
