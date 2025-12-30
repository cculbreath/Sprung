//
//  WebResourceService.swift
//  Sprung
//
//
import Foundation
import WebKit

/// Unified service for fetching web resources (HTML, etc.) with automatic
/// fallback strategies for Cloudflare-protected sites and JavaScript-rendered pages.
@MainActor
final class WebResourceService {

    // MARK: - Configuration

    /// Configuration options for HTML fetching behavior
    struct Configuration {
        /// Maximum time to wait before timing out (in seconds)
        var timeout: TimeInterval = 20

        /// Custom user agent string (nil uses default desktop UA)
        var userAgent: String? = nil

        /// Optional JavaScript to evaluate on page load to detect success
        /// Should return a Bool indicating whether the page has loaded successfully
        var successDetectionScript: String? = nil

        /// Whether to store Cloudflare clearance cookies
        var storeClearanceCookies: Bool = false

        /// Optional delay before completion (in seconds) to allow page to stabilize
        var completionDelay: TimeInterval = 0

        /// Poll interval for success detection (in seconds)
        var pollInterval: TimeInterval = 0.5

        /// Maximum number of polling attempts for success detection
        var maxPollAttempts: Int = 30

        /// Maximum number of retry attempts when Cloudflare challenge is detected
        var maxRetryAttempts: Int = 4
    }

    // MARK: - Constants

    private static let desktopUA =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    private static let acceptHdr = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    private static let langHdr = "en-US,en;q=0.5"

    /// Cloudflare challenge indicators
    private static let cloudflareIndicators = [
        "Attention Required! | Cloudflare",
        "Just a moment…",
        "Just a moment...",
        "Checking if the site connection is secure",
        "cf-browser-verification",
        "Request Blocked",
        "You have been blocked",
        "Blocked - Indeed.com",
        "Security Check - Indeed.com",
        "Additional Verification Required"
    ]

    // MARK: - Public API

    /// Fetches HTML content from the given URL with automatic fallback strategies.
    /// Tries URLSession first for performance, falls back to WKWebView if needed.
    /// - Parameters:
    ///   - url: The URL to fetch
    ///   - config: Configuration options for the fetch operation
    /// - Returns: The HTML content as a string
    /// - Throws: URLError or navigation errors
    static func fetchHTML(from url: URL, config: Configuration = .init()) async throws -> String {
        Logger.verbose("🔍 [WebResourceService] Starting HTML fetch for: \(url.absoluteString)")

        // Strategy 1: Try URLSession first (fast path)
        if let html = try? await fetchHTMLViaURLSession(url: url, config: config) {
            Logger.info("✅ [WebResourceService] Successfully fetched HTML via URLSession")
            return html
        }

        Logger.info("⚠️ [WebResourceService] URLSession fetch failed, falling back to WKWebView")

        // Strategy 2: Fall back to WKWebView (handles JS-rendered pages)
        let html = try await fetchHTMLViaWebView(url: url, config: config)
        Logger.info("✅ [WebResourceService] Successfully fetched HTML via WKWebView")
        return html
    }

    // MARK: - Private Implementation

    /// Fetches HTML using URLSession with Cloudflare cookie handling and retry logic
    private static func fetchHTMLViaURLSession(url: URL, config: Configuration) async throws -> String {
        var attempt = 0

        while attempt < config.maxRetryAttempts {
            attempt += 1

            var request = URLRequest(url: url)
            request.setValue(config.userAgent ?? desktopUA, forHTTPHeaderField: "User-Agent")
            request.setValue(acceptHdr, forHTTPHeaderField: "Accept")
            request.setValue(langHdr, forHTTPHeaderField: "Accept-Language")
            request.timeoutInterval = config.timeout

            // Attach cf_clearance cookie if available
            if let cookie = await CloudflareCookieManager.clearance(for: url) {
                let cookieHeader = "\(cookie.name)=\(cookie.value)"
                request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            }

            // Perform request
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let htmlContent = String(data: data, encoding: .utf8) else {
                throw URLError(.cannotDecodeContentData)
            }

            // Detect Cloudflare challenge pages
            if cloudflareIndicators.contains(where: { htmlContent.contains($0) }) {
                Logger.warning("⚠️ [WebResourceService] Cloudflare challenge detected (attempt \(attempt)/\(config.maxRetryAttempts))")

                // Refresh clearance cookie via interactive challenge
                _ = await CloudflareCookieManager.refreshClearance(for: url)
                continue // retry
            }

            return htmlContent
        }

        throw URLError(.badServerResponse)
    }

    /// Fetches HTML using WKWebView for JavaScript-rendered pages
    private static func fetchHTMLViaWebView(url: URL, config: Configuration) async throws -> String {
        let fetcher = WebViewFetcher(url: url, config: config)
        return try await fetcher.fetch()
    }
}

// MARK: - WebView Implementation

@MainActor
private final class WebViewFetcher: NSObject, WKNavigationDelegate {

    private let url: URL
    private let config: WebResourceService.Configuration
    private var continuation: CheckedContinuation<String, Error>?
    private var webView: WKWebView!
    private var selfRetain: WebViewFetcher?
    private var timeoutTask: DispatchWorkItem?
    private var startTime = Date()
    private var pollAttempts = 0

    init(url: URL, config: WebResourceService.Configuration) {
        self.url = url
        self.config = config
        super.init()

        // Retain self until completion
        selfRetain = self

        // Configure WebView
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: cfg)
        webView.isHidden = true
        webView.navigationDelegate = self

