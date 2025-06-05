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

    var body: some View {
        contentView()
            .inspector(isPresented: $showCoverLetterInspector) {
                CoverLetterInspectorView()
            }
    }

    @ViewBuilder
    private func contentView() -> some View {
        @Bindable var coverLetterStore = coverLetterStore
        @Bindable var jobAppStore = jobAppStore

        if let jobApp = jobAppStore.selectedApp {
            VStack {
                CoverLetterContentView(
                    jobApp: jobApp
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
    
    // Local state instead of legacy button state
    @State private var isEditing = false
    @State private var canEdit = true
    @State private var isHoveringDelete = false
    @State private var isHoveringEdit = false
    @State private var isHoveringStar = false

    var body: some View {
        @Bindable var coverLetterStore = coverLetterStore
        @Bindable var jobAppStore = jobAppStore
        @Bindable var bindStore = jobAppStore
        if let app = jobAppStore.selectedApp,
           let cL = jobAppStore.selectedApp?.selectedCover
        {
            @Bindable var bindApp = app
            VStack(alignment: .leading, spacing: 8) {
                // Picker, delete and edit controls
                HStack {
                    CoverLetterPicker(
                        coverLetters: bindApp.coverLetters,
                        selection: $bindApp.selectedCover,
                        includeNoneOption: false,
                        label: ""
                    )
                    .padding()

                    // Delete Button
                    // Delete Button
                    Button(action: { deleteCoverLetter() }) {
                        HStack {
                            Image(systemName: "trash.fill")
                                .foregroundColor(isHoveringDelete ? .red : .secondary)
                                .font(.system(size: 14))
                            Text("Delete")
                                .font(.caption)
                                .foregroundColor(isHoveringDelete ? .red : .secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(isHoveringDelete ? Color.white.opacity(0.4) : Color.clear)
                        .cornerRadius(10)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onHover { hovering in isHoveringDelete = hovering }

                    // Edit/Preview toggle Button
                    Button(action: { isEditing.toggle() }) {
                        HStack {
                            Image(systemName: isEditing ? "doc.text.viewfinder" : "pencil")
                                .foregroundColor(isHoveringEdit ? .accentColor : .secondary)
                                .font(.system(size: 14))
                            Text(isEditing ? "Preview" : "Edit")
                                .font(.caption)
                                .foregroundColor(isHoveringEdit ? .accentColor : .secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(isHoveringEdit ? Color.white.opacity(0.4) : Color.clear)
                        .cornerRadius(10)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onHover { hovering in isHoveringEdit = hovering }
                    .disabled(!canEdit)
                    
                    // Star toggle button for chosen submission draft
                    Button(action: { toggleChosenSubmissionDraft() }) {
                        HStack {
                            Image(systemName: cL.isChosenSubmissionDraft ? "star.fill" : "star")
                                .foregroundColor(isHoveringStar ? .yellow : (cL.isChosenSubmissionDraft ? .yellow : .secondary))
                                .font(.system(size: 14))
                            Text(cL.isChosenSubmissionDraft ? "Chosen" : "Mark as Chosen")
                                .font(.caption)
                                .foregroundColor(isHoveringStar ? .primary : .secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(isHoveringStar ? Color.white.opacity(0.4) : Color.clear)
                        .cornerRadius(10)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onHover { hovering in isHoveringStar = hovering }
                    .disabled(!cL.generated)
                    .help("Mark this cover letter as your chosen submission draft")

                    // Legacy progress indicator removed - progress now handled by UnifiedToolbar
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

    /// Deletes the current cover letter and updates the selectedCover to the most recent generated cover letter.
    private func deleteCoverLetter() {
        guard let selectedCover = jobApp.selectedCover else { return }
        // Delete the selected cover letter
        coverLetterStore.deleteLetter(selectedCover)
        jobApp.selectedCover = nil

        // Select the most recent generated cover letter
        if let mostRecentGenerated = jobApp.coverLetters
            .filter({ $0.generated })
            .sorted(by: { $0.modDate > $1.modDate })
            .first
        {
            jobApp.selectedCover = mostRecentGenerated
        } else if let anyLetter = jobApp.coverLetters.first {
            // If no generated letters exist, select any remaining letter
            jobApp.selectedCover = anyLetter
        } else {
            // If no letters remain, create a new blank one
            coverLetterStore.createBlank(jobApp: jobApp)
        }
    }
    
    /// Toggles the chosen submission draft status
    private func toggleChosenSubmissionDraft() {
        guard let selectedCover = jobApp.selectedCover else { return }
        
        if selectedCover.isChosenSubmissionDraft {
            // Just clear the flag
            selectedCover.isChosenSubmissionDraft = false
        } else {
            // Mark as chosen (this will clear others)
            selectedCover.markAsChosenSubmissionDraft()
        }
    }
}
