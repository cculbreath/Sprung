//
//  ResumeSplitView.swift
//  Sprung
//
//  Created by Christopher Culbreath on 1/31/25.
//
import SwiftUI
struct ResumeSplitView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(ResStore.self) private var resStore: ResStore
    @Environment(AppEnvironment.self) private var appEnvironment: AppEnvironment

    @Binding var isWide: Bool
    @Binding var tab: TabList
    @Binding var showResumeInspector: Bool
    @Binding var refresh: Bool
    @Binding var sheets: AppSheets
    @Binding var clarifyingQuestions: [ClarifyingQuestion]

    @State private var showCreateResumeSheet = false

    var body: some View {
        if let selApp = jobAppStore.selectedApp {
            if let selRes = selApp.selectedRes {
                // Back to working custom inspector implementation
                @Bindable var selApp = selApp
                GeometryReader { geo in
                    let inspectorWidth: CGFloat = 340
                    let actionBarHeight: CGFloat = 52
                    let isInspectorVisible = showResumeInspector
                    let availableWidth = geo.size.width - (isInspectorVisible ? inspectorWidth : 0)
                    let contentWidth = max(availableWidth, 480)
                    HStack(spacing: 0) {
                        ZStack(alignment: .topLeading) {
                            HSplitView {
                                ResumeDetailView(
                                    resume: selRes,
                                    tab: $tab,
                                    isWide: $isWide,
                                    exportCoordinator: appEnvironment.resumeExportCoordinator
                                )
                                .frame(
                                    minWidth: isWide ? 300 : 220,
                                    idealWidth: isWide ? 480 : 320,
                                    maxWidth: .infinity,
                                    maxHeight: .infinity
                                )
                                .id(selRes.id)
                                .onAppear { Logger.debug("RootNode") }
                                .layoutPriority(1)
                                ResumePDFView(resume: selRes)
                                    .frame(
                                        minWidth: 260, idealWidth: 360,
                                        maxWidth: .infinity, maxHeight: .infinity
                                    )
                                    .id(selRes.id)
                                    .layoutPriority(1)
                            }
                            .padding(.top, actionBarHeight)
                            VStack(spacing: 0) {
                                ResumeActionsBar(
                                    selectedTab: $tab,
                                    sheets: $sheets,
                                    clarifyingQuestions: $clarifyingQuestions
                                )
                                Divider()
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .frame(width: contentWidth, height: geo.size.height)
                        if isInspectorVisible {

                            Divider()
                            ResumeInspectorColumn(refresh: $refresh)
                                .frame(width: inspectorWidth, height: geo.size.height)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                                .compositingGroup()
                                .shadow(color: Color.black.opacity(0.08), radius: 3, x: -2, y: 0)
                                .shadow(color: Color.black.opacity(0.12), radius: 10, x: -4, y: 0)
                        }
                    }
                    .animation(.easeInOut(duration: 0.25), value: isInspectorVisible)
                }
            } else {
                // If no resume is selected, show a create resume view
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
                    // Basic resume creation sheet
                    CreateResumeView(
                        onCreateResume: { template, sources in
                            if resStore.create(
                                jobApp: selApp,
                                sources: sources,
                                template: template
                            ) != nil {
                                // Force refresh of the view
                                refresh.toggle()
                            }
                        }
                    )
                    .padding()
                }
            }
        } else {
            // If no job app is selected, show a placeholder
            Text("Select a job application to customize a resume")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
private struct ResumeActionsBar: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore

    @Binding var selectedTab: TabList
    @Binding var sheets: AppSheets
    @Binding var clarifyingQuestions: [ClarifyingQuestion]

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
        }
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }
}
private struct ResumeInspectorColumn: View {
    @Binding var refresh: Bool
    var body: some View {
        ResumeInspectorView(refresh: $refresh)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial, in: .rect(cornerRadius: 0))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.black.opacity(0.08))
                    .frame(width: 1)
            }
    }
}
