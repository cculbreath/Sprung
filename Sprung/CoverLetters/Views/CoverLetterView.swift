//
//  CoverLetterView.swift
//  Sprung
//
//  Created by Christopher Culbreath on 9/12/24.
//  Simplified after removing legacy button management
//

import SwiftUI

struct CoverLetterView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
    
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

        if jobAppStore.selectedApp != nil {
            VStack {
                CoverLetterContentView(
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
    @Environment(ApplicantProfileStore.self) private var applicantProfileStore: ApplicantProfileStore
    @Binding var isEditing: Bool

    var body: some View {
        @Bindable var coverLetterStore = coverLetterStore
        @Bindable var jobAppStore = jobAppStore
        @Bindable var bindStore = jobAppStore
        
        if let app = jobAppStore.selectedApp {
            @Bindable var bindApp = app
            let selectableLetters = bindApp.coverLetters.filter { $0.generated || !$0.content.isEmpty }
            let hasGeneratedLetters = app.coverLetters.contains(where: \.generated)

            VStack(spacing: 0) {
                CoverLetterActionsBar(
                    coverLetters: selectableLetters,
                    selection: $bindApp.selectedCover
                )
                Divider()

                if !hasGeneratedLetters {
                    // Show encourage generation view when no cover letters exist
                    VStack(spacing: 40) {
                        VStack(spacing: 24) {
                            // Icon with background gradient
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.indigo.opacity(0.1), Color.blue.opacity(0.1)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 140, height: 140)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.indigo.opacity(0.2), lineWidth: 1)
                                    )

                                Image(systemName: "append.page")
                                    .font(.system(size: 60, weight: .light))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [Color.indigo, Color.blue],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .symbolRenderingMode(.hierarchical)
                            }
                            .shadow(color: .indigo.opacity(0.1), radius: 20, x: 0, y: 10)

                            VStack(spacing: 12) {
                                Text("Create Your First Cover Letter")
                                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [Color.primary, Color.primary.opacity(0.8)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )

                                Text("Choose how you'd like to get started")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.top, 40)

                        // Action buttons section
                        VStack(spacing: 16) {
                            if coverLetterStore.isGeneratingCoverLetter {
                                ProgressView("Generating cover letter...")
                                    .scaleEffect(1.2)
                                    .tint(Color.indigo)
                            } else {
                                HStack(spacing: 16) {
                                    // Generate Cover Letter Button
                                    GenerateCoverLetterButtonView()
                                        .frame(maxWidth: 280)

                                    // Batch Cover Letter Button
                                    BatchCoverLetterButtonView()
                                        .frame(maxWidth: 280)
                                }
                            }
                        }

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        // Subtle background pattern
                        ZStack {
                            Color(NSColor.windowBackgroundColor)

                            // Gradient overlay
                            LinearGradient(
                                colors: [
                                    Color.indigo.opacity(0.02),
                                    Color.clear,
                                    Color.blue.opacity(0.02)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                    )
                } else if let cL = app.selectedCover {
                    VStack(alignment: .leading, spacing: 8) {
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
                                    applicant: Applicant(profile: applicantProfileStore.currentProfile())
                                )
                                .frame(maxHeight: .infinity)
                                .id(cL.id)
                                .onChange(of: bindApp.selectedCover) { _, _ in }
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
        } else {
            EmptyView()
        }
    }
}

private struct CoverLetterActionsBar: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
    
    let coverLetters: [CoverLetter]
    @Binding var selection: CoverLetter?
    
    private var hasRequiredLettersForCommittee: Bool {
        (jobAppStore.selectedApp?.coverLetters.filter { $0.generated }.count ?? 0) >= 2
    }
    
    var body: some View {
        HStack(spacing: 12) {
            CoverLetterReviseButton()
            
            Button {
                NotificationCenter.default.post(name: .batchCoverLetter, object: nil)
            } label: {
                Label("Batch Letter", systemImage: "square.stack.3d.down.right")
                    .font(.system(size: 14, weight: .light))
            }
            .buttonStyle(.automatic)
            .help("Batch Cover Letter Operations")
            .disabled(jobAppStore.selectedApp?.selectedRes == nil)
            
            Button {
                NotificationCenter.default.post(name: .committee, object: nil)
            } label: {
                Label("Committee", systemImage: "trophy")
                    .font(.system(size: 14, weight: .light))
            }
            .buttonStyle(.automatic)
            .help("Multi-model Choose Best Cover Letter")
            .disabled(!hasRequiredLettersForCommittee)
            
            TTSButton()
            
            Spacer(minLength: 0)
            
            if !coverLetters.isEmpty {
                CoverLetterPicker(
                    coverLetters: coverLetters,
                    selection: $selection,
                    includeNoneOption: false,
                    label: ""
                )
                .frame(maxWidth: 280)
                .onAppear {
                    // Clean up any ungenerated drafts when the view appears
                    coverLetterStore.deleteUngeneratedDrafts()
                    coverLetterStore.cL = selection
                }
                .onChange(of: selection?.id) { _, _ in
                    // Sync with coverLetterStore when selection changes
                    coverLetterStore.cL = selection
                }
            }
        }
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }
}

// MARK: - Generate Cover Letter Button Component
struct GenerateCoverLetterButtonView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
    @State private var isHovered = false
    
    var body: some View {
        Button(action: {
            NotificationCenter.default.post(name: .triggerGenerateCoverLetterButton, object: nil)
        }) {
            VStack(spacing: 12) {
                // Modern card design
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: isHovered ? 
                                [Color.indigo.opacity(0.15), Color.blue.opacity(0.15)] :
                                [Color.indigo.opacity(0.08), Color.blue.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.indigo.opacity(0.3), Color.blue.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: isHovered ? 2 : 1
                            )
                    )
                    .overlay(
                        VStack(spacing: 12) {
                            if coverLetterStore.isGeneratingCoverLetter {
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .tint(Color.indigo)
                                    .frame(width: 36, height: 36)
                            } else {
                                Image("generate.coverletter")
                                    .renderingMode(.template)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 36, height: 36)
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [Color.indigo, Color.blue],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                            VStack(spacing: 4) {
                                Text("Generate Cover Letter")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.primary)
                                
                                Text("Create a tailored letter")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                    )
                    .shadow(
                        color: isHovered ? Color.indigo.opacity(0.2) : Color.black.opacity(0.05),
                        radius: isHovered ? 12 : 8,
                        x: 0,
                        y: isHovered ? 8 : 4
                    )
            }
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(.plain)
        .disabled(jobAppStore.selectedApp?.selectedRes == nil)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Batch Cover Letter Button Component
struct BatchCoverLetterButtonView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore
    @State private var isHovered = false
    
    var body: some View {
        Button(action: {
            NotificationCenter.default.post(name: .batchCoverLetter, object: nil)
        }) {
            VStack(spacing: 12) {
                // Modern card design
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: isHovered ? 
                                [Color.purple.opacity(0.15), Color.pink.opacity(0.15)] :
                                [Color.purple.opacity(0.08), Color.pink.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.purple.opacity(0.3), Color.pink.opacity(0.3)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: isHovered ? 2 : 1
                            )
                    )
                    .overlay(
                        VStack(spacing: 12) {
                            if coverLetterStore.isGeneratingCoverLetter {
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .tint(Color.purple)
                                    .frame(width: 36, height: 36)
                            } else {
                                Image(systemName: "square.stack.3d.forward.dottedline")
                                    .font(.system(size: 36, weight: .light))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [Color.purple, Color.pink],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            }
                            
                            VStack(spacing: 4) {
                                Text("Batch Generation")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.primary)
                                
                                Text("Generate multiple at once")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                    )
                    .shadow(
                        color: isHovered ? Color.purple.opacity(0.2) : Color.black.opacity(0.05),
                        radius: isHovered ? 12 : 8,
                        x: 0,
                        y: isHovered ? 8 : 4
                    )
            }
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(.plain)
        .disabled(jobAppStore.selectedApp?.selectedRes == nil)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
