// PhysCloudResume/App/Views/UnifiedToolbar.swift
import SwiftUI
import AppKit

/// Unified toolbar with all buttons visible, using disabled state instead of hiding
@ToolbarContentBuilder
func buildUnifiedToolbar(
    selectedTab: Binding<TabList>,
    listingButtons: Binding<SaveButtons>,
    letterButtons: Binding<CoverLetterButtons>,
    resumeButtons: Binding<ResumeButtons>,
    refresh: Binding<Bool>,
    showApplicationReviewSheet: Binding<Bool>,
    showResumeReviewSheet: Binding<Bool>,
    showClarifyingQuestionsSheet: Binding<Bool>,
    showChooseBestCoverLetterSheet: Binding<Bool>,
    showMultiModelChooseBestSheet: Binding<Bool>,
    clarifyingQuestions: Binding<[ClarifyingQuestion]>
) -> some ToolbarContent {
    UnifiedToolbar(
        selectedTab: selectedTab,
        listingButtons: listingButtons,
        letterButtons: letterButtons,
        resumeButtons: resumeButtons,
        refresh: refresh,
        showApplicationReviewSheet: showApplicationReviewSheet,
        showResumeReviewSheet: showResumeReviewSheet,
        showClarifyingQuestionsSheet: showClarifyingQuestionsSheet,
        showChooseBestCoverLetterSheet: showChooseBestCoverLetterSheet,
        showMultiModelChooseBestSheet: showMultiModelChooseBestSheet,
        clarifyingQuestions: clarifyingQuestions
    )
}

struct UnifiedToolbar: ToolbarContent {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(AppState.self) private var appState: AppState
    @Environment(CoverLetterStore.self) private var coverLetterStore: CoverLetterStore

    @Binding var selectedTab: TabList
    @Binding var listingButtons: SaveButtons
    @Binding var letterButtons: CoverLetterButtons
    @Binding var resumeButtons: ResumeButtons
    @Binding var refresh: Bool
    @Binding var showApplicationReviewSheet: Bool
    @Binding var showResumeReviewSheet: Bool
    @Binding var showClarifyingQuestionsSheet: Bool
    @Binding var showChooseBestCoverLetterSheet: Bool
    @Binding var showMultiModelChooseBestSheet: Bool
    @Binding var clarifyingQuestions: [ClarifyingQuestion]

    @State private var isGeneratingResume = false
    @State private var isGeneratingCoverLetter = false

    private var selectedResumeBinding: Binding<Resume?> {
        Binding<Resume?>(
            get: { jobAppStore.selectedApp?.selectedRes },
            set: { newValue in
                if jobAppStore.selectedApp != nil {
                    jobAppStore.selectedApp!.selectedRes = newValue
                }
            }
        )
    }

