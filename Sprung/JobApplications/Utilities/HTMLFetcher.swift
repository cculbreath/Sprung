//
//  HTMLFetcher.swift
//  Sprung
//
//  Created by Christopher Culbreath on 4/19/25.
//
import Foundation
extension JobApp {
    /// Downloads job listing HTML while presenting a desktop user agent and attaching
    /// any cached Cloudflare clearance cookie. Retries when a challenge page is detected.
    // Common HTTP header strings (shared by all job‑scrape requests)
    static let desktopUA =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    static let acceptHdr = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    static let langHdr = "en-US,en;q=0.5"
    /// Downloads the HTML document at `urlString` emulating a regular desktop
    /// browser. A valid `cf_clearance` cookie (if any) is attached.
    ///
    /// The method throws on network/HTTP failure or when the response cannot
    /// be decoded as UTF‑8.
    static func fetchHTMLContent(from urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        // Configure the URLSession request.
        var attempt = 0
        let maxAttempts = 4 // first fetch + up to three retries after challenge
        while attempt < maxAttempts {
            attempt += 1
            var request = URLRequest(url: url)
            request.setValue(Self.desktopUA, forHTTPHeaderField: "User-Agent")
            request.setValue(Self.acceptHdr, forHTTPHeaderField: "Accept")
            request.setValue(Self.langHdr, forHTTPHeaderField: "Accept-Language")
            // Attach cf_clearance cookie if available.
            let cookie: HTTPCookie? = await CloudflareCookieManager.clearance(for: url)
            if let cookie {
                let cookieHeader = "\(cookie.name)=\(cookie.value)"
                request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            }
            // Perform request
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let htmlContent = String(data: data, encoding: .utf8) else {
                throw URLError(.cannotDecodeContentData)
            }
            // Detect Cloudflare challenge pages.
            let cfIndicators = [
                "Attention Required! | Cloudflare",
                "Just a moment…",
                "Just a moment...",
                "Checking if the site connection is secure",
                "cf-browser-verification",
                "Request Blocked",
                "You have been blocked",
                "Blocked - Indeed.com",
                "Security Check - Indeed.com",
                "Additional Verification Required",
            ]
            if cfIndicators.contains(where: { htmlContent.contains($0) }) {
                // Refresh clearance cookie via interactive challenge (if headless fails)
                _ = await CloudflareCookieManager.refreshClearance(for: url)
                continue // retry
            }
            return htmlContent
        }
        throw URLError(.badServerResponse)
    }
}
