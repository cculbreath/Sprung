// Sprung/App/Views/ToolbarButtons/ResumeCustomizeButton.swift
import SwiftUI
struct ResumeCustomizeButton: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(ResumeReviseViewModel.self) private var resumeReviseViewModel: ResumeReviseViewModel
    @Environment(ReasoningStreamManager.self) private var reasoningStreamManager: ReasoningStreamManager
    @Environment(CoverRefStore.self) private var coverRefStore: CoverRefStore
    @Binding var selectedTab: TabList
    @State private var isGeneratingResume = false
    @State private var showCustomizeModelSheet = false
    @State private var selectedCustomizeModel = ""
    var body: some View {
        Button(action: {
            selectedTab = .resume
            showCustomizeModelSheet = true
        }, label: {
            let isBusy = isGeneratingResume || resumeReviseViewModel.isWorkflowBusy(.customize)
            if isBusy {
                Label("Customize", systemImage: "wand.and.rays").fontWeight(.bold).foregroundColor(.blue)
                    .symbolEffect(.variableColor.iterative.nonReversing)
                    .font(.system(size: 14, weight: .light))
            } else {
                Label("Customize", systemImage: "wand.and.sparkles")
                    .font(.system(size: 14, weight: .light))
            }
        })
        .buttonStyle( .automatic )
        .help("Create Resume Revisions (requires nodes marked for AI revision)")
        .disabled(jobAppStore.selectedApp == nil ||
                  jobAppStore.selectedApp?.selectedRes?.rootNode == nil ||
                  !(jobAppStore.selectedApp?.selectedRes?.hasUpdatableNodes == true))
        .sheet(isPresented: $showCustomizeModelSheet) {
            ModelSelectionSheet(
                title: "Choose Model for Resume Customization",
                requiredCapability: .structuredOutput,
                operationKey: "resume_customize",
                isPresented: $showCustomizeModelSheet,
                onModelSelected: { modelId in
                    selectedCustomizeModel = modelId
                    isGeneratingResume = true
                    Task {
                        await startCustomizeWorkflow(modelId: modelId)
                    }
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerCustomizeButton)) { _ in
            // Programmatically trigger the button action (from menu commands)
            showCustomizeModelSheet = true
        }
    }
    @MainActor
    private func startCustomizeWorkflow(modelId: String) async {
        guard let jobApp = jobAppStore.selectedApp,
              let resume = jobApp.selectedRes else {
            isGeneratingResume = false
            return
        }
        do {
            Logger.debug("🛡️ [ResumeCustomizeButton] Starting parallel workflow with model: \(modelId)")
            reasoningStreamManager.hideAndClear()
            try await resumeReviseViewModel.startParallelRevisionWorkflow(
                resume: resume,
                modelId: modelId,
                clarifyingQA: nil,
                coverRefStore: coverRefStore
            )
            isGeneratingResume = false
        } catch {
            Logger.error("Error in customize workflow: \(error.localizedDescription)")
            // Show error to user in the reasoning window
            let userMessage = parseUserFriendlyError(error)
            reasoningStreamManager.showError(userMessage)
            isGeneratingResume = false
        }
    }

    private func parseUserFriendlyError(_ error: Error) -> String {
        let errorString = String(describing: error)
        // Check for common API errors
        if errorString.contains("401") || errorString.lowercased().contains("unauthorized") ||
           errorString.lowercased().contains("api key") {
            return "API key error: Please check your OpenRouter API key in Settings."
        } else if errorString.contains("429") || errorString.lowercased().contains("rate limit") {
            return "Rate limit exceeded. Please wait a moment and try again."
        } else if errorString.contains("500") || errorString.contains("502") || errorString.contains("503") {
            return "The AI service is temporarily unavailable. Please try again later."
        } else if errorString.lowercased().contains("network") || errorString.lowercased().contains("connection") {
            return "Network error. Please check your internet connection."
        } else if errorString.lowercased().contains("invalid_json_schema") || errorString.lowercased().contains("invalid schema") {
            return "Schema configuration error. This model may not support structured output properly. Try a different model."
        } else if errorString.contains("400") {
            return "Invalid request. The selected model may not support this operation. Try a different model."
        }
        // Default: show the localized description
        return error.localizedDescription
    }
}
