//
//  NewAppSheetView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/1/24.
//

import Foundation
import SwiftUI

struct NewAppSheetView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore

    @AppStorage("scrapingDogApiKey") var scrapingDogApiKey: String = "none"
    @AppStorage("proxycurlApiKey") var proxycurlApiKey: String = "none"

    @AppStorage("preferredApi") var preferredApi: apis = .scrapingDog

    @State private var isLoading: Bool = false
    @State private var urlText: String = ""
    @State private var delayed: Bool = false
    @State private var verydelayed: Bool = false
    @State private var showCloudflareChallenge: Bool = false
    @State private var challengeURL: URL? = nil
    @State private var baddomain: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showError: Bool = false
    @State private var showLinkedInLogin: Bool = false
    @State private var isProcessingJob: Bool = false
    @StateObject private var linkedInSessionManager = LinkedInSessionManager.shared

    @Binding var isPresented: Bool

    var body: some View {
        VStack {
            if isLoading {
                VStack {
                    ProgressView("Fetching job details...")
                        .progressViewStyle(CircularProgressViewStyle())
                        .padding()
                    if delayed {
                        Text("Fetch results not ready. Trying again in 10s").font(.caption)
                    }
                    if verydelayed {
                        Text("Something suss going on with scraper. Trying again in 200s").font(.caption)
                    }
                    if baddomain {
                        VStack { Text("URL does not is not a supported job listing site").font(.caption).padding()
                            Button("OK") {
                                isLoading = false
                                isPresented = false
                            }
                        }
                    }
                    if showError, let errorMessage {
                        VStack(spacing: 12) {
                            Text("Error")
                                .font(.headline)
                                .foregroundColor(.red)
                            Text(errorMessage)
                                .font(.body)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            Text("Please check the URL and try again, or contact support if the problem persists.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            Button("OK") {
                                showError = false
                                isLoading = false
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                    }
                }
            } else {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Add New Job Application")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Import job details from LinkedIn, Indeed, or Apple")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    // LinkedIn session status
                    LinkedInSessionStatusView(sessionManager: linkedInSessionManager)
                    
                    // URL input section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Job URL")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        TextField(
                            "https://www.linkedin.com/jobs/view/4261198037", 
                            text: $urlText
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                        .onSubmit {
                            Task {
                                await handleNewApp()
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        Button("Cancel") {
                            isPresented = false
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                        
                        Button("Import Job") {
                            Task {
                                await handleNewApp()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .padding()
        .sheet(isPresented: $showCloudflareChallenge) {
            if let challengeURL {
                CloudflareChallengeView(url: challengeURL, isPresented: $showCloudflareChallenge) {
                    // After success retry the import
                    Task {
                        isLoading = true
                        if let urlString = challengeURL.absoluteString as String?,
                           let _ = await JobApp.importFromIndeed(urlString: urlString, jobAppStore: jobAppStore)
                        {
                            isLoading = false
                            isPresented = false
                        } else {
                            isLoading = false
                        }
                    }
                }.defaultSize()
            }
        }
        .sheet(isPresented: $showLinkedInLogin) {
            LinkedInLoginSheet(
                isPresented: $showLinkedInLogin,
                sessionManager: linkedInSessionManager
            ) {
                // After successful login, retry the job import
                Task {
                    guard let retryURL = URL(string: urlText) else {
                        await MainActor.run {
                            errorMessage = "Invalid URL format. Please check and try again."
                            showError = true
                        }
                        return
                    }
                    await handleLinkedInJob(url: retryURL)
                }
            }
        }
    }

    private func handleNewApp() async {
        Logger.info("🚀 Starting job URL fetch for: \(urlText)")
        if let url = URL(string: urlText) {
            switch url.host {
            case "www.linkedin.com":
                await handleLinkedInJob(url: url)
            case "jobs.apple.com":
                isLoading = true
                Task {
                    do {
                        let htmlContent = try await JobApp.fetchHTMLContent(from: urlText)
                        JobApp.parseAppleJobListing(
                            jobAppStore: jobAppStore, html: htmlContent, url: urlText
                        )
                        Logger.info("✅ Successfully imported job from Apple")

                        isLoading = false
                        isPresented = false
                    } catch {
                        Logger.error("🚨 Apple job fetch error: \(error)")
                        await MainActor.run {
                            errorMessage = "Failed to fetch Apple job listing: \(error.localizedDescription)"
                            showError = true
                            isLoading = false
                        }
                    }
                }
            case "www.indeed.com", "indeed.com":
                isLoading = true
                Task {
                    if let jobApp = await JobApp.importFromIndeed(urlString: urlText, jobAppStore: jobAppStore) {
                        Logger.info("✅ Successfully imported job from Indeed: \(jobApp.jobPosition)")
                        isLoading = false
                        isPresented = false
                    } else {
                        // Failed to import - likely Cloudflare challenge or other error
                        Logger.warning("⚠️ Indeed import failed for URL: \(urlText)")
                        isLoading = false
                        if let u = URL(string: urlText) {
                            challengeURL = u
                            showCloudflareChallenge = true
                        } else {
                            errorMessage = "Failed to import from Indeed: Invalid URL"
                            showError = true
                        }
                    }
                }
            default:
                baddomain = true
            }
            return
        }
        // Invalid URL path
        await MainActor.run {
            errorMessage = "Invalid URL format. Please enter a valid job listing URL."
            showError = true
        }
    }
    
    private func handleLinkedInJob(url: URL) async {
        // Prevent duplicate processing
        guard !isProcessingJob else {
            Logger.debug("🔄 [NewAppSheetView] Already processing LinkedIn job, ignoring duplicate call")
            return
        }
        
        await MainActor.run {
            isProcessingJob = true
            isLoading = true
        }
        
        defer {
            Task { @MainActor in
                isProcessingJob = false
            }
        }
        
        // Check if user is logged in to LinkedIn
        if !linkedInSessionManager.isLoggedIn {
            await MainActor.run {
                isLoading = false
                showLinkedInLogin = true
            }
            return
        }
        
        // Try direct LinkedIn extraction first
        if await JobApp.extractLinkedInJobDetails(
            from: url.absoluteString,
            jobAppStore: jobAppStore,
            sessionManager: linkedInSessionManager
        ) != nil {
            await MainActor.run {
                isLoading = false
                isPresented = false
            }
            return
        }
        
        // Fallback to API-based extraction if direct extraction fails
        if preferredApi == .scrapingDog {
            if let jobID = url.pathComponents.last {
                await ScrapingDogfetchLinkedInJobDetails(jobID: jobID, posting_url: url)
            } else {
                await MainActor.run {
                    errorMessage = "Could not extract job ID from LinkedIn URL"
                    showError = true
                    isLoading = false
                }
            }
        } else {
            // Proxycurl is discontinued
            await MainActor.run {
                errorMessage = "Proxycurl service has been discontinued. Please use direct LinkedIn extraction or ScrapingDog API."
                showError = true
                isLoading = false
            }
        }
    }

    private func ScrapingDogfetchLinkedInJobDetails(jobID: String, posting_url: URL) async {
        let apiKey = scrapingDogApiKey
        let requestURL =
            "https://api.scrapingdog.com/linkedinjobs?api_key=\(apiKey)&job_id=\(jobID)"

        guard let url = URL(string: requestURL) else { return }

        do {
            // Create URLSession with 60 second timeout
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 60.0
            config.timeoutIntervalForResource = 60.0
            let session = URLSession(configuration: config)
            
            let (data, response) = try await session.data(from: url)

            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode != 200
            {
                // Handle HTTP error (non-200 status code)
                Logger.error("🚨 ScrapingDog HTTP error: \(httpResponse.statusCode)")
                await MainActor.run {
                    errorMessage = "HTTP Error: \(httpResponse.statusCode)"
                    showError = true
                    isLoading = false
                }
                return
            }

            let jobDetails = try JSONDecoder().decode([JobApp].self, from: data)
            if let jobDetail = jobDetails.first {
                jobDetail.postingURL = posting_url.absoluteString
                jobAppStore.selectedApp = jobAppStore.addJobApp(jobDetail)
                Logger.info("✅ Successfully imported job from ScrapingDog: \(jobDetail.jobPosition)")
                isPresented = false
            }
        } catch {
            // Handle network or decoding error
            Logger.error("🚨 ScrapingDog fetch error: \(error)")
            await MainActor.run {
                errorMessage = "Network or parsing error: \(error.localizedDescription)"
                showError = true
                isLoading = false
            }
            return
        }

        isLoading = false
    }


    private func ProxycurlfetchLinkedInJobDetails(posting_url: URL) async {
        let apiKey = proxycurlApiKey

        // Build the URL with the job URL as a query parameter
        let baseURL = "https://nubela.co/proxycurl/api/linkedin/job"
        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "url", value: posting_url.absoluteString),
        ]

        guard let requestURL = components?.url else {
            isLoading = false
            return
        }

        // Create request with authorization header
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    // Process successful response
                    if let jobApp = JobApp.parseProxycurlJobApp(
                        jobAppStore: jobAppStore,
                        jsonData: data,
                        postingUrl: posting_url.absoluteString
                    ) {
                        Logger.info("✅ Successfully imported job from Proxycurl: \(jobApp.jobPosition)")
                        isPresented = false
                    }
                } else {
                    // Handle error response
                    Logger.error("🚨 Proxycurl HTTP error: \(httpResponse.statusCode)")
                    await MainActor.run {
                        errorMessage = "HTTP Error: \(httpResponse.statusCode)"
                        showError = true
                        isLoading = false
                    }
                }
            }
        } catch {
            Logger.error("🚨 Proxycurl network error: \(error)")
            await MainActor.run {
                errorMessage = "Network error: \(error.localizedDescription)"
                showError = true
                isLoading = false
            }
        }
    }
    
}
