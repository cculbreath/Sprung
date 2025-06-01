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

struct RecommendJobButton: View {
    @Environment(JobAppStore.self) private var jobAppStore
    @Environment(AppState.self) private var appState

    @State private var isLoading = false
    @State private var errorWrapper: ErrorMessageWrapper? = nil
    @State private var showModelPicker = false
    @State private var selectedModel = ""

    var body: some View {
        Button(action: { showModelPicker = true }) {
            HStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "medal.star")
                        .foregroundColor(.primary)
                }
                Text("Find Best Match")
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(6)
        }
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
                    
                    ModelPickerView(
                        selectedModel: $selectedModel,
                        title: "AI Model",
                        useModelSelection: true
                    )
                    .environment(appState)
                    
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
                let provider = JobRecommendationProvider(
                    appState: appState,
                    jobApps: jobAppStore.jobApps,
                    resume: selectedResume,
                    modelId: selectedModel
                )

                let (jobId, reason) = try await provider.fetchRecommendation()

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

#Preview {
    RecommendJobButton()
}
