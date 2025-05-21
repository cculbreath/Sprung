//
//  SidebarRecommendButton.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/20/25.
//

import SwiftUI

struct SidebarRecommendButton: View {
    @Environment(JobAppStore.self) private var jobAppStore
    @Environment(\.appState) private var appState
    @State private var isLoading = false
    @State private var errorWrapper: ErrorMessageWrapper? = nil

    var body: some View {
        Button(action: recommendBestJob) {
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)
            } else {
                Label("Find Best Match", systemImage: "sparkles.rectangle.stack")
                    .foregroundColor(.primary)
                    .font(.system(size: 14)) // Match font size with other toolbar buttons
                    .imageScale(.large) // Match imageScale with other toolbar buttons
            }
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
    }

    private func setErrorMessage(_ message: String) {
        errorWrapper = ErrorMessageWrapper(message: message)
    }

    private func recommendBestJob() {
        // Track if we're using the fallback mechanism
        let isUsingFallbackResume: Bool
        let resumeForRecommendation: Resume?

        // First check if we have an actively selected resume
        if let activelySelectedResume = jobAppStore.selectedApp?.selectedRes {
            // Using the currently selected resume
            resumeForRecommendation = activelySelectedResume
            isUsingFallbackResume = false
        } else {
            // Try to find a fallback resume for recommendation only
            resumeForRecommendation = getResumeForRecommendation()
            isUsingFallbackResume = true
        }

        // Make sure we have a resume to use
        guard let resumeToUse = resumeForRecommendation else {
            setErrorMessage("Please select or complete a resume first")
            return
        }

        // Check if we have new job applications
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
                    resume: resumeToUse
                )

                let (jobId, reason) = try await provider.fetchRecommendation()

                await MainActor.run {
                    // Find the job with the recommended ID
                    if let recommendedJob = jobAppStore.jobApps.first(where: { $0.id == jobId }) {
                        // Set as selected job
                        jobAppStore.selectedApp = recommendedJob

                        // IMPORTANT FIX: We should never clear the selectedResId completely
                        // as it breaks the ability to create new resumes
                        if isUsingFallbackResume {
                            // When using a fallback resume, we should not affect the selected resume
                            // Do not modify selectedResId at all
                        } else {
                            // Even with a legitimate selected resume, verify it's still valid
                        }

                        // Store the recommended job ID for highlighting
                        appState.recommendedJobId = jobId

                        // Show recommendation in alert
                        setErrorMessage("Recommended: \(recommendedJob.jobPosition) at \(recommendedJob.companyName)\n\nReason: \(reason)")
                    } else {
                        setErrorMessage("Recommended job ID \(jobId) not found. Please try again.")
                    }

                    isLoading = false
                    appState.isLoadingRecommendation = false
                }
            } catch {
                await MainActor.run {
                    setErrorMessage("Error: \(error.localizedDescription)")
                    isLoading = false
                    appState.isLoadingRecommendation = false
                }
            }
        }
    }

    /// Find the most appropriate resume to use for recommendation
    private func getResumeForRecommendation() -> Resume? {
        // First, check if there's already a selected resume
        if let selectedResume = jobAppStore.selectedApp?.selectedRes {
            return selectedResume
        }

        // Define statuses to consider for fallback resumes
        let relevantStatuses: [Statuses] = [
            .submitted, .rejected, .interview, .closed, .followUp,
        ]

        // Find job applications with relevant statuses
        let relevantApps = jobAppStore.jobApps.filter {
            relevantStatuses.contains($0.status) && $0.hasAnyRes
        }

        // Sort by status priority and then by jobPostingTime if available
        let sortedApps = relevantApps.sorted { app1, app2 in
            // First, prioritize by status in this order: submitted, interview, followUp, closed, rejected
            let statusOrder: [Statuses] = [.submitted, .interview, .followUp, .closed, .rejected]

            if let index1 = statusOrder.firstIndex(of: app1.status),
               let index2 = statusOrder.firstIndex(of: app2.status),
               index1 != index2
            {
                return index1 < index2 // Lower index has higher priority
            }

            // If statuses are the same, try to use jobPostingTime
            // Assuming newer postings are more relevant
            if !app1.jobPostingTime.isEmpty && !app2.jobPostingTime.isEmpty {
                return app1.jobPostingTime > app2.jobPostingTime
            }

            // If no reliable sorting criteria, use number of resumes as a proxy for activity
            return app1.resumes.count > app2.resumes.count
        }

        // Return the most recently modified app's selected resume
        return sortedApps.first?.selectedRes
    }
}
