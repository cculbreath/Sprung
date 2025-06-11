//
//  CoverLetterView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/12/24.
//  Simplified after removing legacy button management
//

import SwiftUI

struct CoverLetterView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
    @Environment(AppState.self) private var appState: AppState
    
    @Binding var showCoverLetterInspector: Bool
    @State private var isEditing = false

    var body: some View {
        HStack {
            contentView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .inspectorColumnWidth(min: 250, ideal: 300, max: 400)
        .inspector(isPresented: $showCoverLetterInspector) {
            CoverLetterInspectorView(isEditing: $isEditing)
        }
    }

    @ViewBuilder
    private func contentView() -> some View {
        @Bindable var coverLetterStore = coverLetterStore
        @Bindable var jobAppStore = jobAppStore

        if let jobApp = jobAppStore.selectedApp {
            VStack {
                CoverLetterContentView(
                    jobApp: jobApp,
                    isEditing: $isEditing
                )
            }
        } else {
            Text(jobAppStore.selectedApp?.selectedRes == nil ? "job app nil" : "No nil fail")
                .onAppear {
                    if jobAppStore.selectedApp == nil {
                    } else if jobAppStore.selectedApp?.selectedRes == nil {}
                }
        }
    }
}


struct CoverLetterContentView: View {
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(AppState.self) private var appState: AppState
    @Bindable var jobApp: JobApp
    @Binding var isEditing: Bool

    var body: some View {
        @Bindable var coverLetterStore = coverLetterStore
        @Bindable var jobAppStore = jobAppStore
        @Bindable var bindStore = jobAppStore
        
        if let app = jobAppStore.selectedApp {
            if app.coverLetters.isEmpty {
                // Show encourage generation view when no cover letters exist
                VStack(spacing: 24) {
                    Spacer()
                    
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text.badge.plus")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text("No cover letters yet")
                            .font(.title2)
                            .fontWeight(.medium)
                        
                        Text("Generate your first cover letter to get started")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 20) {
                        // Generate Cover Letter Button (1.5x bigger)
                        GenerateCoverLetterButtonView()
                        
                        // Batch Cover Letter Button (1.5x bigger)
                        BatchCoverLetterButtonView()
                    }
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let cL = app.selectedCover {
                @Bindable var bindApp = app
                VStack(alignment: .leading, spacing: 8) {
                    // Cover letter picker
                    HStack {
                        CoverLetterPicker(
                            coverLetters: bindApp.coverLetters,
                            selection: $bindApp.selectedCover,
                            includeNoneOption: false,
                            label: ""
                        )
                        .onChange(of: bindApp.selectedCover) { _, newSelection in
                            // Sync with coverLetterStore when selection changes
                            coverLetterStore.cL = newSelection
                        }
                        .padding()
                        
                        Spacer()
                    }
                    // Toggle between editing raw content and PDF preview
                    if isEditing {
                        Text("Editing - Last modified \(cL.modDate)")
                            .font(.caption)
                            .padding(.horizontal)
                        // Editable cover letter name (only the part after the colon)
                        let nameBinding = Binding<String>(
                            get: { cL.editableName },
                            set: { newNameContent in
                                cL.setEditableName(newNameContent)
                                cL.moddedDate = Date()
                            }
                        )
                        TextField("Cover Letter Name", text: nameBinding)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding(.horizontal)
                        // Bind to the cover letter content for editing
                        let contentBinding = Binding<String>(
                            get: { cL.content },
                            set: { newText in
                                cL.content = newText
                                cL.moddedDate = Date()
                            }
                        )
                        TextEditor(text: contentBinding)
                            .frame(maxHeight: .infinity)
                            .padding(.horizontal)
                    } else {
                        Text("PDF Preview - Generated \(cL.modDate)")
                            .font(.caption)
                            .italic()

                        if cL.generated {
                            CoverLetterPDFView(
                                coverLetter: cL,
                                applicant: Applicant()
                            )
                            .frame(maxHeight: .infinity)
                            .id(cL.id)
                            .onChange(of: bindApp.selectedCover) { _, _ in
                            }
                        } else {
                            EmptyView()
                                .frame(maxHeight: .infinity)
                        }
                    }
                }
            } else {
                EmptyView()
            }
        } else {
            EmptyView()
        }
    }
}

// MARK: - Generate Cover Letter Button Component
struct GenerateCoverLetterButtonView: View {
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
                Text("Generate Cover Letter")
                    .font(.system(size: 16, weight: .medium))
            } icon: {
                if isGeneratingCoverLetter {
                    Image("custom.append.page.badge.plus")
                        .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing)
                        .font(.system(size: 20, weight: .light))
                } else {
                    Image("custom.append.page.badge.plus")
                        .font(.system(size: 20, weight: .light))
                }
            }
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
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

// MARK: - Batch Cover Letter Button Component
struct BatchCoverLetterButtonView: View {
    @Environment(AppState.self) private var appState: AppState
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
    @State private var showBatchCoverLetterSheet = false
    
    var body: some View {
        Button(action: {
            showBatchCoverLetterSheet = true
        }) {
            Label {
                Text("Batch Generation")
                    .font(.system(size: 16, weight: .medium))
            } icon: {
                Image(systemName: "square.stack.3d.down.right")
                    .font(.system(size: 20, weight: .light))
            }
        }
        .controlSize(.large)
        .buttonStyle(.bordered)
        .disabled(jobAppStore.selectedApp?.selectedRes == nil)
        .sheet(isPresented: $showBatchCoverLetterSheet) {
            BatchCoverLetterView()
                .environment(appState)
                .environment(jobAppStore)
                .environment(coverLetterStore)
        }
    }
}
