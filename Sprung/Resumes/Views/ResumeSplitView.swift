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
            mainEditorContent(selApp: selApp, selRes: selRes)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private let minPdfPreviewWidth: CGFloat = 260
    private let maxPdfPreviewWidth: CGFloat = 800

    private func mainEditorContent(selApp: JobApp, selRes: Resume) -> some View {
        HStack(spacing: 0) {
            ResumeDetailView(
                resume: selRes,
                tab: $tab,
                isWide: $isWide,
                sheets: $sheets,
                clarifyingQuestions: $clarifyingQuestions,
                showCreateResumeSheet: $showCreateResumeSheet,
                exportCoordinator: appEnvironment.resumeExportCoordinator
            )
            .frame(
                minWidth: isWide ? 300 : 220,
                maxWidth: .infinity,
                maxHeight: .infinity
            )
            .id(selRes.id)

            ResumePreviewChevronBar(pdfPreviewVisible: $pdfPreviewVisible)

            if pdfPreviewVisible {
                pdfPreviewSection(resume: selRes)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
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
        VStack(spacing: 0) {
            ResumeBannerView(jobApp: selApp)

            VStack(spacing: 20) {
                Text("No Resume Available")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Create a resume to customize it for this job application.")
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var noJobAppState: some View {
        Text("Select a job application to customize a resume")
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

