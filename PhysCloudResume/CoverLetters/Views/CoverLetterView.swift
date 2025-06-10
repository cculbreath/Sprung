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
    @Bindable var jobApp: JobApp
    @Binding var isEditing: Bool

    var body: some View {
        @Bindable var coverLetterStore = coverLetterStore
        @Bindable var jobAppStore = jobAppStore
        @Bindable var bindStore = jobAppStore
        if let app = jobAppStore.selectedApp,
           let cL = jobAppStore.selectedApp?.selectedCover
        {
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
    }
}
