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
    @Environment(TemplateStore.self) private var templateStore: TemplateStore
    @Environment(KnowledgeCardStore.self) private var knowledgeCardStore: KnowledgeCardStore

    @Binding var isWide: Bool
    @Binding var tab: TabList
    @Binding var refresh: Bool
    @Binding var sheets: AppSheets
    @Binding var clarifyingQuestions: [ClarifyingQuestion]

    @State private var showCreateResumeSheet = false
    @AppStorage("pdfPreviewVisible") private var pdfPreviewVisible = true
    @AppStorage("pdfPreviewWidth") private var pdfPreviewWidth: Double = 360

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
        VStack(spacing: 0) {
            ResumeBannerView(jobApp: selApp)
                .frame(height: 32)

            HStack(spacing: 0) {
                // Editor column
                ResumeDetailView(
                    resume: selRes,
                    tab: $tab,
                    isWide: $isWide,
                    sheets: $sheets,
                    clarifyingQuestions: $clarifyingQuestions,
                    showCreateResumeSheet: $showCreateResumeSheet,
                    exportCoordinator: appEnvironment.resumeExportCoordinator
                )
                .id(selRes.id)
                .frame(
                    minWidth: isWide ? 300 : 220,
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )

                ResumePreviewChevronBar(pdfPreviewVisible: $pdfPreviewVisible)

                if pdfPreviewVisible {
                    pdfPreviewSection(resume: selRes)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: pdfPreviewVisible)
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

    private let minPdfPreviewWidth: CGFloat = 260
    private let maxPdfPreviewWidth: CGFloat = 800

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

    @State private var emptyStateTemplateID: UUID?

    private func noResumeState(selApp: JobApp) -> some View {
        let templates = templateStore.templates()

        return VStack(spacing: 0) {
            ResumeBannerView(jobApp: selApp)
                .frame(height: 32)

            VStack(spacing: 20) {
                Text("No Resume Available")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Create a resume to customize it for this job application.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 12) {
                    Picker("Template", selection: $emptyStateTemplateID) {
                        Text("Select a template").tag(nil as UUID?)
                        ForEach(templates) { template in
                            Text(template.name).tag(template.id as UUID?)
                        }
                    }
                    .frame(width: 260)

                    Button {
                        guard
                            let templateID = emptyStateTemplateID,
                            let template = templates.first(where: { $0.id == templateID })
                        else { return }
                        if resStore.create(
                            jobApp: selApp,
                            sources: knowledgeCardStore.knowledgeCards,
                            template: template
                        ) != nil {
                            refresh.toggle()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "doc.badge.plus")
                            Text("Create Resume")
                        }
                        .padding(.horizontal, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(emptyStateTemplateID == nil)

                    if templates.isEmpty {
                        Button("Open Template Editor") {
                            NotificationCenter.default.post(name: .showTemplateEditor, object: nil)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                if emptyStateTemplateID == nil {
                    emptyStateTemplateID = templateStore.defaultTemplate()?.id
                        ?? templates.first?.id
                }
            }
        }
    }

    private var noJobAppState: some View {
        Text("Select a job application to customize a resume")
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

