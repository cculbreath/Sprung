//
//  LinkedInJobScrape.swift
//  Sprung
//
import Foundation
import SwiftSoup
import WebKit
import ObjectiveC
// MARK: - LinkedIn Session Manager
private enum LinkedInScrapeTiming {
    static let requestTimeout: TimeInterval = 60
    static let fallbackCheckInterval: TimeInterval = 2
    static let navigationTransitionDelay: TimeInterval = 2
    static let dynamicContentDelay: TimeInterval = 3
    static let debugWindowRevealDelay: TimeInterval = 10
    static let debugWindowCloseDelay: TimeInterval = 3
    static let ultimateTimeout: TimeInterval = 60
    static let timeoutDebugWindowDuration: TimeInterval = 10
}
private enum LinkedInScrapeAssociatedKeys {
    static var delegateKey: UInt8 = 0
}
@MainActor
class LinkedInSessionManager: ObservableObject {
    @Published var isLoggedIn = false
    @Published var sessionExpired = false
    private var webView: WKWebView?
    init() {
        setupWebView()
    }
    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: config)
    }
    func clearSession() {
        webView?.configuration.websiteDataStore.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: Date.distantPast
        ) { }
        isLoggedIn = false
        sessionExpired = false
    }
    func getAuthenticatedWebView() -> WKWebView? {
        return webView
    }
}
// MARK: - LinkedIn Job Extractor
extension JobApp {
    /// Attempts to extract job information directly from LinkedIn using an authenticated session
    @MainActor
    static func extractLinkedInJobDetails(
        from urlString: String,
        jobAppStore: JobAppStore,
        sessionManager: LinkedInSessionManager
    ) async -> JobApp? {
        guard let url = URL(string: urlString) else {
            Logger.error("🚨 Invalid LinkedIn URL: \(urlString)")
            return nil
        }
        // Check if we have a valid session
        if !sessionManager.isLoggedIn {
            Logger.warning("⚠️ No LinkedIn session found, login required")
            return nil
        }
        // Create a new WebView for scraping that shares the same session
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        let scrapingWebView = WKWebView(frame: .zero, configuration: config)
        Logger.debug("🔍 [LinkedIn Scraper] Created dedicated scraping WebView with shared session")

        // Helper to clean up the WebView synchronously (must be called on main thread)
        func cleanupWebView() {
            scrapingWebView.navigationDelegate = nil
            scrapingWebView.stopLoading()
            scrapingWebView.removeFromSuperview()
            Logger.debug("🧹 [LinkedIn Scraper] Cleaned up scraping WebView")
        }

        do {
            Logger.info("🚀 Starting LinkedIn job extraction for: \(urlString)")
            // Load the job page using dedicated scraping WebView
            let html = try await loadJobPageHTML(webView: scrapingWebView, url: url)

            // Clean up the WebView synchronously since we're already on MainActor
            cleanupWebView()

            // Parse the HTML using SwiftSoup
            if let jobApp = parseLinkedInJobListing(html: html, url: urlString) {
                jobAppStore.selectedApp = jobAppStore.addJobApp(jobApp)
                Logger.info("✅ Successfully extracted LinkedIn job: \(jobApp.jobPosition)")
                return jobApp
            } else {
                Logger.error("🚨 Failed to parse LinkedIn job data")
                return nil
            }
        } catch let error as URLError {
            cleanupWebView()
            switch error.code {
            case .timedOut:
                Logger.error(
                    "🚨 LinkedIn job extraction timed out - page took too long to load"
                )
                Logger.error("   This could be due to slow network, LinkedIn anti-bot detection, or heavy page content")
            case .notConnectedToInternet:
                Logger.error("🚨 LinkedIn job extraction failed - no internet connection")
            case .cannotFindHost:
                Logger.error("🚨 LinkedIn job extraction failed - cannot reach LinkedIn servers")
            default:
                Logger.error("🚨 LinkedIn job extraction failed with URL error: \(error.localizedDescription)")
            }
            return nil
        } catch {
            cleanupWebView()
            Logger.error("🚨 LinkedIn job extraction failed: \(error)")
            return nil
        }
    }
    /// Load job page HTML using authenticated WebView with debug window
    private static func loadJobPageHTML(webView: WKWebView, url: URL) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            var debugWindow: NSWindow?
            var originalDelegate: WKNavigationDelegate?

            // Track all pending work items so we can cancel them on completion
            var pendingWorkItems: [DispatchWorkItem] = []

            // Helper to cancel all pending work items
            func cancelAllPendingWork() {
                for item in pendingWorkItems {
                    item.cancel()
                }
                pendingWorkItems.removeAll()
            }

            // Helper to schedule cancellable work
            func scheduleWork(after delay: TimeInterval, block: @escaping () -> Void) {
                let workItem = DispatchWorkItem { [weak webView] in
                    guard webView != nil else { return }
                    block()
                }
                pendingWorkItems.append(workItem)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
            }

