//
//  CoverLetterView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/12/24.
//

import SwiftUI

struct CoverLetterView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore

    @Binding var buttons: CoverLetterButtons
    @State private var selectedInspectorTab: InspectorTab = .references // State to manage selected tab

    var body: some View {
        contentView()
    }

    @ViewBuilder
    private func contentView() -> some View {
        @Bindable var coverLetterStore = coverLetterStore
        @Bindable var jobAppStore = jobAppStore

        if let jobApp = jobAppStore.selectedApp {
            VStack {
                CoverLetterContentView(
                    jobApp: jobApp,
                    buttons: $buttons
                )
            }
            .inspector(isPresented: $buttons.showInspector) {
                if coverLetterStore.cL != nil {
                    VStack(alignment: .leading) {
                        Picker("", selection: $selectedInspectorTab) {
                            Text("References").tag(InspectorTab.references)
                            Text("Revisions").tag(InspectorTab.revisions)
                        }
                        .pickerStyle(SegmentedPickerStyle())

                        switch selectedInspectorTab {
                        case .references:
                            CoverRefView()
                        case .revisions:
                            CoverRevisionsView(buttons: $buttons)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding()
                } else {
                    EmptyView()
                }
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

// Enum to manage the tab selection
enum InspectorTab {
    case references
    case revisions
}

struct CoverLetterContentView: View {
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Bindable var jobApp: JobApp
    @Binding var buttons: CoverLetterButtons
    @State private var isHoveringDelete = false
    @State private var isHoveringEdit = false

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
                        coverLetters: bindApp.coverLetters.sorted(by: { $0.moddedDate < $1.moddedDate }),
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
                    Button(action: { buttons.isEditing.toggle() }) {
                        HStack {
                            Image(systemName: buttons.isEditing ? "doc.text.viewfinder" : "pencil")
                                .foregroundColor(isHoveringEdit ? .accentColor : .secondary)
                                .font(.system(size: 14))
                            Text(buttons.isEditing ? "Preview" : "Edit")
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
                    .disabled(!buttons.canEdit)

                    if buttons.runRequested {
                        ProgressView()
                    } else {
                        EmptyView()
                    }
                }
                // Toggle between editing raw content and PDF preview
                if buttons.isEditing {
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
        }
    }
}