        // Set custom user agent if provided
        if let userAgent = config.userAgent {
            webView.customUserAgent = userAgent
        }
    }

    func fetch() async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            continuation = cont
            start()
        }
    }

    private func start() {
        webView.load(URLRequest(url: url))

        // Set up timeout if configured
        if config.timeout > 0 {
            let timeoutWork = DispatchWorkItem { [weak self] in
                self?.finishWithError(URLError(.timedOut))
            }
            timeoutTask = timeoutWork
            DispatchQueue.main.asyncAfter(deadline: .now() + config.timeout, execute: timeoutWork)
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        // Store clearance cookie if requested
        if config.storeClearanceCookies {
            storeClearanceCookie()
        }

        // Check if we have success detection configured
        if let successScript = config.successDetectionScript {
            pollForSuccessCondition(successScript)
        } else {
            // No success detection, extract HTML immediately
            extractHTML()
        }
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        finishWithError(error)
    }

    // MARK: - Success Detection

    private func pollForSuccessCondition(_ script: String) {
        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self else { return }

            if let isSuccess = result as? Bool, isSuccess {
                // Success condition met, extract HTML
                self.extractHTML()
            } else if self.pollAttempts < self.config.maxPollAttempts {
                // Keep polling
                self.pollAttempts += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + self.config.pollInterval) {
                    self.pollForSuccessCondition(script)
                }
            } else {
                // Exceeded max attempts, check for timeout
                if Date().timeIntervalSince(self.startTime) >= self.config.timeout {
                    // Timeout reached, extract HTML anyway
                    self.extractHTML()
                } else {
                    // Continue polling until timeout
                    self.pollAttempts = 0
                    self.pollForSuccessCondition(script)
                }
            }
        }
    }

    // MARK: - HTML Extraction

    private func extractHTML() {
        webView.evaluateJavaScript("document.documentElement.outerHTML.toString()") { [weak self] result, error in
            guard let self else { return }

            if let html = result as? String {
                if self.config.completionDelay > 0 {
                    // Delay before completing
                    DispatchQueue.main.asyncAfter(deadline: .now() + self.config.completionDelay) {
                        self.finish(html)
                    }
                } else {
                    self.finish(html)
                }
            } else {
                self.finishWithError(error ?? URLError(.cannotDecodeContentData))
            }
        }
    }

    // MARK: - Cookie Management

    private func storeClearanceCookie() {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self else { return }
            if let cookie = cookies.first(where: {
                $0.name == "cf_clearance" &&
                    ((self.url.host ?? "").hasSuffix($0.domain))
            }) {
                CloudflareCookieManager.store(cookie: cookie)
            }
        }
    }

    // MARK: - Completion

    private func finish(_ html: String) {
        timeoutTask?.cancel()
        continuation?.resume(returning: html)
        cleanUp()
    }

    private func finishWithError(_ error: Error) {
        timeoutTask?.cancel()
        continuation?.resume(throwing: error)
        cleanUp()
    }

    private func cleanUp() {
        continuation = nil
        selfRetain = nil
        timeoutTask = nil
    }
}

// MARK: - Shared Navigation Delegate Helper

/// A reusable helper for handling WKWebView navigation with success detection
/// and cookie storage. Can be used with any WKWebView instance (visible or hidden).
@MainActor
final class WebViewNavigationHelper: NSObject, WKNavigationDelegate {

    // MARK: - Configuration

    /// Configuration for navigation behavior
    struct Configuration {
        /// JavaScript to evaluate to detect successful page load (returns Bool)
        var successDetectionScript: String? = nil

        /// Whether to store Cloudflare clearance cookies
        var storeClearanceCookies: Bool = false

        /// Maximum time to wait for success condition (in seconds)
        var maxWaitTime: TimeInterval = 15

        /// Delay before calling success callback (in seconds)
        var successDelay: TimeInterval = 0
    }

    // MARK: - Properties

    private let url: URL
    private let config: Configuration
    private let onSuccess: () -> Void
    private var startTime = Date()
    private var hasCompleted = false

    // MARK: - Initialization

    init(url: URL, config: Configuration = .init(), onSuccess: @escaping () -> Void) {
        self.url = url
        self.config = config
        self.onSuccess = onSuccess
        super.init()
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        // Store clearance cookie if requested
        if config.storeClearanceCookies {
            storeClearanceCookie()
        }

        // Check for success condition
        if let successScript = config.successDetectionScript {
            checkForSuccess(webView, script: successScript)
        } else {
            // No success detection, complete immediately
            completeWithSuccess()
        }

        // Check for timeout
        checkForTimeout()
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError _: Error) {
        // Navigation failed, but we still might want to proceed
        // depending on the use case
    }

    // MARK: - Success Detection

    private func checkForSuccess(_ webView: WKWebView, script: String) {
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self else { return }

            if let isSuccess = result as? Bool, isSuccess {
                self.completeWithSuccess()
            }
        }
    }

    // MARK: - Timeout Check

    private func checkForTimeout() {
        if Date().timeIntervalSince(startTime) >= config.maxWaitTime {
            completeWithSuccess()
        }
    }

    // MARK: - Cookie Management

    private func storeClearanceCookie() {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self else { return }
            if let cookie = cookies.first(where: {
                $0.name == "cf_clearance" &&
                    ((self.url.host ?? "").hasSuffix($0.domain))
            }) {
                CloudflareCookieManager.store(cookie: cookie)
            }
        }
    }

    // MARK: - Completion

    private func completeWithSuccess() {
        guard !hasCompleted else { return }
        hasCompleted = true

        if config.successDelay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + config.successDelay) {
                self.onSuccess()
            }
        } else {
            onSuccess()
        }
    }
}
