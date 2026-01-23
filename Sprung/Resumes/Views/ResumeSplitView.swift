//
//  ResumeSplitView.swift
//  Sprung
//
//  Resume editing split view.
//

import SwiftUI

struct ResumeSplitView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(ResStore.self) private var resStore: ResStore
    @Environment(AppEnvironment.self) private var appEnvironment: AppEnvironment

    @Binding var isWide: Bool
    @Binding var tab: TabList
    @Binding var refresh: Bool
    @Binding var sheets: AppSheets
    @Binding var clarifyingQuestions: [ClarifyingQuestion]

    @State private var showCreateResumeSheet = false
    @AppStorage("pdfPreviewVisible") private var pdfPreviewVisible = true
    @AppStorage("pdfPreviewWidth") private var pdfPreviewWidth: Double = 360

    private let actionBarHeight: CGFloat = 52

    var body: some View {
        if let selApp = jobAppStore.selectedApp {
            if let selRes = selApp.selectedRes {
                @Bindable var selApp = selApp
                resumeEditorContent(selApp: selApp, selRes: selRes)
            } else {
                noResumeState(selApp: selApp)
            }
        } else {
            noJobAppState
        }
    }

    // MARK: - Resume Editor Content

    private func resumeEditorContent(selApp: JobApp, selRes: Resume) -> some View {
        mainEditorContent(selApp: selApp, selRes: selRes)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private let minPdfPreviewWidth: CGFloat = 260
    private let maxPdfPreviewWidth: CGFloat = 800

    private func mainEditorContent(selApp: JobApp, selRes: Resume) -> some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                ResumeDetailView(
                    resume: selRes,
                    tab: $tab,
                    isWide: $isWide,
                    exportCoordinator: appEnvironment.resumeExportCoordinator
                )
                .frame(
                    minWidth: isWide ? 300 : 220,
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
                .id(selRes.id)

                if pdfPreviewVisible {
                    pdfPreviewSection(resume: selRes)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.top, actionBarHeight)
            .animation(.easeInOut(duration: 0.2), value: pdfPreviewVisible)

            // Actions bar overlay
            VStack(spacing: 0) {
                ResumeActionsBar(
                    selectedTab: $tab,
                    sheets: $sheets,
                    clarifyingQuestions: $clarifyingQuestions,
                    showCreateResumeSheet: $showCreateResumeSheet,
                    pdfPreviewVisible: $pdfPreviewVisible
                )
                Divider()
            }
            .frame(maxWidth: .infinity)
            .sheet(isPresented: $showCreateResumeSheet) {
                CreateResumeView(
                    onCreateResume: { template, sources in
                        if resStore.create(
                            jobApp: selApp,
                            sources: sources,
                            template: template
                        ) != nil {
                            refresh.toggle()
                        }
                    }
                )
                .padding()
            }
        }
    }

    @ViewBuilder
    private func pdfPreviewSection(resume: Resume) -> some View {
        VerticalResizeHandle(
            width: $pdfPreviewWidth,
            minWidth: minPdfPreviewWidth,
            maxWidth: maxPdfPreviewWidth,
            inverted: true
        )

        ResumePDFView(resume: resume)
            .frame(width: pdfPreviewWidth)
            .id(resume.id)
    }

    // MARK: - Empty States

    private func noResumeState(selApp: JobApp) -> some View {
        VStack(spacing: 20) {
            Text("No Resume Available")
                .font(.title)
                .fontWeight(.bold)

            Text("Create a resume to customize it for this job application.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Create Resume") {
                showCreateResumeSheet = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showCreateResumeSheet) {
            CreateResumeView(
                onCreateResume: { template, sources in
                    if resStore.create(
                        jobApp: selApp,
                        sources: sources,
                        template: template
                    ) != nil {
                        refresh.toggle()
                    }
                }
            )
            .padding()
        }
    }

    private var noJobAppState: some View {
        Text("Select a job application to customize a resume")
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Actions Bar

private struct ResumeActionsBar: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore

    @Binding var selectedTab: TabList
    @Binding var sheets: AppSheets
    @Binding var clarifyingQuestions: [ClarifyingQuestion]
    @Binding var showCreateResumeSheet: Bool
    @Binding var pdfPreviewVisible: Bool

    var body: some View {
        HStack(spacing: 12) {
            ResumeCustomizeButton(selectedTab: $selectedTab)

            ClarifyingQuestionsButton(
                selectedTab: $selectedTab,
                clarifyingQuestions: $clarifyingQuestions,
                sheets: $sheets
            )

            Button {
                sheets.showResumeReview = true
            } label: {
                Label("Optimize", systemImage: "character.magnify")
                    .font(.system(size: 14, weight: .light))
            }
            .buttonStyle(.automatic)
            .help("AI Resume Review")
            .disabled(jobAppStore.selectedApp?.selectedRes == nil)

            Spacer(minLength: 0)

            Button {
                showCreateResumeSheet = true
            } label: {
                Label("Create Resume", systemImage: "doc.badge.plus")
                    .font(.system(size: 14, weight: .light))
            }
            .buttonStyle(.automatic)
            .help("Create a new resume for this job application")

            // PDF preview toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    pdfPreviewVisible.toggle()
                }
            } label: {
                Label(pdfPreviewVisible ? "Hide Preview" : "Show Preview", systemImage: "document.viewfinder")
                    .font(.system(size: 14, weight: .light))
            }
            .buttonStyle(.automatic)
            .help(pdfPreviewVisible ? "Hide PDF preview" : "Show PDF preview")
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }
}
