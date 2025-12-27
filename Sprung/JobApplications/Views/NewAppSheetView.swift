//
//  NewAppSheetView.swift
//  Sprung
//
//
import Foundation
import SwiftUI
import SwiftOpenAI

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
    @State private var llmStatusMessage: String = ""
    @StateObject private var linkedInSessionManager: LinkedInSessionManager
    @Binding var isPresented: Bool
    var initialURL: String?

    @MainActor
    init(isPresented: Binding<Bool>, initialURL: String? = nil) {
        self.init(isPresented: isPresented, sessionManager: LinkedInSessionManager(), initialURL: initialURL)
    }
    @MainActor
    init(isPresented: Binding<Bool>, sessionManager: LinkedInSessionManager, initialURL: String? = nil) {
        _isPresented = isPresented
        _linkedInSessionManager = StateObject(wrappedValue: sessionManager)
        self.initialURL = initialURL
    }
    var body: some View {
        VStack {
            if isLoading {
                VStack {
                    if !llmStatusMessage.isEmpty {
                        AnimatedThinkingText(statusMessage: llmStatusMessage)
                            .padding()
                    } else {
                        ProgressView("Fetching job details...")
                            .progressViewStyle(CircularProgressViewStyle())
                            .padding()
                    }
                    if delayed {
                        Text("Fetch results not ready. Trying again in 10s").font(.caption)
                    }
                    if verydelayed {
                        Text("The scraping service is taking longer than expected. Retrying in 200 seconds.")
                            .font(.caption)
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
                        Text("Import job details from any job listing URL")
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
                        Button("Manual Entry") {
                            _ = jobAppStore.createManualEntry()
                            isPresented = false
                            // Switch to listing tab for editing
                            NotificationCenter.default.post(name: .manualJobAppCreated, object: nil)
                        }
                        .buttonStyle(.bordered)
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
        .onAppear {
            if let initialURL = initialURL, !initialURL.isEmpty {
                urlText = initialURL
                Task {
                    await handleNewApp()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .captureJobURLReady)) { notification in
            // Relay notification from AppSheets - fires after sheet is mounted
            if let urlString = notification.userInfo?["url"] as? String, urlText.isEmpty {
                Logger.info("📥 [NewAppSheetView] Received capture URL via relay notification: \(urlString)", category: .ui)
                urlText = urlString
                Task {
                    await handleNewApp()
                }
            }
        }
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
                        let htmlContent = try await WebResourceService.fetchHTML(from: url)
                        try JobApp.parseAppleJobListing(
                            jobAppStore: jobAppStore, html: htmlContent, url: urlText
                        )
                        Logger.info("✅ Successfully imported job from Apple")
                        isLoading = false
                        isPresented = false
                    } catch {
                        Logger.error("🚨 Apple job import error: \(error)")
                        await MainActor.run {
                            errorMessage = "Failed to import Apple job listing: \(error.localizedDescription)"
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
                // Use LLM with web search for unknown domains
                await handleLLMImport(url: url)
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
        // Try direct LinkedIn extraction
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
        // Direct extraction failed
        await MainActor.run {
            errorMessage = "LinkedIn extraction failed. Please ensure you're logged into LinkedIn and the job posting is still available."
            showError = true
            isLoading = false
        }
    }

    private func handleLLMImport(url: URL) async {
        guard !isProcessingJob else {
            Logger.debug("🔄 [NewAppSheetView] Already processing job, ignoring duplicate call")
            return
        }

        await MainActor.run {
            isProcessingJob = true
            isLoading = true
            llmStatusMessage = "Analyzing job listing..."
        }

        defer {
            Task { @MainActor in
                isProcessingJob = false
                llmStatusMessage = ""
            }
        }

        // Check for OpenAI API key
        guard let apiKey = APIKeyManager.get(.openAI), !apiKey.isEmpty else {
            await MainActor.run {
                errorMessage = "OpenAI API key required to import from this site. Add your key in Settings."
                showError = true
                isLoading = false
            }
            return
        }

        Logger.info("🤖 [NewAppSheetView] Starting LLM import for: \(url.absoluteString)", category: .ai)

        let service = OpenAIServiceFactory.service(apiKey: apiKey)

        let systemPrompt = """
        You are a job listing data extractor. When given a job listing URL, use web search to fetch the page and extract structured job information.
        Extract ALL available information from the job posting. For job_description, include the COMPLETE description with all responsibilities, requirements, qualifications, and any other details. Do not summarize or truncate.
        For any field where the information is not provided on the job listing, use "Not specified" as the value.
        """

        let userMessage = "Extract all job information from: \(url.absoluteString)"

        // Build JSON schema for structured output
        let jobSchema = JSONSchema(
            type: .object,
            description: "Extracted job listing information",
            properties: [
                "job_title": JSONSchema(type: .string, description: "The exact job title as shown in the posting"),
                "company": JSONSchema(type: .string, description: "Company name"),
                "location": JSONSchema(type: .string, description: "Job location (city, state/country)"),
                "workplace_type": JSONSchema(type: .string, description: "Remote, Hybrid, Onsite, or Flexible"),
                "employment_type": JSONSchema(type: .string, description: "Full-time, Part-time, Contract, Internship, etc."),
                "seniority_level": JSONSchema(type: .string, description: "Entry, Mid, Senior, Lead, Director, etc. if mentioned"),
                "industries": JSONSchema(type: .string, description: "Relevant industries or sectors"),
                "posted_date": JSONSchema(type: .string, description: "When the job was posted, if available"),
                "salary": JSONSchema(type: .string, description: "Salary range or compensation details if mentioned"),
                "job_description": JSONSchema(type: .string, description: "The COMPLETE job description including all responsibilities, requirements, qualifications, benefits, and any other details. Do not summarize."),
                "apply_link": JSONSchema(type: .string, description: "Direct application URL if different from the source URL")
            ],
            required: ["job_title", "company", "location", "workplace_type", "employment_type", "seniority_level", "industries", "posted_date", "salary", "job_description", "apply_link"],
            additionalProperties: false
        )

        let textConfig = TextConfiguration(format: .jsonSchema(jobSchema, name: "job_listing"))

        do {
            let developerMessage = InputMessage(role: "developer", content: .text(systemPrompt))
            let userInputMessage = InputMessage(role: "user", content: .text(userMessage))
            let inputItems: [InputItem] = [.message(developerMessage), .message(userInputMessage)]

            let webSearchTool = Tool.webSearch(Tool.WebSearchTool(type: .webSearch, userLocation: nil))
            let reasoning = Reasoning(effort: "low")

            let parameters = ModelResponseParameter(
                input: .array(inputItems),
                model: .gpt5,
                reasoning: reasoning,
                store: true,
                stream: true,
                text: textConfig,
                toolChoice: .auto,
                tools: [webSearchTool]
            )

            var finalResponse: ResponseModel?
            let stream = try await service.responseCreateStream(parameters)

            for try await event in stream {
                switch event {
                case .responseCompleted(let completed):
                    finalResponse = completed.response
                case .webSearchCallSearching:
                    await MainActor.run { llmStatusMessage = "Searching the web..." }
                case .webSearchCallCompleted:
                    await MainActor.run { llmStatusMessage = "Processing results..." }
                default:
                    break
                }
            }

            guard let response = finalResponse,
                  let outputText = extractLLMResponseText(from: response) else {
                await MainActor.run {
                    errorMessage = "No response from AI. Please try again."
                    showError = true
                    isLoading = false
                }
                return
            }

            // Log full JSON response for debugging
            Logger.info("📄 [LLM] Full JSON response:\n\(outputText)", category: .ai)

            // Parse the JSON response
            guard let jobApp = parseLLMJobJSON(outputText, sourceURL: url.absoluteString) else {
                await MainActor.run {
                    errorMessage = "Failed to extract job details from this page. The listing may not be accessible."
                    showError = true
                    isLoading = false
                }
                return
            }

            // Check for duplicates
            if let existingJob = jobAppStore.jobApps.first(where: { $0.postingURL == url.absoluteString }) {
                Logger.info("📋 [LLM] Job already exists, selecting it", category: .ai)
                await MainActor.run {
                    jobAppStore.selectedApp = existingJob
                    isLoading = false
                    isPresented = false
                }
                return
            }

            // Add to store
            await MainActor.run {
                jobAppStore.selectedApp = jobAppStore.addJobApp(jobApp)
                Logger.info("✅ [LLM] Successfully imported: \(jobApp.jobPosition) at \(jobApp.companyName)", category: .ai)
                isLoading = false
                isPresented = false
            }

        } catch {
            Logger.error("🚨 [LLM] Import error: \(error)", category: .ai)
            await MainActor.run {
                errorMessage = "Failed to import job: \(error.localizedDescription)"
                showError = true
                isLoading = false
            }
        }
    }

    // MARK: - LLM Helpers

    private func extractLLMResponseText(from response: ResponseModel) -> String? {
        for item in response.output {
            if case .message(let message) = item {
                for content in message.content {
                    if case .outputText(let text) = content {
                        return text.text
                    }
                }
            }
        }
        return nil
    }

    private func parseLLMJobJSON(_ jsonString: String, sourceURL: String) -> JobApp? {
        // Clean up the JSON string (remove markdown code blocks if present)
        var cleaned = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Logger.error("🚨 [LLM] Failed to parse JSON: \(cleaned.prefix(200))", category: .ai)
            return nil
        }

        let jobApp = JobApp()
        jobApp.postingURL = sourceURL
        jobApp.jobPosition = json["job_title"] as? String ?? ""
        jobApp.companyName = json["company"] as? String ?? ""
        jobApp.jobLocation = json["location"] as? String ?? ""
        jobApp.employmentType = json["employment_type"] as? String ?? ""
        jobApp.seniorityLevel = json["seniority_level"] as? String ?? ""
        jobApp.industries = json["industries"] as? String ?? ""
        jobApp.jobPostingTime = json["posted_date"] as? String ?? ""
        jobApp.jobDescription = json["job_description"] as? String ?? ""

        if let applyLink = json["apply_link"] as? String, !applyLink.isEmpty {
            jobApp.jobApplyLink = applyLink
        } else {
            jobApp.jobApplyLink = sourceURL
        }

        // Extract salary to dedicated field
        if let salary = json["salary"] as? String, !salary.isEmpty, salary != "Not specified" {
            jobApp.salary = salary
            Logger.debug("💰 [LLM] Extracted salary: \(salary)", category: .ai)
        }

        // Add workplace type to employment type if present
        if let workplaceType = json["workplace_type"] as? String, !workplaceType.isEmpty {
            if jobApp.employmentType.isEmpty {
                jobApp.employmentType = workplaceType
            } else {
                jobApp.employmentType += " (\(workplaceType))"
            }
        }

        jobApp.status = .new
        jobApp.stage = .identified
        jobApp.identifiedDate = Date()
        jobApp.source = "LLM Import"

        // Validate we got essential data
        guard !jobApp.jobPosition.isEmpty && !jobApp.companyName.isEmpty else {
            Logger.warning("⚠️ [LLM] Missing essential data (title or company)", category: .ai)
            return nil
        }

        return jobApp
    }
}
