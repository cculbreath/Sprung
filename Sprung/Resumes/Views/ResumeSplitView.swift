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
                // Show the resume view if there's a selected resume
                @Bindable var selApp = selApp

                let splitView = HSplitView {
                    ResumeDetailView(
                        resume: selRes,
                        tab: $tab,
                        isWide: $isWide,
                        exportCoordinator: appEnvironment.resumeExportCoordinator
                    )
                    .frame(
                        minWidth: isWide ? 300 : 220,
                        idealWidth: isWide ? 480 : 320,
                        maxWidth: 640,
                        maxHeight: .infinity
                    )
                    .id(selRes.id) // Force view recreation when selected resume changes
                    .onAppear { Logger.debug("RootNode") }
                    .layoutPriority(1) // Ensures this view gets priority in layout

                    ResumePDFView(resume: selRes)
                        .frame(
                            minWidth: 260, idealWidth: 360,
                            maxWidth: .infinity, maxHeight: .infinity
                        )
                        .id(selRes.id) // Force view recreation when selected resume changes
                        .layoutPriority(1) // Less priority, but still resizable
                }

                ZStack(alignment: .topLeading) {
                    splitView
                        .padding(.top, 52)

                    VStack(spacing: 0) {
                        ResumeActionsBar(
                            selectedTab: $tab,
                            sheets: $sheets,
                            clarifyingQuestions: $clarifyingQuestions
                        )
                        Divider()
                    }
                    .frame(maxWidth: .infinity)
                    .background(
                        VisualEffectBlur(material: .headerView, blendingMode: .behindWindow)
                    )
                }
                    .overlay(alignment: .trailing) {
                        ResumeInspectorOverlay(
                            isPresented: $showResumeInspector,
                            refresh: $refresh
                        )
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
                        jobApp: selApp,
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

private struct ResumeInspectorOverlay: View {
    @Binding var isPresented: Bool
    @Binding var refresh: Bool
    @State private var dragOffset: CGFloat = 0

    private let inspectorWidth: CGFloat = 340

    var body: some View {
        GeometryReader { geo in
            let width = inspectorWidth
            ResumeInspectorView(refresh: $refresh)
                .frame(maxHeight: .infinity)
                .background(
                    VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow)
                        .ignoresSafeArea()
                )
                .offset(x: isPresented ? 0 : width + 16)
                .offset(x: dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = min(0, max(-width, value.translation.width))
                        }
                        .onEnded { value in
                            let shouldDismiss = value.translation.width > width * 0.4
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                if shouldDismiss {
                                    isPresented = false
                                }
                                dragOffset = 0
                            }
                        }
                )
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isPresented)
        }
        .allowsHitTesting(isPresented)
    }
}
