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

    @Binding var isWide: Bool
    @Binding var tab: TabList
    @Binding var refresh: Bool
    @Binding var sheets: AppSheets

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
            // GeometryReader gives the true available width up front, so the PDF
            // pane is sized within the same layout pass and can never overflow
            // it (the stuck, clipped state came from lagged measurement).
            GeometryReader { geo in
                let pdfW = pdfDisplayWidth(geo.size.width)
                HStack(spacing: 0) {
                    // Editor column takes the remainder
                    ResumeDetailView(
                        resume: selRes,
                        tab: $tab,
                        isWide: $isWide,
                        sheets: $sheets,
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
                        pdfPreviewSection(resume: selRes, width: pdfW)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }

            ResumeBannerView(jobApp: selApp)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: pdfPreviewVisible)
        .sheet(isPresented: $showCreateResumeSheet) {
            CreateResumeView(
                onCreateResume: { template in
                    try resStore.create(
                        jobApp: selApp,
                        template: template
                    )
                    refresh.toggle()
                }
            )
            .padding()
        }
    }

    /// Smallest the PDF preview may be dragged or squeezed to (points). ~250pt
    /// renders as ~500px in a 2x Retina screenshot — enough to keep a page
    /// legible. MUST match the PDF floor in ResumeEditorModuleView.detailMinWidth
    /// so the window minimum reserves the same width; both are the drag floor and
    /// the squeeze floor in pdfDisplayWidth, so a compressed pane stays draggable.
    private let minPdfPreviewWidth: CGFloat = 250
    private let maxPdfPreviewWidth: CGFloat = 800

    /// Width the rest of the row must always keep: editor minimum (300) +
    /// preview chevron bar (16) + resize handle (9).
    private let nonPdfMinBudget: CGFloat = 325

    /// Stored preview width, clamped to the available row width so the editor
    /// always keeps its minimum. Computed synchronously from the GeometryReader
    /// width, so a persisted width larger than the window can never push the
    /// editor out of the layout.
    private func pdfDisplayWidth(_ available: CGFloat) -> Double {
        // Before first layout GeometryReader reports 0; show the stored width.
        guard available > 0 else { return pdfPreviewWidth }
        let room = Double(available - nonPdfMinBudget)
        return min(pdfPreviewWidth, max(room, Double(minPdfPreviewWidth)))
    }

    @ViewBuilder
    private func pdfPreviewSection(resume: Resume, width: Double) -> some View {
        VerticalResizeHandle(
            width: $pdfPreviewWidth,
            minWidth: minPdfPreviewWidth,
            maxWidth: maxPdfPreviewWidth,
            inverted: true,
            displayedWidth: width
        )

        ResumePDFView(resume: resume)
            .frame(width: width)
            .id(resume.id)
    }

    // MARK: - Empty States

    @State private var emptyStateTemplateID: UUID?
    @State private var noResumeCreateError: String?

    private func noResumeState(selApp: JobApp) -> some View {
        let templates = templateStore.templates()

        return VStack(spacing: 0) {
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
                        do {
                            try resStore.create(
                                jobApp: selApp,
                                template: template
                            )
                            refresh.toggle()
                        } catch {
                            noResumeCreateError = error.localizedDescription
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
                        Button("Manage Templates…") {
                            NotificationCenter.default.post(
                                name: .navigateToModule, object: nil,
                                userInfo: ["module": AppModule.references.rawValue]
                            )
                            NotificationCenter.default.post(
                                name: .navigateToReferencesTab, object: nil,
                                userInfo: ["tab": "Templates"]
                            )
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

            ResumeBannerView(jobApp: selApp)
        }
        .alert(
            "Couldn't Create Resume",
            isPresented: Binding(
                get: { noResumeCreateError != nil },
                set: { if !$0 { noResumeCreateError = nil } }
            )
        ) {
            Button("OK") { noResumeCreateError = nil }
        } message: {
            Text(noResumeCreateError ?? "")
        }
    }

    private var noJobAppState: some View {
        Text("Select a job application to customize a resume")
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

