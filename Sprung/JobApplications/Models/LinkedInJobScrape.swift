//
//  LinkedInJobScrape.swift
//  Sprung
//
import Foundation
import WebKit
import ObjectiveC

// MARK: - Configuration

private enum LinkedInScrapeTiming {
    static let requestTimeout: TimeInterval = 60
    static let navigationTransitionDelay: TimeInterval = 2
    static let dynamicContentDelay: TimeInterval = 3
    static let debugWindowRevealDelay: TimeInterval = 10
    static let ultimateTimeout: TimeInterval = 60
}

private enum LinkedInScrapeAssociatedKeys {
    static var delegateKey: UInt8 = 0
}

// MARK: - LinkedIn Session Manager

@MainActor
class LinkedInSessionManager: ObservableObject {
    @Published var isLoggedIn = false
    @Published var sessionExpired = false
    private var webView: WKWebView?

    init() {
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

        if !sessionManager.isLoggedIn {
            Logger.warning("⚠️ No LinkedIn session found, login required")
            return nil
        }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        let scrapingWebView = WKWebView(frame: .zero, configuration: config)
        Logger.debug("🔍 [LinkedIn Scraper] Created dedicated scraping WebView with shared session")

        func cleanupWebView() {
            scrapingWebView.navigationDelegate = nil
            scrapingWebView.stopLoading()
            scrapingWebView.removeFromSuperview()
            Logger.debug("🧹 [LinkedIn Scraper] Cleaned up scraping WebView")
        }

        do {
            Logger.info("🚀 Starting LinkedIn job extraction for: \(urlString)")
            let jsonString = try await loadJobPage(webView: scrapingWebView, url: url)
            cleanupWebView()

            if let jobApp = parseLinkedInJobJSON(jsonString, url: urlString) {
                // Check for duplicates before adding
                let urlBase = urlString.components(separatedBy: "?").first ?? urlString
                if let existingJob = jobAppStore.jobApps.first(where: {
                    ($0.postingURL.components(separatedBy: "?").first ?? $0.postingURL) == urlBase
                }) {
                    Logger.info("📋 [LinkedIn Scraper] Job already exists, selecting existing: \(existingJob.jobPosition)")
                    jobAppStore.selectedApp = existingJob
                    return existingJob
                }

                jobAppStore.selectedApp = jobAppStore.addJobApp(jobApp)
                Logger.info("✅ Successfully extracted LinkedIn job: \(jobApp.jobPosition)")
                return jobApp
            } else {
                Logger.error("🚨 Failed to parse LinkedIn job data")
                return nil
            }
        } catch {
            cleanupWebView()
            Logger.error("🚨 LinkedIn job extraction failed: \(error)")
            return nil
        }
    }

    /// Load job page and extract data via JavaScript
    private static func loadJobPage(webView: WKWebView, url: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            var debugWindow: NSWindow?

            DispatchQueue.main.async {
                // Create debug window (hidden initially)
                debugWindow = NSWindow(
                    contentRect: CGRect(x: 0, y: 0, width: 1000, height: 700),
                    styleMask: [.titled, .closable, .resizable],
                    backing: .buffered,
                    defer: false
                )
                debugWindow?.title = "LinkedIn Job Page Debug - \(url.lastPathComponent)"
                debugWindow?.contentView = webView
                debugWindow?.center()

                let scrapeDelegate = LinkedInJobScrapeDelegate(targetURL: url, debugWindow: debugWindow) { result in
                    guard !hasResumed else { return }
                    hasResumed = true
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
                var request = URLRequest(url: URL(string: "https://www.linkedin.com/feed/")!)
                request.setValue(
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
                    forHTTPHeaderField: "User-Agent"
                )
                request.timeoutInterval = LinkedInScrapeTiming.requestTimeout
                Logger.debug("🔍 [LinkedIn Scraper] Step 1: Loading LinkedIn feed")
                webView.load(request)
            }
        }
    }