            // Ensure WebView operations happen on main thread
            DispatchQueue.main.async {
                Logger.debug("🌐 [LinkedIn Scraper] Loading job page via LinkedIn feed first: \(url.absoluteString)")
                // Create debug window but don't show it yet
                debugWindow = NSWindow(
                    contentRect: CGRect(x: 0, y: 0, width: 1000, height: 700),
                    styleMask: [.titled, .closable, .resizable],
                    backing: .buffered,
                    defer: false
                )
                debugWindow?.title = "LinkedIn Job Page Debug - \(url.lastPathComponent)"
                debugWindow?.contentView = webView
                debugWindow?.center()
                Logger.debug("🪟 [LinkedIn Scraper] Debug window created but hidden - will show if scraping takes >10s")
                // Store original delegate and set up new one
                originalDelegate = webView.navigationDelegate

                // Create scrapeDelegate variable first so we can reference it in the completion
                var scrapeDelegate: LinkedInJobScrapeDelegate?
                scrapeDelegate = LinkedInJobScrapeDelegate(targetURL: url) { [weak webView] result in
                    guard !hasResumed else {
                        Logger.debug("🔍 [LinkedIn Scraper] Delegate callback fired but already resumed")
                        return
                    }
                    hasResumed = true

                    // Cancel all pending work items immediately to prevent use-after-free
                    cancelAllPendingWork()

                    // Cancel delegate's pending work as well
                    scrapeDelegate?.cancelAllPendingWork()

                    // Restore original delegate and clean up immediately to prevent crashes
                    if let webView = webView {
                        webView.navigationDelegate = originalDelegate
                        webView.stopLoading()
                        objc_setAssociatedObject(
                            webView,
                            &LinkedInScrapeAssociatedKeys.delegateKey,
                            nil,
                            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
                        )
                    }

                    switch result {
                    case .success(let html):
                        Logger.debug("✅ [LinkedIn Scraper] Successfully loaded page HTML (\(html.count) characters)")
                    case .failure(let error):
                        Logger.error("🚨 [LinkedIn Scraper] Failed to load page: \(error)")
                    }

                    // Close debug window immediately if visible
                    if debugWindow?.isVisible == true {
                        debugWindow?.close()
                    }

                    continuation.resume(with: result)
                }
                webView.navigationDelegate = scrapeDelegate
                objc_setAssociatedObject(
                    webView,
                    &LinkedInScrapeAssociatedKeys.delegateKey,
                    scrapeDelegate,
                    .OBJC_ASSOCIATION_RETAIN_NONATOMIC
                )
                // Start by loading LinkedIn feed to establish session context
                let feedURL = URL(string: "https://www.linkedin.com/feed/")!
                var request = URLRequest(url: feedURL)
                request.setValue(
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                    forHTTPHeaderField: "User-Agent"
                )
                request.setValue(
                    "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                    forHTTPHeaderField: "Accept"
                )
                request.setValue("en-US,en;q=0.5", forHTTPHeaderField: "Accept-Language")
                request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
                request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
                request.timeoutInterval = LinkedInScrapeTiming.requestTimeout
                Logger.debug("🔍 [LinkedIn Scraper] Step 1: Loading LinkedIn feed to establish session")
                webView.load(request)
                // Fallback mechanism: periodically check if the page is loaded
                var fallbackAttempts = 0
                let maxFallbackAttempts = 25 // Check every 2 seconds for 50 seconds (leaving 10s buffer before timeout)
                func checkPageLoaded() {
                    guard !hasResumed else { return }
                    fallbackAttempts += 1
                    Logger.debug("🔍 [LinkedIn Scraper] Fallback check \(fallbackAttempts)/\(maxFallbackAttempts)")
                    // Check if page appears to be loaded by evaluating a simple JavaScript
                    webView.evaluateJavaScript("document.readyState") { result, _ in
                        guard !hasResumed else { return }
                        if let readyState = result as? String, readyState == "complete" {
                            Logger.debug("🔍 [LinkedIn Scraper] Fallback detected page ready state: complete")
                            // Also check what URL we're actually on
                            webView.evaluateJavaScript("window.location.href") { urlResult, _ in
                                if let currentURL = urlResult as? String {
                                    Logger.debug("🔍 [LinkedIn Scraper] Current page URL: \(currentURL)")
                                    if currentURL == "about:blank" {
                                        Logger.warning("⚠️ [LinkedIn Scraper] Page is blank! LinkedIn may have blocked the request")
                                    }
                                }
                            }
                            // Give it a moment more then extract HTML
                            scheduleWork(after: LinkedInScrapeTiming.navigationTransitionDelay) {
                                guard !hasResumed else { return }
                                webView.evaluateJavaScript("document.documentElement.outerHTML") { htmlResult, htmlError in
                                    guard !hasResumed else { return }
                                    hasResumed = true

                                    // Cancel all pending work items
                                    cancelAllPendingWork()
                                    scrapeDelegate?.cancelAllPendingWork()

                                    // Clean up
                                    webView.navigationDelegate = originalDelegate
                                    webView.stopLoading()
                                    objc_setAssociatedObject(
                                        webView,
                                        &LinkedInScrapeAssociatedKeys.delegateKey,
                                        nil,
                                        .OBJC_ASSOCIATION_RETAIN_NONATOMIC
                                    )

                                    if let htmlError = htmlError {
                                        Logger.error("🚨 [LinkedIn Scraper] Fallback HTML extraction failed: \(htmlError)")
                                        continuation.resume(throwing: htmlError)
                                    } else if let html = htmlResult as? String {
                                        Logger.info(
                                            "✅ [LinkedIn Scraper] Fallback successfully extracted HTML (\(html.count) characters)"
                                        )
                                        // Debug: log the actual HTML if it's suspiciously short
                                        if html.count < 1000 {
                                            Logger.warning("⚠️ [LinkedIn Scraper] HTML content seems too short, here's what we got:")
                                            Logger.warning("   \(html.prefix(200))")
                                        }
                                        // Close debug window if visible
                                        if debugWindow?.isVisible == true {
                                            debugWindow?.close()
                                        }
                                        continuation.resume(returning: html)
                                    } else {
                                        Logger.error("🚨 [LinkedIn Scraper] Fallback HTML extraction returned unexpected type")
                                        continuation.resume(throwing: URLError(.cannotDecodeContentData))
                                    }
                                }
                            }
                        } else if fallbackAttempts < maxFallbackAttempts {
                            // Try again after fallback interval
                            scheduleWork(after: LinkedInScrapeTiming.fallbackCheckInterval) {
                                checkPageLoaded()
                            }
                        } else {
                            // Continue trying - the main timeout will handle giving up
                            scheduleWork(after: LinkedInScrapeTiming.fallbackCheckInterval) {
                                checkPageLoaded()
                            }
                        }
                    }
                }
                // Show debug window after 10 seconds if scraping hasn't completed
                scheduleWork(after: LinkedInScrapeTiming.debugWindowRevealDelay) {
                    guard !hasResumed else { return }
                    Logger.info("🪟 [LinkedIn Scraper] Showing debug window - scraping taking longer than expected")
                    debugWindow?.makeKeyAndOrderFront(nil)
                    checkPageLoaded()
                }
                // Ultimate timeout after 60 seconds
                scheduleWork(after: LinkedInScrapeTiming.ultimateTimeout) {
                    guard !hasResumed else { return }
                    hasResumed = true

                    // Cancel all other pending work items
                    cancelAllPendingWork()
                    scrapeDelegate?.cancelAllPendingWork()

                    Logger.warning(
                        "⚠️ [LinkedIn Scraper] Timeout reached after 60 seconds"
                    )
                    // Restore original delegate and clean up to prevent crashes
                    webView.navigationDelegate = originalDelegate
                    webView.stopLoading()
                    objc_setAssociatedObject(
                        webView,
                        &LinkedInScrapeAssociatedKeys.delegateKey,
                        nil,
                        .OBJC_ASSOCIATION_RETAIN_NONATOMIC
                    )
                    // Keep debug window open longer on timeout so we can see what happened
                    Logger.info(
                        "🪟 [LinkedIn Scraper] Debug window will stay open for 10 seconds so you can inspect the page"
                    )
                    // Use a simple dispatch for the window close since we're already completing
                    DispatchQueue.main.asyncAfter(deadline: .now() + LinkedInScrapeTiming.timeoutDebugWindowDuration) { [weak debugWindow] in
                        debugWindow?.close()
                    }
                    continuation.resume(throwing: URLError(.timedOut))
                }
            }
        }
    }
    /// Parse LinkedIn job listing - handles both JSON (from JS scraper) and HTML (legacy)
    static func parseLinkedInJobListing(html: String, url: String) -> JobApp? {
        // Check if this is JSON from the JS scraper
        if html.hasPrefix("__LINKEDIN_JSON__") {
            let jsonString = String(html.dropFirst("__LINKEDIN_JSON__".count))
            return parseLinkedInJobJSON(jsonString, url: url)
        }

        // Legacy HTML parsing with SwiftSoup
        do {
            let doc = try SwiftSoup.parse(html)
            // Create new JobApp instance
            let jobApp = JobApp()
            jobApp.postingURL = url
            // Extract job title - comprehensive selectors for different LinkedIn layouts
            let titleSelectors = [
                // Primary selectors (most common)
                "h1[data-test-id=\"job-title\"]",
                ".job-details-jobs-unified-top-card__job-title h1",
                ".jobs-unified-top-card__job-title h1",
                // 2024+ LinkedIn layout selectors
                ".job-details-jobs-unified-top-card__job-title",
                ".jobs-unified-top-card__job-title",
                ".job-details-module__title",
                // Legacy and alternative selectors
                ".jobs-search__job-title",
                ".job-details__job-title",
                "h1.t-24.t-bold",
                "h1[class*=\"job-title\"]",
                "h1[class*=\"unified-top-card\"]",
                ".jobs-details__main-content h1",
                ".job-view-layout h1",
                // Generic fallbacks
                "h1[data-test*=\"job\"]",
                ".job-posting-title",
                "main h1"
            ]
            for selector in titleSelectors {
                if let element = try? doc.select(selector).first(),
                   let title = try? element.text().trimmingCharacters(in: .whitespacesAndNewlines),
                   !title.isEmpty {
                    jobApp.jobPosition = title
                    Logger.debug("📋 Extracted job title with selector '\(selector)': \(jobApp.jobPosition)")
                    break
                }
            }

            // Fallback: Extract from <title> tag (format: "Job Title | Company | LinkedIn")
            if jobApp.jobPosition.isEmpty {
                if let titleElement = try? doc.select("title").first(),
                   let titleText = try? titleElement.text() {
                    let components = titleText.components(separatedBy: " | ")
                    if components.count >= 2 {
                        jobApp.jobPosition = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
                        Logger.debug("📋 Extracted job title from <title> tag: \(jobApp.jobPosition)")
                    }
                }
            }
            // Extract company name - comprehensive selectors
            let companySelectors = [
                // Primary selectors with links
                ".job-details-jobs-unified-top-card__company-name a",
                ".jobs-unified-top-card__company-name a",
                ".job-details-jobs-unified-top-card__primary-description a",
                // Primary selectors without links
                ".job-details-jobs-unified-top-card__company-name",
                ".jobs-unified-top-card__company-name",
                ".job-details-jobs-unified-top-card__primary-description",
                // 2024+ layout selectors
                ".job-details-module__company-name",
                ".jobs-company-name",
                ".job-poster__company-name",
                // Alternative selectors
                "[data-test-id=\"job-company-name\"]",
                ".job-details__company",
                ".company-name",
                "a[data-test*=\"company\"]",
                // Fallback selectors
                ".job-details-jobs-unified-top-card__primary-description-container .t-black",
                ".jobs-unified-top-card__subtitle-primary-grouping .t-black"
            ]
            for selector in companySelectors {
                if let element = try? doc.select(selector).first(),
                   let company = try? element.text().trimmingCharacters(in: .whitespacesAndNewlines),
                   !company.isEmpty {
                    jobApp.companyName = company
                    Logger.debug("🏢 Extracted company with selector '\(selector)': \(jobApp.companyName)")
                    break
                }
            }

            // Fallback: Extract company from <title> tag (format: "Job Title | Company | LinkedIn")
            if jobApp.companyName.isEmpty {
                if let titleElement = try? doc.select("title").first(),
                   let titleText = try? titleElement.text() {
                    let components = titleText.components(separatedBy: " | ")
                    if components.count >= 3 {
                        jobApp.companyName = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
                        Logger.debug("🏢 Extracted company from <title> tag: \(jobApp.companyName)")
                    }
                }
            }

            // Fallback: Extract company from aria-label
            if jobApp.companyName.isEmpty {
                if let companyLabel = try? doc.select("[aria-label^=\"Company,\"]").first(),
                   let labelText = try? companyLabel.attr("aria-label") {
                    // Format: "Company, Company Name."
                    let company = labelText
                        .replacingOccurrences(of: "Company, ", with: "")
                        .replacingOccurrences(of: ".", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !company.isEmpty {
                        jobApp.companyName = company
                        Logger.debug("🏢 Extracted company from aria-label: \(jobApp.companyName)")
                    }
                }
            }
            // Extract location
            if let locationElement = try? doc.select(
                ".job-details-jobs-unified-top-card__primary-description-container .t-black--light, .jobs-unified-top-card__bullet"
            ).first() {
                let locationText = try locationElement.text().trimmingCharacters(in: .whitespacesAndNewlines)
                // LinkedIn often shows location with other info, extract just the location part
                jobApp.jobLocation = locationText.components(separatedBy: " · ").first ?? locationText
                Logger.debug("📍 Extracted location: \(jobApp.jobLocation)")
            }
            // Extract job description - try multiple selectors in order of specificity
            let descriptionSelectors = [
                // Primary selectors for job description content
                "#job-details",
                ".jobs-description__content",
                ".jobs-description-content__text",
                ".job-details-jobs-unified-top-card__job-description",
                // 2024+ LinkedIn layout selectors
                ".jobs-box__html-content",
                ".jobs-description__container",
                "[data-job-description]",
                // Expandable text containers
                "[data-testid=\"expandable-text-box\"]",
                ".show-more-less-html__markup",
                // Generic fallbacks
                ".jobs-description",
                "article[data-view-name=\"job-details\"]",
                ".job-view-layout section.description"
            ]

            for selector in descriptionSelectors {
                if let descriptionElement = try? doc.select(selector).first() {
                    let rawDescription = try descriptionElement.html()
                    let cleanedDescription = cleanJobDescription(rawDescription)
                    // Only use if we got meaningful content (more than just whitespace)
                    if cleanedDescription.count > 100 {
                        jobApp.jobDescription = cleanedDescription
                        Logger.debug("📝 Extracted description with selector '\(selector)': \(jobApp.jobDescription.count) characters")
                        break
                    }
                }
            }

            // If still empty or too short, try getting all text from the main content area
            if jobApp.jobDescription.count < 100 {
                Logger.warning("⚠️ Job description too short (\(jobApp.jobDescription.count) chars), trying broader extraction")
                if let mainContent = try? doc.select("main, [role=\"main\"], .scaffold-layout__detail").first() {
                    let rawDescription = try mainContent.html()
                    let cleanedDescription = cleanJobDescription(rawDescription)
                    if cleanedDescription.count > jobApp.jobDescription.count {
                        jobApp.jobDescription = cleanedDescription
                        Logger.debug("📝 Extracted description from main content: \(jobApp.jobDescription.count) characters")
                    }
                }
            }
            // Extract apply link
            if let applyElement = try? doc.select(
                "a[data-test-id=\"job-apply-link\"], .jobs-apply-button, a[href*=\"apply\"]"
            ).first(),
               let applyHref = try? applyElement.attr("href") {
                if applyHref.hasPrefix("http") {
                    jobApp.jobApplyLink = applyHref
                } else {
                    jobApp.jobApplyLink = "https://www.linkedin.com" + applyHref
                }
                Logger.debug("🔗 Extracted apply link: \(jobApp.jobApplyLink)")
            }
            // Extract additional metadata if available
            if let metaElements = try? doc.select(
                ".job-details-jobs-unified-top-card__job-insight .job-details-jobs-unified-top-card__job-insight-view-model-secondary"
            ) {
                for element in metaElements {
                    let text = try element.text().lowercased()
                    if text.contains("employment type") || text.contains("full-time") ||
                       text.contains("part-time") || text.contains("contract") {
                        jobApp.employmentType = try element.text()
                    } else if text.contains("seniority") || text.contains("level") {
                        jobApp.seniorityLevel = try element.text()
                    }
                }
            }
            // Validate that we got essential information
            guard !jobApp.jobPosition.isEmpty && !jobApp.companyName.isEmpty else {
                Logger.warning("⚠️ LinkedIn job extraction failed - missing essential data")
                // Save HTML to Downloads for debugging
                let downloadsURL = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Downloads")
                    .appendingPathComponent("linkedin-scrape-debug-\(Date().timeIntervalSince1970).html")
                do {
                    try html.write(to: downloadsURL, atomically: true, encoding: .utf8)
                    Logger.debug("📄 [LinkedIn Scraper] Saved captured HTML to: \(downloadsURL.path)")
                } catch {
                    Logger.error("🚨 [LinkedIn Scraper] Failed to save debug HTML: \(error)")
                }
                return nil
            }
            Logger.info("✅ Successfully parsed LinkedIn job: \(jobApp.jobPosition) at \(jobApp.companyName)")
            return jobApp
        } catch {
            Logger.error("🚨 SwiftSoup parsing error: \(error)")
            return nil
        }
    }
    /// Clean and normalize job description HTML while preserving paragraph structure
    private static func cleanJobDescription(_ html: String) -> String {
        do {
            let doc = try SwiftSoup.parse(html)

            // Convert block-level elements to newlines before extracting text
            // This preserves paragraph structure
            for element in try doc.select("p, br, div, li, h1, h2, h3, h4, h5, h6") {
                try element.before("\n")
                if element.tagName() == "li" {
                    try element.before("• ")
                }
            }

            // Get the text content
            var text = try doc.text()

            // Normalize horizontal whitespace (spaces/tabs) but preserve newlines
            // Replace multiple spaces/tabs with single space
            text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)

            // Normalize multiple newlines to double newline (paragraph break)
            text = text.replacingOccurrences(of: "\\n\\s*\\n+", with: "\n\n", options: .regularExpression)

            // Clean up leading/trailing whitespace on each line
            let lines = text.components(separatedBy: "\n")
            let cleanedLines = lines.map { $0.trimmingCharacters(in: .whitespaces) }
            text = cleanedLines.joined(separator: "\n")

            // Remove excessive blank lines (more than 2 consecutive)
            text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)

            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            // Fallback: strip HTML tags with regex while preserving structure
            var result = html

            // Convert block elements to newlines
            result = result.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: [.regularExpression, .caseInsensitive])
            result = result.replacingOccurrences(of: "</p>|</div>|</li>|</h[1-6]>", with: "\n", options: [.regularExpression, .caseInsensitive])
            result = result.replacingOccurrences(of: "<li[^>]*>", with: "\n• ", options: [.regularExpression, .caseInsensitive])

            // Strip remaining HTML tags
            result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

            // Normalize whitespace
            result = result.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            result = result.replacingOccurrences(of: "\\n\\s*\\n+", with: "\n\n", options: .regularExpression)

            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Parse relative date strings like "2 days ago", "1 week ago", "3 hours ago" into actual Date
    private static func parseRelativeDate(_ relativeString: String) -> Date? {
        let lowercased = relativeString.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Extract the number
        let numberPattern = try? NSRegularExpression(pattern: "(\\d+)", options: [])
        guard let match = numberPattern?.firstMatch(
            in: lowercased,
            options: [],
            range: NSRange(lowercased.startIndex..., in: lowercased)
        ),
              let numberRange = Range(match.range(at: 1), in: lowercased),
              let number = Int(lowercased[numberRange]) else {
            // Handle "just now" or "today"
            if lowercased.contains("just now") || lowercased.contains("today") {
                return Date()
            }
            if lowercased.contains("yesterday") {
                return Calendar.current.date(byAdding: .day, value: -1, to: Date())
            }
            return nil
        }

        let calendar = Calendar.current
        let now = Date()

        if lowercased.contains("second") {
            return calendar.date(byAdding: .second, value: -number, to: now)
        } else if lowercased.contains("minute") {
            return calendar.date(byAdding: .minute, value: -number, to: now)
        } else if lowercased.contains("hour") {
            return calendar.date(byAdding: .hour, value: -number, to: now)
        } else if lowercased.contains("day") {
            return calendar.date(byAdding: .day, value: -number, to: now)
        } else if lowercased.contains("week") {
            return calendar.date(byAdding: .day, value: -number * 7, to: now)
        } else if lowercased.contains("month") {
            return calendar.date(byAdding: .month, value: -number, to: now)
        } else if lowercased.contains("year") {
            return calendar.date(byAdding: .year, value: -number, to: now)
        }

        return nil
    }

    /// Parse LinkedIn job data from JSON extracted by JS scraper
    private static func parseLinkedInJobJSON(_ jsonString: String, url: String) -> JobApp? {
        Logger.debug("🔍 [LinkedIn Scraper] Parsing JSON from JS scraper")

        guard let jsonData = jsonString.data(using: .utf8) else {
            Logger.error("🚨 [LinkedIn Scraper] Failed to convert JSON string to data")
            return nil
        }

        do {
            guard let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                Logger.error("🚨 [LinkedIn Scraper] JSON is not a dictionary")
                return nil
            }

            let jobApp = JobApp()

            // Title
            if let title = json["title"] as? String, !title.isEmpty {
                jobApp.jobPosition = title
                Logger.debug("📋 Extracted title: \(title)")
            }

            // Company
            if let company = json["company"] as? String, !company.isEmpty {
                jobApp.companyName = company
                Logger.debug("🏢 Extracted company: \(company)")
            }

            // Location
            if let location = json["location"] as? String, !location.isEmpty {
                jobApp.jobLocation = location
                Logger.debug("📍 Extracted location: \(location)")
            }

            // Description
            if let description = json["description"] as? String, !description.isEmpty {
                jobApp.jobDescription = description
                Logger.debug("📝 Extracted description: \(description.count) characters")
            }

            // Build metadata header for fields without dedicated columns
            var metadataLines: [String] = []

            // Salary - use dedicated field
            if let salary = json["salary"] as? String, !salary.isEmpty {
                jobApp.salary = salary
                Logger.debug("💰 Extracted salary: \(salary)")
            }

            // Job type (Full-time, Part-time, etc.) - use employmentType field
            if let jobType = json["jobType"] as? String, !jobType.isEmpty {
                jobApp.employmentType = jobType
                Logger.debug("📋 Extracted job type: \(jobType)")
            }

            // Workplace type (Hybrid, Remote, On-site) - no dedicated field, add to metadata
            if let workplaceType = json["workplaceType"] as? String, !workplaceType.isEmpty {
                metadataLines.append("🏢 Workplace: \(workplaceType)")
                Logger.debug("🏢 Extracted workplace type: \(workplaceType)")
            }

            // Company industry - use industries field
            if let industry = json["companyIndustry"] as? String, !industry.isEmpty {
                jobApp.industries = industry
                Logger.debug("🏭 Extracted industry: \(industry)")
            }

            // Company size - no dedicated field, add to metadata
            if let companySize = json["companySize"] as? String, !companySize.isEmpty {
                metadataLines.append("👥 Company Size: \(companySize)")
                Logger.debug("👥 Extracted company size: \(companySize)")
            }

            // Applicants count - no dedicated field, add to metadata
            if let applicants = json["applicants"] as? String, !applicants.isEmpty {
                metadataLines.append("👤 Applicants: \(applicants)")
                Logger.debug("👤 Extracted applicants: \(applicants)")
            }

            // Posted date - convert relative date to actual Date and store raw string
            if let postedDate = json["postedDate"] as? String, !postedDate.isEmpty {
                jobApp.jobPostingTime = postedDate
                if let actualDate = parseRelativeDate(postedDate) {
                    jobApp.identifiedDate = actualDate
                    Logger.debug("📅 Converted '\(postedDate)' to date: \(actualDate)")
                } else {
                    Logger.debug("📅 Stored posting time: \(postedDate)")
                }
            }

            // Prepend metadata to description if we have any
            if !metadataLines.isEmpty && !jobApp.jobDescription.isEmpty {
                let metadataHeader = metadataLines.joined(separator: "\n")
                jobApp.jobDescription = metadataHeader + "\n\n---\n\n" + jobApp.jobDescription
                Logger.debug("📝 Prepended \(metadataLines.count) metadata fields to description")
            }

            // URL
            if let jobUrl = json["url"] as? String, !jobUrl.isEmpty {
                jobApp.postingURL = jobUrl
            } else {
                jobApp.postingURL = url
            }

            // Validate we have minimum required data
            if jobApp.jobPosition.isEmpty && jobApp.companyName.isEmpty {
                Logger.warning("⚠️ [LinkedIn Scraper] JSON parsed but missing title and company")
                return nil
            }

            Logger.info("✅ [LinkedIn Scraper] Successfully parsed job from JSON: \(jobApp.jobPosition) at \(jobApp.companyName)")
            return jobApp

        } catch {
            Logger.error("🚨 [LinkedIn Scraper] JSON parsing error: \(error)")
            return nil
        }
    }
}
// MARK: - Navigation Delegate Helper
private class LinkedInJobScrapeDelegate: NSObject, WKNavigationDelegate {
    let targetURL: URL
    let completion: (Result<String, Error>) -> Void
    private var hasCompleted = false
    private var hasStartedExtraction = false  // Prevents duplicate extraction attempts
    private var navigationStep = 0 // 0 = feed, 1 = job page
    private var pendingWorkItems: [DispatchWorkItem] = []

