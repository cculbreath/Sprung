// PhysCloudResume/App/Views/ToolbarButtons/ResumeCustomizeButton.swift
import SwiftUI

struct ResumeCustomizeButton: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    
    @Binding var selectedTab: TabList
    var resumeReviseViewModel: ResumeReviseViewModel?
    
    @State private var isGeneratingResume = false
    @State private var showCustomizeModelSheet = false
    @State private var selectedCustomizeModel = ""
    
    var body: some View {
        Button(action: {
            selectedTab = .resume
            showCustomizeModelSheet = true
        }) {
            if isGeneratingResume {
                Label("Customize", systemImage: "wand.and.rays").fontWeight(.bold).foregroundColor(.blue)
                    .symbolEffect(.variableColor.iterative.nonReversing)
                    .font(.system(size: 14, weight: .light))
            } else {
                Label("Customize", systemImage: "wand.and.sparkles")
                    .font(.system(size: 14, weight: .light))
            }
        }
        .buttonStyle(.automatic)
        .help("Create Resume Revisions")
        .disabled(jobAppStore.selectedApp?.selectedRes?.rootNode == nil)
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
    }
    
    @MainActor 
    private func startCustomizeWorkflow(modelId: String) async {
        guard let jobApp = jobAppStore.selectedApp,
              let resume = jobApp.selectedRes else {
            isGeneratingResume = false
            return
        }
        
        do {
            guard let viewModel = resumeReviseViewModel else {
                Logger.error("ResumeReviseViewModel not available")
                isGeneratingResume = false
                return
            }
            
            try await viewModel.startFreshRevisionWorkflow(
                resume: resume,
                modelId: modelId
            )
            
            isGeneratingResume = false
            
        } catch {
            Logger.error("Error in customize workflow: \(error.localizedDescription)")
            isGeneratingResume = false
        }
    }
}