    /// Parse relative date strings like "2 days ago" into actual Date
    static func parseRelativeDate(_ relativeString: String) -> Date? {
        let lowercased = relativeString.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        let numberPattern = try? NSRegularExpression(pattern: "(\\d+)", options: [])
        guard let match = numberPattern?.firstMatch(
            in: lowercased, options: [],
            range: NSRange(lowercased.startIndex..., in: lowercased)
        ),
              let numberRange = Range(match.range(at: 1), in: lowercased),
              let number = Int(lowercased[numberRange]) else {
            if lowercased.contains("just now") || lowercased.contains("today") { return Date() }
            if lowercased.contains("yesterday") {
                return Calendar.current.date(byAdding: .day, value: -1, to: Date())
            }
            return nil
        }

        let calendar = Calendar.current
        let now = Date()

        if lowercased.contains("second") { return calendar.date(byAdding: .second, value: -number, to: now) }
        if lowercased.contains("minute") { return calendar.date(byAdding: .minute, value: -number, to: now) }
        if lowercased.contains("hour") { return calendar.date(byAdding: .hour, value: -number, to: now) }
        if lowercased.contains("day") { return calendar.date(byAdding: .day, value: -number, to: now) }
        if lowercased.contains("week") { return calendar.date(byAdding: .day, value: -number * 7, to: now) }
        if lowercased.contains("month") { return calendar.date(byAdding: .month, value: -number, to: now) }
        if lowercased.contains("year") { return calendar.date(byAdding: .year, value: -number, to: now) }

        return nil
    }

    /// Parse LinkedIn job data from JSON extracted by JS scraper
    private static func parseLinkedInJobJSON(_ jsonString: String, url: String) -> JobApp? {
        Logger.debug("🔍 [LinkedIn Scraper] Parsing JSON from JS scraper")

        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            Logger.error("🚨 [LinkedIn Scraper] Failed to parse JSON")
            return nil
        }

        let jobApp = JobApp()

        // Core fields
        if let title = json["title"] as? String, !title.isEmpty {
            jobApp.jobPosition = title
        }
        if let company = json["company"] as? String, !company.isEmpty {
            jobApp.companyName = company
        }
        if let location = json["location"] as? String, !location.isEmpty {
            jobApp.jobLocation = location
        }
        if let description = json["description"] as? String, !description.isEmpty {
            jobApp.jobDescription = description
        }
        if let salary = json["salary"] as? String, !salary.isEmpty {
            jobApp.salary = salary
        }
        if let jobType = json["jobType"] as? String, !jobType.isEmpty {
            jobApp.employmentType = jobType
        }
        if let industry = json["companyIndustry"] as? String, !industry.isEmpty {
            jobApp.industries = industry
        }

        // Metadata to prepend to description
        var metadataLines: [String] = []
        if let workplaceType = json["workplaceType"] as? String, !workplaceType.isEmpty {
            metadataLines.append("🏢 Workplace: \(workplaceType)")
        }
        if let companySize = json["companySize"] as? String, !companySize.isEmpty {
            metadataLines.append("👥 Company Size: \(companySize)")
        }
        if let applicants = json["applicants"] as? String, !applicants.isEmpty {
            metadataLines.append("👤 Applicants: \(applicants)")
        }

        if let postedDate = json["postedDate"] as? String, !postedDate.isEmpty {
            jobApp.jobPostingTime = postedDate
            if let actualDate = parseRelativeDate(postedDate) {
                jobApp.identifiedDate = actualDate
            }
        }

        if !metadataLines.isEmpty && !jobApp.jobDescription.isEmpty {
            jobApp.jobDescription = metadataLines.joined(separator: "\n") + "\n\n---\n\n" + jobApp.jobDescription
        }

        jobApp.postingURL = (json["url"] as? String) ?? url

        // Validate minimum required data
        guard !jobApp.jobPosition.isEmpty || !jobApp.companyName.isEmpty else {
            Logger.warning("⚠️ [LinkedIn Scraper] JSON parsed but missing title and company")
            return nil
        }

        Logger.info("✅ [LinkedIn Scraper] Parsed: \(jobApp.jobPosition) at \(jobApp.companyName)")
        return jobApp
    }
}

// MARK: - Navigation Delegate

