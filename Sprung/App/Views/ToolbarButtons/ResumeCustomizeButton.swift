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
    
    var body: some View {
        Button(action: {
            selectedTab = .resume
            showCustomizeModelSheet = true
        }) {
            let isBusy = isGeneratingResume || resumeReviseViewModel.isWorkflowBusy(.customize)
            if isBusy {
                Label("Customize", systemImage: "wand.and.rays").fontWeight(.bold).foregroundColor(.blue)
                    .symbolEffect(.variableColor.iterative.nonReversing)
                    .font(.system(size: 14, weight: .light))
            } else {
                Label("Customize", systemImage: "wand.and.sparkles")
                    .font(.system(size: 14, weight: .light))
            }
        }
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
            // Defensive check: ensure reasoning modal is not visible before starting workflow
            Logger.debug("🛡️ [ResumeCustomizeButton] Starting fresh workflow with model: \(modelId)")
            reasoningStreamManager.isVisible = false
            reasoningStreamManager.clear()
            
            try await resumeReviseViewModel.startFreshRevisionWorkflow(
                resume: resume,
                modelId: modelId,
                workflow: .customize
            )
            
            isGeneratingResume = false
            
        } catch {
            Logger.error("Error in customize workflow: \(error.localizedDescription)")
            isGeneratingResume = false
        }
    }
}
