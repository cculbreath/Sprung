//
//  NewAppSheetView.swift
//  Sprung
//
//
import Foundation
import SwiftUI
struct NewAppSheetView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @State private var isLoading: Bool = false
    @State private var urlText: String = ""
    @State private var delayed: Bool = false
    @State private var verydelayed: Bool = false
    @State private var showCloudflareChallenge: Bool = false
    @State private var challengeURL: URL?
    @State private var baddomain: Bool = false
    @State private var errorMessage: String?
    @State private var showError: Bool = false
    @State private var showLinkedInLogin: Bool = false
    @State private var isProcessingJob: Bool = false
    @StateObject private var linkedInSessionManager: LinkedInSessionManager
    @Binding var isPresented: Bool
    @MainActor
    init(isPresented: Binding<Bool>) {
        self.init(isPresented: isPresented, sessionManager: LinkedInSessionManager())
    }
    @MainActor
    init(isPresented: Binding<Bool>, sessionManager: LinkedInSessionManager) {
        _isPresented = isPresented
        _linkedInSessionManager = StateObject(wrappedValue: sessionManager)
    }
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
                        Text("The scraping service is taking longer than expected. Retrying in 200 seconds.")
                            .font(.caption)
                    }
                    if baddomain {
                        VStack(spacing: 12) {
                            Text("This URL is not from a supported job listing site.")
                                .font(.caption)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
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
                           await JobApp.importFromIndeed(urlString: urlString, jobAppStore: jobAppStore) != nil {
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
        // Fallback to ScrapingDog if a key is configured
        guard let scrapingDogApiKey = APIKeyManager.get(.scrapingDog),
              !scrapingDogApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let jobID = linkedinJobId(from: url)
        else {
            await MainActor.run {
                errorMessage = "Direct LinkedIn extraction failed and no ScrapingDog API key is configured. Add a key from Settings to enable fallback scraping."
                showError = true
                isLoading = false
            }
            return
        }
        await fetchLinkedInWithScrapingDog(jobID: jobID, postingURL: url, apiKey: scrapingDogApiKey)
    }
    private func fetchLinkedInWithScrapingDog(jobID: String, postingURL: URL, apiKey: String) async {
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
               httpResponse.statusCode != 200 {
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
                jobDetail.postingURL = postingURL.absoluteString
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
    private func linkedinJobId(from url: URL) -> String? {
        let candidates = url.pathComponents.reversed()
        for component in candidates where !component.isEmpty && component != "view" {
            if component.allSatisfy(\.isNumber) {
                return component
            }
        }
        return nil
    }
}