private class LinkedInJobScrapeDelegate: NSObject, WKNavigationDelegate {
    let targetURL: URL
    let completion: (Result<String, Error>) -> Void
    weak var debugWindow: NSWindow?

    private var hasCompleted = false
    private var hasStartedExtraction = false
    private var navigationStep = 0
    private var pendingWorkItems: [DispatchWorkItem] = []
    private var timeoutWorkItem: DispatchWorkItem?

    init(targetURL: URL, debugWindow: NSWindow?, completion: @escaping (Result<String, Error>) -> Void) {
        self.targetURL = targetURL
        self.debugWindow = debugWindow
        self.completion = completion
        super.init()
        setupTimeouts()
    }

    private func setupTimeouts() {
        // Show debug window after delay if not completed
        scheduleWork(after: LinkedInScrapeTiming.debugWindowRevealDelay) { [weak self] in
            guard let self = self, !self.hasCompleted else { return }
            Logger.info("🪟 [LinkedIn Scraper] Showing debug window - scraping taking longer than expected")
            self.debugWindow?.makeKeyAndOrderFront(nil)
        }

        // Ultimate timeout
        timeoutWorkItem = scheduleWork(after: LinkedInScrapeTiming.ultimateTimeout) { [weak self] in
            guard let self = self, !self.hasCompleted else { return }
            self.complete(with: .failure(URLError(.timedOut)))
        }
    }

