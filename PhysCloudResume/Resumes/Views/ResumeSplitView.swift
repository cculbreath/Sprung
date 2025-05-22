//
//  ResumeSplitView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 1/31/25.
//

import SwiftUI

struct ResumeSplitView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(ResStore.self) private var resStore: ResStore
    @Environment(ResModelStore.self) private var resModelStore: ResModelStore
    @Environment(ResRefStore.self) private var resRefStore: ResRefStore
    
    @Binding var isWide: Bool
    @Binding var tab: TabList
    @Binding var resumeButtons: ResumeButtons
    @Binding var refresh: Bool
    
    @State private var showCreateResumeSheet = false
    
    var body: some View {
        if let selApp = jobAppStore.selectedApp {
            if let selRes = selApp.selectedRes {
                // Show the resume view if there's a selected resume
                @Bindable var selApp = selApp

                HSplitView {
                    ResumeDetailView(
                        resume: selRes,
                        tab: $tab,
                        isWide: $isWide,
                        resStore: resStore
                    )
                    .frame(
                        minWidth: isWide ? 350 : 200,
                        idealWidth: isWide ? 500 : 300,
                        maxWidth: 600,
                        maxHeight: .infinity
                    )
                    .id(selRes.id) // Force view recreation when selected resume changes
                    .onAppear { Logger.debug("RootNode") }
                    .layoutPriority(1) // Ensures this view gets priority in layout

                    ResumePDFView(resume: selRes)
                        .frame(
                            minWidth: 300, idealWidth: 400,
                            maxWidth: .infinity, maxHeight: .infinity
                        )
                        .id(selRes.id) // Force view recreation when selected resume changes
                        .layoutPriority(1) // Less priority, but still resizable
                }.inspector(isPresented: $resumeButtons.showResumeInspector) {
                    ResumeInspectorView(refresh: $refresh)
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
                        onCreateResume: { model, sources in
                            if resStore.create(
                                jobApp: selApp,
                                sources: sources,
                                model: model
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
