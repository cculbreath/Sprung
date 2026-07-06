//
//  SiteJobSearchService.swift
//  Sprung
//
//  Orchestration + pure halves of the agentic small-site job search: resolve
//  the user-selected Discovery Anthropic model (never a hardcoded fallback),
//  assemble the task message, drive SiteJobSearchLoop on the shared
//  AnthropicToolLoopRunner, and import submitted listings as `.new` pipeline
//  leads through the same two-stage path as the MCP boards (dedup via
//  `JobAppStore.findDuplicateJobApp`, land instantly with preprocessing
//  deferred, then `JobLeadEnrichmentService` fetches the full posting in the
//  background). JobSearchView keeps only the thin async glue + UI state.
//

import Foundation

@MainActor
enum SiteJobSearchService {

    /// Prompt template resource (Sprung/Resources/Prompts/site_job_search.txt).
    static let promptResourceName = "site_job_search"

    // MARK: - Run

    /// Run the agent loop against one site and return its submission. The
    /// model comes from the same Discovery Anthropic setting the events loop
    /// uses; `ModelConfigurationError` propagates when unconfigured. Cancel
    /// the owning task to stop the loop cooperatively between turns.
    static func run(
        siteURL: URL,
        guidance: String,
        llmFacade: LLMFacade,
        onProgress: (@MainActor (String) async -> Void)? = nil
    ) async throws -> SiteJobSearchSubmission {
        let modelId = try ModelConfigResolver.resolve(
            key: DiscoveryAgentService.anthropicModelSettingKey,
            operation: "Site Job Search"
        )
        let systemPrompt = try loadPromptTemplate()
        let loop = SiteJobSearchLoop(
            llmFacade: llmFacade,
            modelId: modelId,
            systemPrompt: systemPrompt,
            userMessage: userMessage(siteURL: siteURL, guidance: guidance, today: Date()),
            onProgress: onProgress
        )
        return try await AnthropicToolLoopRunner(delegate: loop).run()
    }

    private static func loadPromptTemplate() throws -> String {
        guard let url = Bundle.main.url(forResource: promptResourceName, withExtension: "txt", subdirectory: "Prompts"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            Logger.error("Failed to load prompt template: \(promptResourceName)", category: .ai)
            throw SiteJobSearchError.promptTemplateMissing(promptResourceName)
        }
        return content
    }

    // MARK: - Input Normalization (pure — covered by SiteJobSearchLoopTests)

    /// Normalize the user-typed site address into a fetchable URL: trim, add
    /// an https scheme when none was typed ("austinjobs.com" is the natural
    /// way to type it), and require an http(s) URL with a dotted host.
    /// Returns nil when the input can't name a site.
    static func normalizedSiteURL(_ raw: String) -> URL? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.lowercased().hasPrefix("http://") && !trimmed.lowercased().hasPrefix("https://") {
            trimmed = "https://" + trimmed
        }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, host.contains(".") else {
            return nil
        }
        return url
    }

    // MARK: - Task-Message Assembly (pure — covered by SiteJobSearchLoopTests)

    /// Build the task message: the site to search (plus its bare host for
    /// site: search operators), today's date, and the optional user guidance
    /// block — delimited so the prompt can scope it to steering, never to
    /// waiving page verification.
    static func userMessage(siteURL: URL, guidance: String, today: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        var message = """
            Search this job site for current openings and submit page-verified postings.

            SITE: \(siteURL.absoluteString)
            SITE HOST (for site: search operators): \(siteURL.host ?? siteURL.absoluteString)
            Today: \(formatter.string(from: today))
            """
        let trimmedGuidance = guidance.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedGuidance.isEmpty {
            message += "\n\n## SEARCH GUIDANCE FROM THE USER\n\(trimmedGuidance)"
        }
        return message
    }

    // MARK: - Mapping (pure — covered by SiteJobSearchImportTests)

    /// Map a submitted listing to a fresh `.new` JobApp lead. The agent's
    /// summary (a faithful condensation of the fetched posting page) lands as
    /// the stand-in description; enrichment fetches the full posting later.
    /// Returns nil when the listing lacks the essentials for a useful card.
    /// `siteHost` labels the lead's source with the site it came from.
    static func makeJobApp(from listing: SiteJobListing, siteHost: String) -> JobApp? {
        let title = listing.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let company = listing.company.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !company.isEmpty, !listing.url.isEmpty else {
            return nil
        }
        let jobApp = JobApp()
        jobApp.jobPosition = title
        jobApp.companyName = company
        jobApp.jobLocation = listing.location ?? ""
        jobApp.jobDescription = listing.summary
        // The agent submits the posting's canonical detail-page URL verbatim —
        // no query-stripping normalization here; on arbitrary small boards the
        // query string is often the posting's identity (?jobId=…).
        jobApp.postingURL = listing.url
        jobApp.jobApplyLink = listing.url
        if let salary = listing.salary, !salary.isEmpty {
            jobApp.salary = salary
        }
        if let postedDate = listing.postedDate, !postedDate.isEmpty {
            jobApp.jobPostingTime = postedDate
        }
        jobApp.status = .new
        jobApp.identifiedDate = Date()
        jobApp.source = siteHost
        return jobApp
    }

    // MARK: - Import (same two-stage pipeline as the MCP boards)

    /// Import a submitted listing as a `.new` pipeline lead. Dedup runs
    /// through the shared `JobAppStore.findDuplicateJobApp` (URL match,
    /// falling back to title+company); the lead lands instantly with the
    /// agent's summary as a stand-in description and preprocessing deferred
    /// to `JobLeadEnrichmentService`, which fetches the full posting behind
    /// the canonical URL in the background.
    @discardableResult
    static func importAsLead(
        _ listing: SiteJobListing,
        siteHost: String,
        into store: JobAppStore
    ) -> JobMCPImportService.ImportOutcome {
        guard let jobApp = makeJobApp(from: listing, siteHost: siteHost) else {
            return .skipped(reason: "missing title, company, or URL")
        }
        if let existing = store.findDuplicateJobApp(url: jobApp.postingURL, title: jobApp.jobPosition, company: jobApp.companyName) {
            return .duplicate(existing)
        }
        guard let inserted = store.addJobApp(jobApp, deferringPreprocessing: true) else {
            return .skipped(reason: "the job couldn't be saved")
        }
        store.leadEnrichment.enqueue(inserted, store: store)
        return .imported(inserted)
    }

    /// Whether a submitted listing's canonical URL is already in the pipeline
    /// (for the "Imported" badge — same URL-keyed affordance as Dice rows).
    static func isImported(_ listing: SiteJobListing, importedURLs: Set<String>) -> Bool {
        importedURLs.contains(listing.url)
    }
}