    var body: some ToolbarContent {
        // ───── Left edge: Title and Status ─────
        ToolbarItemGroup(placement: .navigation) {
            if let selApp = jobAppStore.selectedApp {
                HStack(spacing: 12) {
                    // Status tag
                    selApp.statusTag

                    // Title with better space management
                    VStack(alignment: .leading, spacing: 1) {
                        Text(selApp.jobPosition)
                            .font(.headline)
                            .lineLimit(1)
                            .frame(maxWidth: 500, alignment: .leading)
                        Text(selApp.companyName)
                            .font(.caption)
                            .lineLimit(1)
                            .frame(maxWidth: 500, alignment: .leading)
                    }
                }
            }
        }

        // ───── Center: All main buttons ─────
        ToolbarItemGroup(placement: .principal) {
            HStack(spacing: 20) {
                // Resume Operations cluster
                HStack(spacing: 12) {
                    resumeButton("Customize", "wand.and.sparkles", action: {
                        if let resume = selectedResumeBinding.wrappedValue {
                            isGeneratingResume = true
                        }
                    }, disabled: selectedResumeBinding.wrappedValue?.rootNode == nil,
                                 help: "Create Resume Revisions")

                    Button(action: {
                        clarifyingQuestions = []
                        showClarifyingQuestionsSheet = true
                    }) {
                        VStack(spacing: 3) {
                            if isGeneratingResume {
                                Image("custom.wand.and.rays.inverse.badge.questionmark")
                                    .font(.system(size: 18))
                                    .frame(height: 20)
                            } else {
                                Image("custom.wand.and.sparkles.badge.questionmark")
                                    .font(.system(size: 18))
                                    .frame(height: 20)
                            }
                            Text("Clarify & Customize")
                                .font(.system(size: 11))
                                .frame(height: 14)
                        }
                        .frame(minWidth: 60, minHeight: 50)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .help("Create Resume Revisions with Clarifying Questions")
                    .disabled(selectedResumeBinding.wrappedValue?.rootNode == nil)
                    .sheet(isPresented: $showClarifyingQuestionsSheet) {
                        ClarifyingQuestionsSheet(
                            questions: clarifyingQuestions,
                            isPresented: $showClarifyingQuestionsSheet,
                            onSubmit: { answers in
                                showClarifyingQuestionsSheet = false
                            }
                        )
                    }

                    resumeButton("Optimize", "character.magnify", action: {
                        showResumeReviewSheet = true
                    }, disabled: selectedResumeBinding.wrappedValue == nil,
                                 help: "AI Resume Review")
                }

                Divider()
                    .frame(height: 30)

                // Cover Letter Operations cluster
                HStack(spacing: 12) {
                    Button(action: {
                        if let cL = coverLetterStore.cL {
                            isGeneratingCoverLetter = true
                            let newCL = coverLetterStore.createDuplicate(letter: cL)
                            newCL.currentMode = .generate
                            coverLetterStore.cL = newCL
                        }
                    }) {
                        VStack(spacing: 3) {
                            Image("custom.append.page.badge.plus")
                                .font(.system(size: 18))
                                .frame(height: 20)
                            Text("Cover Letter")
                                .font(.system(size: 11))
                                .frame(height: 14)
                        }
                        .frame(minWidth: 60, minHeight: 50)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .help("Generate Cover Letter")
                    .disabled(jobAppStore.selectedApp?.selectedRes == nil)

                    coverLetterButton("Batch Letter", "square.stack.3d.up.fill", action: {
                        letterButtons.showBatchGeneration = true
                    }, disabled: jobAppStore.selectedApp?.selectedRes == nil,
                                      help: "Batch Cover Letter Operations")

                    coverLetterButton("Best Letter", "medal", action: {
                        showChooseBestCoverLetterSheet = true
                    }, disabled: (jobAppStore.selectedApp?.coverLetters.filter { $0.generated }.count ?? 0) < 2,
                                      help: "Choose Best Cover Letter")

                    Button(action: {
                        showMultiModelChooseBestSheet = true
                    }) {
                        VStack(spacing: 3) {
                            Image("custom.medal.square.stack")
                                .font(.system(size: 18))
                                .frame(height: 20)
                            Text("Committee")
                                .font(.system(size: 11))
                                .frame(height: 14)
                        }
                        .frame(minWidth: 60, minHeight: 50)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .help("Multi-model Choose Best Cover Letter")
                    .disabled((jobAppStore.selectedApp?.coverLetters.filter { $0.generated }.count ?? 0) < 2)
                }

                // Additional buttons section
                if UserDefaults.standard.bool(forKey: "ttsEnabled") {
                    Divider()
                        .frame(height: 30)

                    HStack(spacing: 12) {
                        TTSButton()
                            .disabled(coverLetterStore.cL?.generated != true)

                        sidebarButton("Analyze", "mail.and.text.magnifyingglass", action: {
                            showApplicationReviewSheet = true
                        }, disabled: jobAppStore.selectedApp?.selectedRes == nil ||
                                      jobAppStore.selectedApp?.selectedCover == nil ||
                                      jobAppStore.selectedApp?.selectedCover?.generated != true,
                                      help: "Review Application")
                    }
                } else {
                    Divider()
                        .frame(height: 30)

                    sidebarButton("Analyze", "mail.and.text.magnifyingglass", action: {
                        showApplicationReviewSheet = true
                    }, disabled: jobAppStore.selectedApp?.selectedRes == nil ||
                                  jobAppStore.selectedApp?.selectedCover == nil ||
                                  jobAppStore.selectedApp?.selectedCover?.generated != true,
                                  help: "Review Application")
                }
            }
        }

        // ───── Right edge: Inspector only ─────
        ToolbarItem(placement: .primaryAction) {
            sidebarButton("Inspector", "sidebar.right", action: {
                resumeButtons.showResumeInspector.toggle()
            }, disabled: selectedTab != .resume,
                          help: "Show Resume Inspector")
        }
    }

    // Helper functions for consistent button styling
    @ViewBuilder
    private func resumeButton(_ title: String,
                              _ systemName: String,
                              action: @escaping () -> Void,
                              disabled: Bool = false,
                              help: String) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                if isGeneratingResume && (title == "Customize") {
                    Image(systemName: "wand.and.rays")
                        .font(.system(size: 18))
                        .frame(height: 20)
                        .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing)
                } else {
                    Image(systemName: systemName)
                        .font(.system(size: 18))
                        .frame(height: 20)
                }
                Text(title)
                    .font(.system(size: 11))
                    .frame(height: 14)
            }
            .frame(minWidth: 60, minHeight: 50)
        }
        .buttonStyle(.plain)
        .help(help)
        .disabled(disabled)
    }

    @ViewBuilder
    private func coverLetterButton(_ title: String,
                                   _ systemName: String,
                                   action: @escaping () -> Void,
                                   disabled: Bool = false,
                                   help: String) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemName)
                    .font(.system(size: 18))
                    .frame(height: 20)
                Text(title)
                    .font(.system(size: 11))
                    .frame(height: 14)
            }
            .frame(minWidth: 60, minHeight: 50)
        }
        .buttonStyle(.plain)
        .help(help)
        .disabled(disabled)
    }

    @ViewBuilder
    private func actionButton(_ title: String,
                              _ systemName: String,
                              action: @escaping () -> Void,
                              disabled: Bool = false,
                              help: String) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title2)
        }
        .buttonStyle(.plain)
        .help(help)
        .disabled(disabled)
    }

    @ViewBuilder
    private func sidebarButton(_ title: String,
                               _ systemName: String,
                               action: @escaping () -> Void,
                               disabled: Bool = false,
                               help: String) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemName)
                    .font(.system(size: 18))
                    .frame(height: 20)
                Text(title)
                    .font(.system(size: 11))
                    .frame(height: 14)
            }
            .frame(minWidth: 60, minHeight: 50)
        }
        .buttonStyle(.plain)
        .help(help)
        .disabled(disabled)
    }
}

// TTS Button
struct TTSButton: View {
    @Environment(CoverLetterStore.self) private var coverLetterStore
    @AppStorage("ttsEnabled") var ttsEnabled: Bool = false

    var body: some View {
        if ttsEnabled {
            Button(action: {
                // TTS action
            }) {
                VStack(spacing: 3) {
                    Image(systemName: "speaker.wave.2")
                        .font(.system(size: 18))
                        .frame(height: 20)
                    Text("Read Aloud")
                        .font(.system(size: 11))
                        .frame(height: 14)
                }
                .frame(minWidth: 60, minHeight: 50)
            }
            .buttonStyle(.plain)
            .help("Read Cover Letter")
        }
    }
}

// Placeholder for Choose Best Cover Letter Sheet
struct ChooseBestCoverLetterSheet: View {
    let jobApp: JobApp
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            Text("Choose Best Cover Letter")
                .font(.title2)
                .padding()

            // Implementation would include model selection and processing

            Button("Close") {
                dismiss()
            }
            .padding()
        }
        .frame(width: 600, height: 400)
    }
}
