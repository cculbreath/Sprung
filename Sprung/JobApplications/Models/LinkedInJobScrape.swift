//
//  LinkedInJobScrape.swift
//  Sprung
//
//  Created by Claude on 7/12/25.
//

import Foundation
import SwiftSoup
import WebKit

// MARK: - LinkedIn Session Manager

@MainActor
class LinkedInSessionManager: ObservableObject {
    static let shared = LinkedInSessionManager()
    
    @Published var isLoggedIn = false
    @Published var sessionExpired = false
    
    private var webView: WKWebView?

    private init() {
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
        
        do {
            Logger.info("🚀 Starting LinkedIn job extraction for: \(urlString)")
            
            // Load the job page using dedicated scraping WebView
            let html = try await loadJobPageHTML(webView: scrapingWebView, url: url)
            
            // Clean up the WebView immediately after use
            defer {
                DispatchQueue.main.async {
                    scrapingWebView.navigationDelegate = nil
                    scrapingWebView.stopLoading()
                    scrapingWebView.removeFromSuperview()
                    Logger.debug("🧹 [LinkedIn Scraper] Cleaned up scraping WebView")
                }
            }
            
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
            switch error.code {
            case .timedOut:
                Logger.error("🚨 LinkedIn job extraction timed out - page took too long to load")
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
                
                // Create delegate and keep strong reference
                let scrapeDelegate = LinkedInJobScrapeDelegate(targetURL: url) { result in
                    guard !hasResumed else { 
                        Logger.debug("🔍 [LinkedIn Scraper] Delegate callback fired but already resumed")
                        return 
                    }
                    hasResumed = true
                    
                    // Restore original delegate and clean up immediately to prevent crashes
                    DispatchQueue.main.async {
                        webView.navigationDelegate = originalDelegate
                        webView.stopLoading()
                    }
                    
                    switch result {
                    case .success(let html):
                        Logger.debug("✅ [LinkedIn Scraper] Successfully loaded page HTML (\(html.count) characters)")
                    case .failure(let error):
                        Logger.error("🚨 [LinkedIn Scraper] Failed to load page: \(error)")
                    }
                    
                    // Close debug window after a brief delay (only if it was shown)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        if debugWindow?.isVisible == true {
                            debugWindow?.close()
                        }
                    }
                    
                    continuation.resume(with: result)
                }
                webView.navigationDelegate = scrapeDelegate
                
                // Start by loading LinkedIn feed to establish session context
                let feedURL = URL(string: "https://www.linkedin.com/feed/")!
                var request = URLRequest(url: feedURL)
                request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
                request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
                request.setValue("en-US,en;q=0.5", forHTTPHeaderField: "Accept-Language")
                request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
                request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
                request.timeoutInterval = 60.0
                
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
                    webView.evaluateJavaScript("document.readyState") { result, error in
                        if let readyState = result as? String, readyState == "complete" {
                            Logger.debug("🔍 [LinkedIn Scraper] Fallback detected page ready state: complete")
                            
                            // Also check what URL we're actually on
                            webView.evaluateJavaScript("window.location.href") { urlResult, urlError in
                                if let currentURL = urlResult as? String {
                                    Logger.debug("🔍 [LinkedIn Scraper] Current page URL: \(currentURL)")
                                    if currentURL == "about:blank" {
                                        Logger.warning("⚠️ [LinkedIn Scraper] Page is blank! LinkedIn may have blocked the request")
                                    }
                                }
                            }
                            
                            // Give it a moment more then extract HTML
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                guard !hasResumed else { return }
                                
                                webView.evaluateJavaScript("document.documentElement.outerHTML") { htmlResult, htmlError in
                                    guard !hasResumed else { return }
                                    hasResumed = true
                                    
                                    if let htmlError = htmlError {
                                        Logger.error("🚨 [LinkedIn Scraper] Fallback HTML extraction failed: \(htmlError)")
                                        continuation.resume(throwing: htmlError)
                                    } else if let html = htmlResult as? String {
                                        Logger.info("✅ [LinkedIn Scraper] Fallback successfully extracted HTML (\(html.count) characters)")
                                        
                                        // Debug: log the actual HTML if it's suspiciously short
                                        if html.count < 1000 {
                                            Logger.warning("⚠️ [LinkedIn Scraper] HTML content seems too short, here's what we got:")
                                            Logger.warning("   \(html.prefix(200))")
                                        }
                                        
                                        // Close debug window after a brief delay (only if it was shown)
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                            if debugWindow?.isVisible == true {
                                                debugWindow?.close()
                                            }
                                        }
                                        continuation.resume(returning: html)
                                    } else {
                                        Logger.error("🚨 [LinkedIn Scraper] Fallback HTML extraction returned unexpected type")
                                        continuation.resume(throwing: URLError(.cannotDecodeContentData))
                                    }
                                }
                            }
                        } else if fallbackAttempts < maxFallbackAttempts {
                            // Try again in 2 seconds
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                checkPageLoaded()
                            }
                        } else {
                            // Continue trying - the main timeout will handle giving up
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                checkPageLoaded()
                            }
                        }
                    }
                }
                
                // Show debug window after 10 seconds if scraping hasn't completed
                DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                    guard !hasResumed else { return }
                    Logger.info("🪟 [LinkedIn Scraper] Showing debug window - scraping taking longer than expected")
                    debugWindow?.makeKeyAndOrderFront(nil)
                    checkPageLoaded()
                }
                
                // Ultimate timeout after 60 seconds to allow fallback to ScrapingDog
                DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                    guard !hasResumed else { return }
                    hasResumed = true
                    Logger.warning("⚠️ [LinkedIn Scraper] Timeout reached after 60 seconds - will fallback to ScrapingDog")
                    
                    // Restore original delegate and clean up to prevent crashes
                    webView.navigationDelegate = originalDelegate
                    webView.stopLoading()
                    
                    // Keep debug window open longer on timeout so we can see what happened
                    Logger.info("🪟 [LinkedIn Scraper] Debug window will stay open for 10 seconds so you can inspect the page")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                        debugWindow?.close()
                    }
                    
                    continuation.resume(throwing: URLError(.timedOut))
                }
            }
        }
    }
    
    /// Parse LinkedIn job listing HTML using SwiftSoup
    static func parseLinkedInJobListing(html: String, url: String) -> JobApp? {
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
            
            // Extract location
            if let locationElement = try? doc.select(".job-details-jobs-unified-top-card__primary-description-container .t-black--light, .jobs-unified-top-card__bullet").first() {
                let locationText = try locationElement.text().trimmingCharacters(in: .whitespacesAndNewlines)
                // LinkedIn often shows location with other info, extract just the location part
                jobApp.jobLocation = locationText.components(separatedBy: " · ").first ?? locationText
                Logger.debug("📍 Extracted location: \(jobApp.jobLocation)")
            }
            
            // Extract job description
            if let descriptionElement = try? doc.select("#job-details, .job-details-jobs-unified-top-card__job-description, .jobs-description-content__text").first() {
                let rawDescription = try descriptionElement.html()
                // Clean up HTML tags and normalize whitespace
                jobApp.jobDescription = cleanJobDescription(rawDescription)
                Logger.debug("📝 Extracted description length: \(jobApp.jobDescription.count) characters")
            }
            
            // Extract apply link
            if let applyElement = try? doc.select("a[data-test-id=\"job-apply-link\"], .jobs-apply-button, a[href*=\"apply\"]").first(),
               let applyHref = try? applyElement.attr("href") {
                if applyHref.hasPrefix("http") {
                    jobApp.jobApplyLink = applyHref
                } else {
                    jobApp.jobApplyLink = "https://www.linkedin.com" + applyHref
                }
                Logger.debug("🔗 Extracted apply link: \(jobApp.jobApplyLink)")
            }
            
            // Extract additional metadata if available
            if let metaElements = try? doc.select(".job-details-jobs-unified-top-card__job-insight .job-details-jobs-unified-top-card__job-insight-view-model-secondary") {
                for element in metaElements {
                    let text = try element.text().lowercased()
                    if text.contains("employment type") || text.contains("full-time") || text.contains("part-time") || text.contains("contract") {
                        jobApp.employmentType = try element.text()
                    } else if text.contains("seniority") || text.contains("level") {
                        jobApp.seniorityLevel = try element.text()
                    }
                }
            }
            
            // Validate that we got essential information
            guard !jobApp.jobPosition.isEmpty && !jobApp.companyName.isEmpty else {
                Logger.warning("⚠️ LinkedIn job extraction failed - missing essential data")
                return nil
            }
            
            Logger.info("✅ Successfully parsed LinkedIn job: \(jobApp.jobPosition) at \(jobApp.companyName)")
            return jobApp
            
        } catch {
            Logger.error("🚨 SwiftSoup parsing error: \(error)")
            return nil
        }
    }
    
    /// Clean and normalize job description HTML
    private static func cleanJobDescription(_ html: String) -> String {
        do {
            let doc = try SwiftSoup.parse(html)
            let text = try doc.text()
            return text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                      .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            // Fallback: strip HTML tags with regex
            return html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                      .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    
}

// MARK: - Navigation Delegate Helper

private class LinkedInJobScrapeDelegate: NSObject, WKNavigationDelegate {
    let targetURL: URL
    let completion: (Result<String, Error>) -> Void
    private var hasCompleted = false
    private var navigationStep = 0 // 0 = feed, 1 = job page
    
    init(targetURL: URL, completion: @escaping (Result<String, Error>) -> Void) {
        self.targetURL = targetURL
        self.completion = completion
        super.init()
        Logger.debug("🔍 [LinkedInJobScrapeDelegate] Delegate initialized for target: \(targetURL.absoluteString)")
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                var request = URLRequest(url: self.targetURL)
                request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
                request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
                request.setValue("en-US,en;q=0.5", forHTTPHeaderField: "Accept-Language")
                request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
                request.setValue("https://www.linkedin.com/feed/", forHTTPHeaderField: "Referer")
                request.timeoutInterval = 60.0
                
                Logger.debug("🔍 [LinkedInJobScrapeDelegate] Step 2: Loading job page with proper referer")
                webView.load(request)
            }
        } else {
            // Finished loading job page, extract HTML
            Logger.debug("🔍 [LinkedInJobScrapeDelegate] Step 2 complete, extracting job page HTML")
            
            // Wait a moment for dynamic content to load
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                Logger.debug("🔍 [LinkedInJobScrapeDelegate] Extracting HTML after 3 second delay...")
                webView.evaluateJavaScript("document.documentElement.outerHTML") { result, error in
                    guard !self.hasCompleted else {
                        Logger.debug("🔍 [LinkedInJobScrapeDelegate] JavaScript completed but already handled")
                        return
                    }
                    self.hasCompleted = true
                    
                    // Clear delegate reference and stop loading to prevent further callbacks
                    DispatchQueue.main.async {
                        if webView.navigationDelegate === self {
                            webView.navigationDelegate = nil
                            webView.stopLoading()
                        }
                    }
                    
                    if let error = error {
                        Logger.error("🚨 [LinkedInJobScrapeDelegate] JavaScript evaluation failed: \(error)")
                        self.completion(.failure(error))
                    } else if let html = result as? String {
                        Logger.debug("✅ [LinkedInJobScrapeDelegate] Successfully extracted HTML (\(html.count) characters)")
                        
                        // Debug: log the actual HTML if it's suspiciously short
                        if html.count < 1000 {
                            Logger.warning("⚠️ [LinkedInJobScrapeDelegate] HTML content seems too short, here's what we got:")
                            Logger.warning("   \(html.prefix(200))")
                        }
                        
                        self.completion(.success(html))
                    } else {
                        Logger.error("🚨 [LinkedInJobScrapeDelegate] JavaScript returned unexpected result type")
                        self.completion(.failure(URLError(.cannotDecodeContentData)))
                    }
                }
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Logger.error("🚨 [LinkedInJobScrapeDelegate] didFail navigation (step \(navigationStep)): \(error)")
        guard !hasCompleted else { return }
        hasCompleted = true
        
        // Clear delegate reference and stop loading to prevent further callbacks
        DispatchQueue.main.async {
            if webView.navigationDelegate === self {
                webView.navigationDelegate = nil
                webView.stopLoading()
            }
        }
        
        completion(.failure(error))
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Logger.error("🚨 [LinkedInJobScrapeDelegate] didFailProvisionalNavigation (step \(navigationStep)): \(error)")
        guard !hasCompleted else { return }
        hasCompleted = true
        
        // Clear delegate reference and stop loading to prevent further callbacks
        DispatchQueue.main.async {
            if webView.navigationDelegate === self {
                webView.navigationDelegate = nil
                webView.stopLoading()
            }
        }
        
        completion(.failure(error))
    }
    
    deinit {
        Logger.debug("🔍 [LinkedInJobScrapeDelegate] Delegate deallocated")
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url {
            Logger.debug("🔍 [LinkedInJobScrapeDelegate] Navigation policy for: \(url.absoluteString)")
            
            // Check for potential security challenges or redirects that might cause blank pages
            if url.absoluteString.contains("linkedin.com/checkpoint") ||
               url.absoluteString.contains("linkedin.com/challenge") ||
               url.absoluteString.contains("linkedin.com/security") {
                Logger.warning("⚠️ [LinkedInJobScrapeDelegate] LinkedIn security challenge detected: \(url.absoluteString)")
            }
            
            // Check for external redirects that might indicate bot detection
            if ((url.host?.contains("linkedin.com")) != nil) == true &&
               !url.absoluteString.hasPrefix("about:") &&
               !url.absoluteString.hasPrefix("data:") {
                Logger.warning("⚠️ [LinkedInJobScrapeDelegate] External redirect detected (possible bot detection): \(url.absoluteString)")
            }
        }
        decisionHandler(.allow)
    }
}


