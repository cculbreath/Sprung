// Sprung/App/Views/ToolbarButtons/ResumeCustomizeButton.swift
import SwiftUI
struct ResumeCustomizeButton: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(ResumeReviseViewModel.self) private var resumeReviseViewModel: ResumeReviseViewModel
    @Environment(ReasoningStreamManager.self) private var reasoningStreamManager: ReasoningStreamManager
    @Binding var selectedTab: TabList
    @State private var isGeneratingResume = false
    @State private var showCustomizeModelSheet = false
    @State private var selectedCustomizeModel = ""
    @State private var workflowTask: Task<Void, Never>?
    var body: some View {
        // Headless: no visible content. Sheets and notification listeners
        // remain in the view hierarchy for toolbar/menu-driven workflows.
        Color.clear
            .frame(width: 0, height: 0)
        .sheet(isPresented: $showCustomizeModelSheet) {
            ModelSelectionSheet(
                title: "Choose Model for Resume Customization",
                requiredCapability: .structuredOutput,
                operationKey: "resume_customize",
                isPresented: $showCustomizeModelSheet,
                onModelSelected: { modelId in
                    selectedCustomizeModel = modelId
                    isGeneratingResume = true
                    workflowTask = Task {
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
            Logger.debug("🛡️ [ResumeCustomizeButton] Starting customize workflow with model: \(modelId)")
            reasoningStreamManager.hideAndClear()
            try await resumeReviseViewModel.startFreshRevisionWorkflow(
                resume: resume,
                modelId: modelId,
                workflow: .customize
            )
            if Task.isCancelled {
                isGeneratingResume = false
                return
            }
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
