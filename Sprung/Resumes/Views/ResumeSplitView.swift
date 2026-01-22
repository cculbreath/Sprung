//
//  ResumeSplitView.swift
//  Sprung
//
//  Resume editing split view with unified collapsible inspector panel.
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

    private let inspectorWidth: CGFloat = 340
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
        GeometryReader { geo in
            HStack(spacing: 0) {
                // Main content area
                mainEditorContent(selApp: selApp, selRes: selRes)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Collapsible inspector panel
                if showResumeInspector {
                    // Separator
                    Rectangle()
                        .fill(Color(.separatorColor))
                        .frame(width: 1)

                    inspectorPanel
                        .frame(width: inspectorWidth, height: geo.size.height)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showResumeInspector)
        }
    }

    private func mainEditorContent(selApp: JobApp, selRes: Resume) -> some View {
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

            // Actions bar overlay
            VStack(spacing: 0) {
                ResumeActionsBar(
                    selectedTab: $tab,
                    sheets: $sheets,
                    clarifyingQuestions: $clarifyingQuestions,
                    showCreateResumeSheet: $showCreateResumeSheet,
                    showInspector: $showResumeInspector
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

    // MARK: - Inspector Panel

    private var inspectorPanel: some View {
        VStack(spacing: 0) {
            // Inspector header with collapse toggle
            HStack {
                Text("Inspector")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                PanelToggleButton(
                    edge: .trailing,
                    isExpanded: $showResumeInspector,
                    collapsedIcon: "sidebar.right",
                    expandedIcon: "sidebar.right"
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Inspector content
            ResumeInspectorView(refresh: $refresh)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.windowBackgroundColor))
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
    @Binding var showInspector: Bool

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

            // Inspector toggle button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showInspector.toggle()
                }
            } label: {
                Image(systemName: showInspector ? "sidebar.right" : "sidebar.right")
                    .font(.system(size: 14))
                    .foregroundStyle(showInspector ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help(showInspector ? "Hide Inspector" : "Show Inspector")

            Button {
                showCreateResumeSheet = true
            } label: {
                Label("Create Resume", systemImage: "doc.badge.plus")
                    .font(.system(size: 14, weight: .light))
            }
            .buttonStyle(.automatic)
            .help("Create a new resume for this job application")
        }
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }
}
