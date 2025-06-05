//
//  CoverLetterInspectorView.swift
//  PhysCloudResume
//
//  Created on 6/5/2025.
//  Unified inspector view for cover letter sources and revisions

import SwiftUI

struct CoverLetterInspectorView: View {
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
    @Environment(AppState.self) private var appState: AppState
    
    @State private var selectedTab: CoverLetterInspectorTab = .sources
    
    enum CoverLetterInspectorTab: String, CaseIterable {
        case sources = "Sources"
        case revisions = "Revisions"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            Picker("Inspector Tab", selection: $selectedTab) {
                ForEach(CoverLetterInspectorTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top)
            
            // Tab content
            Group {
                switch selectedTab {
                case .sources:
                    CoverLetterRefManagementView()
                case .revisions:
                    CoverLetterRevisionsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 350)
    }
}

struct CoverLetterRevisionsView: View {
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(AppState.self) private var appState: AppState
    
    @State private var selectedRevisionMode: CoverLetterPrompts.EditorPrompts = .improve
    @State private var customFeedback: String = ""
    @State private var isRevising = false
    @State private var showModelSelection = false
    @State private var selectedModelId = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cover Letter Revisions")
                .font(.headline)
                .padding(.horizontal)
            
            if let coverLetter = coverLetterStore.cL,
               let resume = jobAppStore.selectedApp?.selectedRes {
                
                VStack(alignment: .leading, spacing: 12) {
                    // Revision mode picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Revision Type")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Picker("Revision Mode", selection: $selectedRevisionMode) {
                            ForEach(CoverLetterPrompts.EditorPrompts.allCases, id: \.self) { mode in
                                Text(mode.operation.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    // Custom feedback text field (only for custom mode)
                    if selectedRevisionMode == .custom {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Custom Feedback")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            TextEditor(text: $customFeedback)
                                .frame(minHeight: 80)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                    
                    // Revision mode descriptions
                    VStack(alignment: .leading, spacing: 4) {
                        Text("About this revision:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(revisionDescription(for: selectedRevisionMode))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                    
                    Divider()
                    
                    // Revise button
                    Button(action: {
                        showModelSelection = true
                    }) {
                        HStack {
                            if isRevising {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Revising...")
                            } else {
                                Image(systemName: "wand.and.stars")
                                Text(selectedRevisionMode == .custom ? "Revise" : "Rewrite")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRevising || !coverLetter.generated || (selectedRevisionMode == .custom && customFeedback.isEmpty))
                    
                    if !coverLetter.generated {
                        Text("Cover letter must be generated before it can be revised")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding(.horizontal)
                
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.title)
                        .foregroundColor(.secondary)
                    
                    Text("No cover letter selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(alignment: .center)
            }
            
            Spacer()
        }
        .sheet(isPresented: $showModelSelection) {
            ModelSelectionSheet(
                title: "Choose Model for Revision",
                requiredCapability: nil, // Cover letter revision can work with any model
                isPresented: $showModelSelection,
                onModelSelected: { modelId in
                    selectedModelId = modelId
                    showModelSelection = false
                    
                    Task {
                        await performRevision(modelId: modelId)
                    }
                }
            )
        }
    }
    
    private func revisionDescription(for mode: CoverLetterPrompts.EditorPrompts) -> String {
        switch mode {
        case .improve:
            return "Identifies and improves content and writing quality"
        case .zissner:
            return "Applies William Zinsser's 'On Writing Well' editing techniques"
        case .mimic:
            return "Rewrites to match the tone and style of your writing samples"
        case .custom:
            return "Incorporates your specific feedback and instructions"
        }
    }
    
    @MainActor
    private func performRevision(modelId: String) async {
        guard let coverLetter = coverLetterStore.cL,
              let resume = jobAppStore.selectedApp?.selectedRes else {
            return
        }
        
        isRevising = true
        
        do {
            // Create a duplicate if the current letter is already generated
            let targetLetter: CoverLetter
            if coverLetter.generated {
                targetLetter = coverLetterStore.createDuplicate(letter: coverLetter)
                targetLetter.generated = false
                targetLetter.editorPrompt = selectedRevisionMode
                
                // Update selected cover letter
                jobAppStore.selectedApp?.selectedCover = targetLetter
                coverLetterStore.cL = targetLetter
            } else {
                targetLetter = coverLetter
                targetLetter.editorPrompt = selectedRevisionMode
            }
            
            // Set the current mode for the prompt generation
            targetLetter.currentMode = selectedRevisionMode == .custom ? .revise : .rewrite
            
            // Perform the revision
            let feedback = selectedRevisionMode == .custom ? customFeedback : ""
            _ = try await CoverLetterService.shared.reviseCoverLetter(
                coverLetter: targetLetter,
                resume: resume,
                modelId: modelId,
                feedback: feedback,
                editorPrompt: selectedRevisionMode
            )
            
            // Clear custom feedback for next time
            if selectedRevisionMode == .custom {
                customFeedback = ""
            }
            
            Logger.debug("✅ Cover letter revision completed successfully")
            
        } catch {
            Logger.error("Error during cover letter revision: \(error.localizedDescription)")
            // TODO: Show error alert to user
        }
        
        isRevising = false
    }
}