    @discardableResult
    private func scheduleWork(after delay: TimeInterval, block: @escaping () -> Void) -> DispatchWorkItem {
        let workItem = DispatchWorkItem { [weak self] in
            guard self != nil else { return }
            block()
        }
        pendingWorkItems.append(workItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        return workItem
    }

    private func cancelAllPendingWork() {
        pendingWorkItems.forEach { $0.cancel() }
        pendingWorkItems.removeAll()
    }

    private func complete(with result: Result<String, Error>) {
        guard !hasCompleted else { return }
        hasCompleted = true
        cancelAllPendingWork()
        debugWindow?.close()
        completion(result)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !hasCompleted else { return }

        if navigationStep == 0 {
            // Finished loading feed, now navigate to job page
            navigationStep = 1
            scheduleWork(after: LinkedInScrapeTiming.navigationTransitionDelay) { [weak self, weak webView] in
                guard let self = self, let webView = webView, !self.hasCompleted else { return }
                var request = URLRequest(url: self.targetURL)
                request.setValue(
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
                    forHTTPHeaderField: "User-Agent"
                )
                request.setValue("https://www.linkedin.com/feed/", forHTTPHeaderField: "Referer")
                request.timeoutInterval = LinkedInScrapeTiming.requestTimeout
                Logger.debug("🔍 [LinkedIn Scraper] Step 2: Loading job page")
                webView.load(request)
            }
        } else {
            // Verify we're on the target job page
            let targetJobID = targetURL.absoluteString
                .replacingOccurrences(of: "\\?.*", with: "", options: .regularExpression)
                .components(separatedBy: "/")
                .last(where: { !$0.isEmpty && $0.allSatisfy { $0.isNumber } }) ?? ""

            guard let currentURL = webView.url,
                  currentURL.absoluteString.contains("/jobs/view/"),
                  !targetJobID.isEmpty,
                  currentURL.absoluteString.contains(targetJobID) else {
                return // Not on target page yet
            }

            guard !hasStartedExtraction else { return }
            hasStartedExtraction = true

            // Wait for dynamic content, then extract
            scheduleWork(after: LinkedInScrapeTiming.dynamicContentDelay) { [weak self, weak webView] in
                guard let self = self, let webView = webView, !self.hasCompleted else { return }
                self.expandAndExtract(from: webView)
            }
        }
    }

    private func expandAndExtract(from webView: WKWebView) {
        // Click "See more" buttons to expand content
        let expandScript = """
        (function() {
            document.querySelectorAll(
                'button[aria-label*="see more"], button[aria-label*="See more"], ' +
                '.show-more-less-html__button--more, button.jobs-description__footer-button'
            ).forEach(btn => { try { btn.click(); } catch(e) {} });
            return true;
        })()
        """

        webView.evaluateJavaScript(expandScript) { [weak self, weak webView] _, _ in
            guard let self = self, let webView = webView, !self.hasCompleted else { return }
            // Brief delay for content to render after expanding
            self.scheduleWork(after: 1.0) { [weak self, weak webView] in
                guard let self = self, let webView = webView else { return }
                self.extractJobData(from: webView)
            }
        }
    }

    private func extractJobData(from webView: WKWebView) {
        let scraperScript = """
        (function() {
            var job = {};
            var mainEl = document.querySelector('main');
            var mainText = mainEl ? mainEl.innerText : '';
            var bodyText = document.body.innerText;

            job.title = document.title.split('|')[0].trim();

            var companyLink = document.querySelector('main a[href*="/company/"]');
            job.company = companyLink ? companyLink.textContent.trim() : '';

            // Info line with location, posted date, applicants
            var allP = document.querySelectorAll('main p');
            for (var p = 0; p < allP.length; p++) {
                var pText = allP[p].innerText || '';
                if (pText.indexOf('ago') > -1) {
                    var parts = pText.split('·');
                    if (parts[0]) job.location = parts[0].trim();
                    for (var k = 0; k < parts.length; k++) {
                        var part = parts[k].trim();
                        if (part.indexOf('ago') > -1) job.postedDate = part;
                        if (part.indexOf('people') > -1 || part.indexOf('applicant') > -1) {
                            job.applicants = part.replace(/[^0-9]/g, '');
                        }
                    }
                    break;
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

            // Company info from About section
            var aboutIdx = mainText.indexOf('About the company');
            if (aboutIdx > -1) {
                var aboutSection = mainText.substring(aboutIdx, aboutIdx + 500);
                var sizeParts = aboutSection.split('·');
                for (var s = 0; s < sizeParts.length; s++) {
                    if (sizeParts[s].indexOf('employees') > -1) {
                        job.companySize = sizeParts[s].trim();
                        break;
                    }
                }
                var industries = ['Insurance','Technology','Finance','Healthcare','Software','Retail','Education','Banking','Consulting','Manufacturing'];
                for (var ind = 0; ind < industries.length; ind++) {
                    if (aboutSection.indexOf(industries[ind]) > -1) {
                        job.companyIndustry = industries[ind];
                        break;
                    }
                }
            }

            // Job type and workplace type
            var buttons = document.querySelectorAll('main button, main span');
            for (var j = 0; j < buttons.length; j++) {
                var btnText = (buttons[j].innerText || '').trim();
                if (!job.jobType && ['Full-time','Part-time','Contract','Internship','Temporary'].indexOf(btnText) > -1) job.jobType = btnText;
                if (!job.workplaceType && ['Hybrid','Remote','On-site'].indexOf(btnText) > -1) job.workplaceType = btnText;
            }

            // Description
            var descStart = bodyText.indexOf('About the job');
            var descEnd = bodyText.indexOf('Benefits found');
            if (descEnd < 0) descEnd = bodyText.indexOf('Set alert for');
            if (descEnd < 0) descEnd = bodyText.indexOf('About the company');
            if (descStart > -1 && descEnd > -1 && descEnd > descStart) {
                job.description = bodyText.substring(descStart + 13, descEnd).trim();
            } else if (descStart > -1) {
                job.description = bodyText.substring(descStart + 13, descStart + 5000).trim();
            }

            job.url = window.location.href.split('?')[0];
            return JSON.stringify(job);
        })()
        """

        webView.evaluateJavaScript(scraperScript) { [weak self] result, error in
            guard let self = self else { return }

            if let error = error {
                self.complete(with: .failure(error))
            } else if let jsonString = result as? String {
                Logger.debug("✅ [LinkedIn Scraper] JS scraper returned data")
                self.complete(with: .success(jsonString))
            } else {
                self.complete(with: .failure(URLError(.cannotDecodeContentData)))
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        complete(with: .failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        complete(with: .failure(error))
    }

    deinit {
        cancelAllPendingWork()
    }
}
