//
//  NewAppSheetView.swift
//  Sprung
//
//
import Foundation
import SwiftUI

struct NewAppSheetView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(LinkedInMCPServerService.self) private var linkedInMCPServer
    @Environment(LLMFacade.self) private var llmFacade: LLMFacade
    @State private var isLoading: Bool = false
    @State private var urlText: String = ""
    @State private var errorMessage: String?
    @State private var showError: Bool = false
    @State private var isProcessingJob: Bool = false
    @State private var llmStatusMessage: String = ""
    @Binding var isPresented: Bool
    var initialURL: String?

    init(isPresented: Binding<Bool>, initialURL: String? = nil) {
        _isPresented = isPresented
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
                    ModalFooterView(
                        primaryLabel: "Import Job",
                        isDisabled: urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        secondaryLabel: "Manual Entry",
                        onSecondary: {
                            _ = jobAppStore.createManualEntry()
                            isPresented = false
                            // Switch to listing tab for editing
                            NotificationCenter.default.post(name: .manualJobAppCreated, object: nil)
                        },
                        onCancel: { isPresented = false },
                        onPrimary: { Task { await handleNewApp() } }
                    )
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
    }
    private func handleNewApp() async {
        Logger.info("🚀 Starting job URL fetch for: \(urlText)")
        if let url = URL(string: urlText) {
            switch url.host {
            case "www.linkedin.com", "linkedin.com":
                if let jobId = LinkedInJobDetailsService.jobId(fromURL: url.absoluteString) {
                    await handleLinkedInJob(jobId: jobId)
                } else {
                    // Non-job-view LinkedIn URLs name no job id — they route
                    // through the generic URL importer like any other host.
                    await handleLLMImport(url: url)
                }
            default:
                // Every non-LinkedIn host goes through the generic LLM importer
                // — the single import path for pasted job URLs.
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
    /// Import a LinkedIn job by id: fetch the posting text over the local MCP
    /// server (`get_job_details`), then run the same structured extraction the
    /// generic URL importer uses — on the supplied text instead of web search.
    /// Errors (no browser session, budget, server, extraction) surface in the
    /// sheet's error panel; nothing degrades silently.
    private func handleLinkedInJob(jobId: String) async {
        guard !isProcessingJob else {
            Logger.debug("🔄 [NewAppSheetView] Already processing LinkedIn job, ignoring duplicate call")
            return
        }
        await MainActor.run {
            isProcessingJob = true
            isLoading = true
            llmStatusMessage = "Fetching LinkedIn job posting..."
        }
        defer {
            Task { @MainActor in
                isProcessingJob = false
                llmStatusMessage = ""
            }
        }

        // The canonical URL is the job's stable identity (shared with the
        // LinkedIn search board's leads) — dedup before spending a budgeted
        // LinkedIn call and an extraction pass.
        let canonicalURL = LinkedInMCPImportService.canonicalJobURL(jobID: jobId)
        if let existingJob = jobAppStore.jobApps.first(where: { $0.postingURL == canonicalURL }) {
            Logger.info("📋 [LinkedIn] Job already exists, selecting it", category: .ai)
            await MainActor.run {
                jobAppStore.selectedApp = existingJob
                isLoading = false
                isPresented = false
            }
            return
        }

        do {
            // Resolve the configured model up front (no hardcoded default —
            // surface the picker) before the budgeted LinkedIn call.
            let modelId = try JobURLImportService.requireJobImportModelId(operationName: "LinkedIn Job Import")

            let postingText = try await LinkedInJobDetailsService.fetchPostingText(
                jobId: jobId,
                serverService: linkedInMCPServer
            )
            await MainActor.run { llmStatusMessage = "Extracting job details..." }

            // Extract from the MCP-supplied posting text — no web step.
            let jobApp = try await runJobImport(
                mode: .text(postingText), sourceURL: canonicalURL, modelId: modelId
            )
            jobApp.source = "LinkedIn"

            // Same downstream dedup as the LLM-import path (title+company net).
            if let existingJob = jobAppStore.findDuplicateJobApp(
                url: canonicalURL,
                title: jobApp.jobPosition,
                company: jobApp.companyName
            ) {
                Logger.info("📋 [LinkedIn] Job already exists, selecting it", category: .ai)
                await MainActor.run {
                    jobAppStore.selectedApp = existingJob
                    isLoading = false
                    isPresented = false
                }
                return
            }

            await MainActor.run {
                jobAppStore.selectedApp = jobAppStore.addJobApp(jobApp)
                Logger.info("✅ [LinkedIn] Imported: \(jobApp.jobPosition) at \(jobApp.companyName)", category: .ai)
                isLoading = false
                isPresented = false
            }
        } catch {
            Logger.error("🚨 [LinkedIn] Import failed: \(error.localizedDescription)", category: .ai)
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
            }
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

        Logger.info("🤖 [NewAppSheetView] Starting LLM import for: \(url.absoluteString)", category: .ai)

        // Resolve the configured Job Import model (no hardcoded default — surface the picker).
        guard let modelId = UserDefaults.standard.string(forKey: "jobImportModelId"), !modelId.isEmpty else {
            await MainActor.run {
                errorMessage = "No Job Import model configured. Select one in Settings > Models."
                showError = true
                isLoading = false
            }
            return
        }

        do {
            // The agent fetches the posting page itself (server-side web_fetch)
            // and extracts, surfacing progress through llmStatusMessage.
            let jobApp = try await runJobImport(
                mode: .url(url), sourceURL: url.absoluteString, modelId: modelId
            )

            // Check for duplicates. Compare the pasted URL both as-is and in
            // its Dice-normalized form (utm_* tracking query + fragment
            // stripped) — Dice/MCP imports already store `postingURL`
            // normalized this way (see JobMCPImportService.normalizedPostingURL),
            // so a utm-tagged Dice URL pasted here would otherwise bypass that
            // dedup. Query params are NOT stripped wholesale: some ATS URLs
            // (e.g. Greenhouse `gh_jid`) need them for identity, so only this
            // known-safe normalization is applied, and only for comparison —
            // falls back to JobAppStore's title+company match.
            let rawURLString = url.absoluteString
            let diceNormalizedURLString = JobMCPImportService.normalizedPostingURL(rawURLString)
            let existingJob = jobAppStore.findDuplicateJobApp(
                url: rawURLString,
                title: jobApp.jobPosition,
                company: jobApp.companyName
            ) ?? jobAppStore.jobApps.first(where: { $0.postingURL == diceNormalizedURLString })
            if let existingJob {
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

    /// Run the Anthropic job-import agent for either variant, threading its
    /// progress lines into the sheet's status text.
    @MainActor
    private func runJobImport(
        mode: JobImportLoop.Mode,
        sourceURL: String,
        modelId: String
    ) async throws -> JobApp {
        let loop = JobImportLoop(
            mode: mode,
            sourceURL: sourceURL,
            llmFacade: llmFacade,
            modelId: modelId,
            onProgress: { message in llmStatusMessage = message }
        )
        return try await AnthropicToolLoopRunner(delegate: loop).run()
    }

}
