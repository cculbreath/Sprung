//
//  RecommendJobButton.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/20/25.
//

import SwiftUI

// Import Logger
import Foundation

struct ErrorMessageWrapper: Identifiable {
    let id = UUID()
    let message: String
}

// Custom button style matching sidebar appearance with text labels
struct RecommendButtonStyle: ButtonStyle {
    @State private var isHovering = false
    
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 2) {
            configuration.label
        }
        .foregroundColor(configuration.isPressed ? .accentColor : (isHovering ? .primary : .secondary))
        .frame(minWidth: 60)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(configuration.isPressed ? Color.gray.opacity(0.2) : (isHovering ? Color.gray.opacity(0.1) : Color.clear))
        )
        .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct RecommendJobButton: View {
    @Environment(JobAppStore.self) private var jobAppStore
    @Environment(AppState.self) private var appState

    @State private var isLoading = false
    @State private var errorWrapper: ErrorMessageWrapper? = nil
    @State private var showModelPicker = false
    @State private var selectedModel = ""

    var body: some View {
        Button(action: { showModelPicker = true }) {
            if isLoading {
                Image(systemName: "wand.and.rays")
                    .font(.system(size: 18))
                    .symbolEffect(.variableColor.iterative.hideInactiveLayers.nonReversing)
            } else {
                Image(systemName: "medal.star")
                    .font(.system(size: 18))
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .help("Find the best job match based on your qualifications")
        .alert(item: $errorWrapper) { wrapper in
            Alert(
                title: Text("Recommendation"),
                message: Text(wrapper.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .sheet(isPresented: $showModelPicker) {
            NavigationStack {
                VStack(spacing: 20) {
                    Text("Choose Model for Job Recommendation")
                        .font(.headline)
                        .padding(.top)
                    
                    DropdownModelPicker(
                        selectedModel: $selectedModel,
                        title: "AI Model"
                    )
                    
                    HStack(spacing: 12) {
                        Button("Cancel") {
                            showModelPicker = false
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Recommend") {
                            showModelPicker = false
                            recommendBestJob()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedModel.isEmpty)
                    }
                    
                    Spacer()
                }
                .padding()
                .frame(width: 400, height: 250)
            }
        }
    }

    private func setErrorMessage(_ message: String) {
        errorWrapper = ErrorMessageWrapper(message: message)
    }

    private func recommendBestJob() {
        guard let selectedResume = jobAppStore.selectedApp?.selectedRes else {
            setErrorMessage("Please select a resume first")
            return
        }

        let newJobs = jobAppStore.jobApps.filter { $0.status == .new }
        if newJobs.isEmpty {
            setErrorMessage("No new job applications found")
            return
        }

        isLoading = true
        appState.isLoadingRecommendation = true

        Task {
            do {
                let service = JobRecommendationService()
                
                let (jobId, reason) = try await service.fetchRecommendation(
                    jobApps: jobAppStore.jobApps,
                    resume: selectedResume,
                    modelId: selectedModel
                )

                await MainActor.run {
                    // Find the job with the recommended ID
                    if let recommendedJob = jobAppStore.jobApps.first(where: { $0.id == jobId }) {
                        // Set as selected job
                        jobAppStore.selectedApp = recommendedJob

                        // Store the recommended job ID for highlighting
                        appState.recommendedJobId = jobId

                        // Show recommendation in alert
                        setErrorMessage("Recommended: \(recommendedJob.jobPosition) at \(recommendedJob.companyName)\n\nReason: \(reason)")
                    } else {
                        setErrorMessage("Recommended job not found")
                    }

                    isLoading = false
                    appState.isLoadingRecommendation = false
                }
            } catch {
                await MainActor.run {
                    // Enhanced error logging using Logger
                    Logger.error("JobRecommendation Error: \(error)")
                    Logger.error("Error description: \(error.localizedDescription)")
                    
                    // Show more detailed error message to user
                    if let nsError = error as NSError? {
                        Logger.error("Error domain: \(nsError.domain), code: \(nsError.code)")
                        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
                            Logger.error("Underlying error: \(underlyingError)")
                        }
                        
                        // Include underlying error info in the alert if available
                        let detailedMessage = "Error: \(error.localizedDescription)\n\nDetails: Domain=\(nsError.domain), Code=\(nsError.code)"
                        setErrorMessage(detailedMessage)
                    } else {
                        setErrorMessage("Error: \(error.localizedDescription)")
                    }
                    
                    isLoading = false
                    appState.isLoadingRecommendation = false
                }
            }
        }
    }
}