    init(targetURL: URL, completion: @escaping (Result<String, Error>) -> Void) {
        self.targetURL = targetURL
        self.completion = completion
        super.init()
        Logger.debug("🔍 [LinkedInJobScrapeDelegate] Delegate initialized for target: \(targetURL.absoluteString)")
    }

    /// Cancel all pending work items to prevent use-after-free
    func cancelAllPendingWork() {
        for item in pendingWorkItems {
            item.cancel()
        }
        pendingWorkItems.removeAll()
    }

    /// Schedule cancellable work
    private func scheduleWork(after delay: TimeInterval, block: @escaping () -> Void) {
        let workItem = DispatchWorkItem { [weak self] in
            guard self != nil else { return }
            block()
        }
        pendingWorkItems.append(workItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Logger.debug("🔍 [LinkedInJobScrapeDelegate] didStartProvisionalNavigation (step \(navigationStep))")
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        Logger.debug("🔍 [LinkedInJobScrapeDelegate] didCommit navigation (step \(navigationStep))")
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Logger.debug("🔍 [LinkedInJobScrapeDelegate] didFinish navigation (step \(navigationStep))")
        guard !hasCompleted else {
            Logger.debug("🔍 [LinkedInJobScrapeDelegate] Already completed, ignoring duplicate didFinish")
            return
        }
        if navigationStep == 0 {
            // Just finished loading LinkedIn feed, now navigate to the job page
            navigationStep = 1
            Logger.debug("🔍 [LinkedInJobScrapeDelegate] Step 1 complete, now navigating to job page")
            // Wait a moment for the feed to fully load, then navigate to job page
            scheduleWork(after: LinkedInScrapeTiming.navigationTransitionDelay) { [weak self, weak webView] in
                guard let self = self, let webView = webView, !self.hasCompleted else { return }
                var request = URLRequest(url: self.targetURL)
                request.setValue(
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                    forHTTPHeaderField: "User-Agent"
                )
                request.setValue(
                    "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                    forHTTPHeaderField: "Accept"
                )
                request.setValue("en-US,en;q=0.5", forHTTPHeaderField: "Accept-Language")
                request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
                request.setValue("https://www.linkedin.com/feed/", forHTTPHeaderField: "Referer")
                request.timeoutInterval = LinkedInScrapeTiming.requestTimeout
                Logger.debug("🔍 [LinkedInJobScrapeDelegate] Step 2: Loading job page with proper referer")
                webView.load(request)
            }
        } else {
            // Finished loading job page, extract HTML
            // Extract job ID from target URL (handles trailing slashes and query params)
            let targetJobID = targetURL.absoluteString
                .replacingOccurrences(of: "\\?.*", with: "", options: .regularExpression)
                .components(separatedBy: "/")
                .last(where: { !$0.isEmpty && $0.allSatisfy { $0.isNumber } }) ?? ""

            // Verify we're actually on the target job page before extracting
            guard let currentURL = webView.url,
                  currentURL.absoluteString.contains("/jobs/view/"),
                  !targetJobID.isEmpty,
                  currentURL.absoluteString.contains(targetJobID) else {
                Logger.debug("🔍 [LinkedInJobScrapeDelegate] didFinish but not on target job page yet (current: \(webView.url?.absoluteString ?? "nil"), target job ID: \(targetJobID))")
                return
            }

            // Guard against duplicate didFinish calls for the same page
            guard !hasStartedExtraction else {
                Logger.debug("🔍 [LinkedInJobScrapeDelegate] Already started extraction, ignoring duplicate didFinish")
                return
            }
            hasStartedExtraction = true
            Logger.debug("🔍 [LinkedInJobScrapeDelegate] Step 2 complete on \(currentURL.absoluteString), extracting job page HTML")
            // Wait a moment for dynamic content to load
            scheduleWork(after: LinkedInScrapeTiming.dynamicContentDelay) { [weak self, weak webView] in
                guard let self = self, let webView = webView, !self.hasCompleted else { return }
                Logger.debug(
                    "🔍 [LinkedInJobScrapeDelegate] Expanding 'See more' sections before extraction..."
                )

                // JavaScript to click all "See more" buttons and expand job description
                let expandScript = """
                (function() {
                    // Click all "See more" buttons to expand content
                    const seeMoreButtons = document.querySelectorAll(
                        'button[aria-label*="see more"], ' +
                        'button[aria-label*="See more"], ' +
                        'button.jobs-description__footer-button, ' +
                        '[data-tracking-control-name*="see_more"], ' +
                        '.show-more-less-html__button--more, ' +
                        'button.artdeco-button--tertiary[aria-expanded="false"]'
                    );
                    seeMoreButtons.forEach(btn => {
                        try { btn.click(); } catch(e) {}
                    });

                    // Also try to find and expand job description specifically
                    const jobDescExpand = document.querySelector(
                        '#job-details button, ' +
                        '.jobs-description button[aria-expanded="false"], ' +
                        '.jobs-box__html-content button'
                    );
                    if (jobDescExpand) {
                        try { jobDescExpand.click(); } catch(e) {}
                    }

                    return seeMoreButtons.length;
                })()
                """

                webView.evaluateJavaScript(expandScript) { [weak self, weak webView] expandResult, _ in
                    guard let self = self, let webView = webView, !self.hasCompleted else { return }

                    if let count = expandResult as? Int, count > 0 {
                        Logger.debug("🔍 [LinkedInJobScrapeDelegate] Clicked \(count) 'See more' buttons, waiting for content...")
                        // Wait a bit more for expanded content to render
                        self.scheduleWork(after: 1.0) { [weak self, weak webView] in
                            guard let self = self, let webView = webView, !self.hasCompleted else { return }
                            self.extractHTMLContent(from: webView)
                        }
                    } else {
                        Logger.debug("🔍 [LinkedInJobScrapeDelegate] No 'See more' buttons found, extracting HTML...")
                        self.extractHTMLContent(from: webView)
                    }
                }
            }
        }
    }

    private func extractHTMLContent(from webView: WKWebView) {
        Logger.debug("🔍 [LinkedInJobScrapeDelegate] Running JS scraper...")

        // JavaScript scraper that extracts structured job data directly from the DOM
        let scraperScript = """
        (function extractLinkedInJob() {
            var job = {};
            var mainEl = document.querySelector('main');
            var mainText = mainEl ? mainEl.innerText : '';
            var bodyText = document.body.innerText;

            // Title from page title
            job.title = document.title.split('|')[0].trim();

            // Company from link
            var companyLink = document.querySelector('main a[href*="/company/"]');
            job.company = companyLink ? companyLink.textContent.trim() : '';
            job.companyUrl = companyLink ? companyLink.href : '';

            // Find the info line with location, posted date, applicants
            var infoLine = '';
            var allP = document.querySelectorAll('main p');
            for (var p = 0; p < allP.length; p++) {
                var pText = allP[p].innerText || '';
                if (pText.indexOf('ago') > -1 && pText.indexOf('people') > -1) {
                    infoLine = pText;
                    break;
                }
            }

            if (infoLine) {
                var parts = infoLine.split('·');
                if (parts[0]) job.location = parts[0].trim();
                for (var k = 0; k < parts.length; k++) {
                    var part = parts[k].trim();
                    if (part.indexOf('ago') > -1) job.postedDate = part;
                    if (part.indexOf('people') > -1 || part.indexOf('applicant') > -1) {
                        var nums = part.replace(/[^0-9]/g, '');
                        if (nums) job.applicants = nums;
                    }
                }
            }

            // Salary
            var allEls = document.querySelectorAll('main span, main button');
            for (var i = 0; i < allEls.length; i++) {
                var text = (allEls[i].innerText || '').trim();
                if (!job.salary && text.indexOf('/yr') > -1 && text.indexOf('$') > -1 && text.length < 30) {
                    job.salary = text;
                    break;
                }
            }

            // Company size from About section
            var aboutIdx = mainText.indexOf('About the company');
            if (aboutIdx > -1) {
                var aboutSection = mainText.substring(aboutIdx, aboutIdx + 300);
                var sizeParts = aboutSection.split('·');
                for (var s = 0; s < sizeParts.length; s++) {
                    if (sizeParts[s].indexOf('employees') > -1) {
                        job.companySize = sizeParts[s].trim();
                        break;
                    }
                }
            }

            // Job type and workplace type from buttons
            var buttons = document.querySelectorAll('main button, main span');
            for (var j = 0; j < buttons.length; j++) {
                var btnText = (buttons[j].innerText || '').trim();
                if (!job.jobType && ['Full-time','Part-time','Contract','Internship','Temporary'].indexOf(btnText) > -1) job.jobType = btnText;
                if (!job.workplaceType && ['Hybrid','Remote','On-site'].indexOf(btnText) > -1) job.workplaceType = btnText;
            }

            // Description - find between markers
            var descStart = bodyText.indexOf('About the job');
            var descEnd = bodyText.indexOf('Benefits found');
            if (descEnd < 0) descEnd = bodyText.indexOf('Set alert for');
            if (descEnd < 0) descEnd = bodyText.indexOf('About the company');
            if (descStart > -1 && descEnd > -1 && descEnd > descStart) {
                job.description = bodyText.substring(descStart + 13, descEnd).trim();
            } else if (descStart > -1) {
                // Try to get at least some description
                job.description = bodyText.substring(descStart + 13, descStart + 5000).trim();
            }

            // Industry
            if (aboutIdx > -1) {
                var compSection = mainText.substring(aboutIdx, aboutIdx + 500);
                var industries = ['Insurance','Technology','Finance','Healthcare','Software','SaaS','Retail','Education','Banking','Consulting','Manufacturing','Real Estate','Legal','Media','Energy','Telecommunications'];
                for (var ind = 0; ind < industries.length; ind++) {
                    if (compSection.indexOf(industries[ind]) > -1) {
                        job.companyIndustry = industries[ind];
                        break;
                    }
                }
            }

            job.url = window.location.href.split('?')[0];

            return JSON.stringify(job);
        })()
        """

        webView.evaluateJavaScript(scraperScript) { [weak self] result, error in
            guard let self = self, !self.hasCompleted else {
                Logger.debug("🔍 [LinkedInJobScrapeDelegate] JavaScript completed but already handled")
                return
            }
            self.hasCompleted = true
            self.cancelAllPendingWork()

            if let error = error {
                Logger.error("🚨 [LinkedInJobScrapeDelegate] JavaScript evaluation failed: \(error)")
                self.completion(.failure(error))
            } else if let jsonString = result as? String {
                Logger.debug("✅ [LinkedInJobScrapeDelegate] JS scraper returned: \(jsonString.prefix(200))...")
                // Return the JSON string as the "HTML" - we'll parse it differently
                self.completion(.success("__LINKEDIN_JSON__" + jsonString))
            } else {
                Logger.error("🚨 [LinkedInJobScrapeDelegate] JavaScript returned unexpected result type")
                self.completion(.failure(URLError(.cannotDecodeContentData)))
            }
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Logger.error("🚨 [LinkedInJobScrapeDelegate] didFail navigation (step \(navigationStep)): \(error)")
        guard !hasCompleted else { return }
        hasCompleted = true
        cancelAllPendingWork()
        completion(.failure(error))
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Logger.error("🚨 [LinkedInJobScrapeDelegate] didFailProvisionalNavigation (step \(navigationStep)): \(error)")
        guard !hasCompleted else { return }
        hasCompleted = true
        cancelAllPendingWork()
        completion(.failure(error))
    }
    deinit {
        cancelAllPendingWork()
        Logger.debug("🔍 [LinkedInJobScrapeDelegate] Delegate deallocated")
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url {
            Logger.debug("🔍 [LinkedInJobScrapeDelegate] Navigation policy for: \(url.absoluteString)")
            // Check for potential security challenges or redirects that might cause blank pages
            if url.absoluteString.contains("linkedin.com/checkpoint") ||
               url.absoluteString.contains("linkedin.com/challenge") ||
               url.absoluteString.contains("linkedin.com/security") {
                Logger.warning(
                    "⚠️ [LinkedInJobScrapeDelegate] LinkedIn security challenge detected: \(url.absoluteString)"
                )
            }
            // Check for external redirects that might indicate bot detection
            if ((url.host?.contains("linkedin.com")) != nil) == true &&
               !url.absoluteString.hasPrefix("about:") &&
               !url.absoluteString.hasPrefix("data:") {
                Logger.warning(
                    "⚠️ [LinkedInJobScrapeDelegate] External redirect detected (possible bot detection): \(url.absoluteString)"
                )
            }
        }
        decisionHandler(.allow)
    }
}
