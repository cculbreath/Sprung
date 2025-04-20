//
//  RecommendJobButton.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/20/25.
//

import SwiftUI

struct RecommendJobButton: View {
    @Environment(JobAppStore.self) private var jobAppStore
    @Environment(\.appState) private var appState

    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    var body: some View {
        Button(action: recommendBestJob) {
            HStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "sparkles.rectangle.stack")
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
        .alert(item: $errorMessageWrapper) { wrapper in
            Alert(
                title: Text("Error"),
                message: Text(wrapper.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var errorMessageWrapper: ErrorMessageWrapper? {
        get {
            errorMessage.map { ErrorMessageWrapper(message: $0) }
        }
        set {
            errorMessage = newValue?.message
        }
    }

    private func recommendBestJob() {
        guard let selectedResume = jobAppStore.selectedApp?.selectedRes else {
            errorMessage = "Please select a resume first"
            return
        }

        let newJobs = jobAppStore.jobApps.filter { $0.status == .new }
        if newJobs.isEmpty {
            errorMessage = "No new job applications found"
            return
        }

        isLoading = true
        appState.isLoadingRecommendation = true

        Task {
            do {
                let provider = JobRecommendationProvider(
                    jobApps: jobAppStore.jobApps,
                    resume: selectedResume,
                    savePromptToFile: true
                )

                let (jobId, reason) = try await provider.fetchRecommendation()

                await MainActor.run {
                    // Find the job with the recommended ID
                    if let recommendedJob = jobAppStore.jobApps.first(where: { $0.id == jobId }) {
                        // Set as selected job
                        jobAppStore.selectedApp = recommendedJob

                        // Store the recommended job ID for highlighting
                        appState.recommendedJobId = jobId

                        // Create an alert instead of notification since NSUserNotification is unavailable
                        errorMessage = "Recommended: \(recommendedJob.jobPosition) at \(recommendedJob.companyName)\n\nReason: \(reason)"
                    } else {
                        errorMessage = "Recommended job not found"
                    }

                    isLoading = false
                    appState.isLoadingRecommendation = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Error: \(error.localizedDescription)"
                    isLoading = false
                    appState.isLoadingRecommendation = false
                }
            }
        }
    }
}

struct ErrorMessageWrapper: Identifiable {
    let id = UUID()
    let message: String
}

#Preview {
    RecommendJobButton()
}