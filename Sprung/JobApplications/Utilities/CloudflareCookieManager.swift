//
//  CloudflareCookieManager.swift
//  Sprung
//
//  Created by Christopher Culbreath on 4/19/25.
//
import Foundation
import WebKit
@MainActor
/// Persists Cloudflare `cf_clearance` cookies so headless fetches can bypass
/// subsequent challenges.
///
/// Cookies are stored under the user's Application Support directory on macOS.
/// When adapting this helper to iOS, prefer persisting data via the keychain.
final class CloudflareCookieManager: NSObject, WKNavigationDelegate {
    // MARK: Public -------------------------------------------------
    /// Ensures a valid `cf_clearance` cookie exists for the given URL’s host.
    /// - Returns: The cookie (newly fetched or cached) or `nil` if we failed.
    static func clearance(for url: URL) async -> HTTPCookie? {
        let host = url.host ?? ""
        // 1. Return cached cookie if still valid
        if let cached = existingCookie(for: host) {
            return cached
        }
        // 2. Need to perform the Cloudflare challenge in a hidden WebView
        return await withCheckedContinuation { cont in
            let helper = CloudflareCookieManager(targetURL: url, cont)
            helper.startChallenge()
        }
    }
    /// Forces a fresh Cloudflare challenge even if a cached cookie exists.  Use
    /// this when we received a Cloudflare *block* page despite having a cookie –
    /// odds are the cookie has expired or been revoked.
    static func refreshClearance(for url: URL) async -> HTTPCookie? {
        // Drop any previously cached cookie so that `clearance(for:)` performs
        // a new challenge.
        if let host = url.host {
            let fileURL = cookieFileURL(for: host)
            try? FileManager.default.removeItem(at: fileURL)
        }
        return await clearance(for: url)
    }
    // MARK: Internals ---------------------------------------------
    private let targetURL: URL
    private var continuation: CheckedContinuation<HTTPCookie?, Never>?
    private var webView: WKWebView!
    private var selfRetain: CloudflareCookieManager? // keep self alive
    private init(targetURL: URL, _ cont: CheckedContinuation<HTTPCookie?, Never>) {
        self.targetURL = targetURL
        continuation = cont
        super.init()
        selfRetain = self
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: cfg)
        webView.navigationDelegate = self
        webView.isHidden = true // headless
    }
    private func startChallenge() {
        webView.load(URLRequest(url: targetURL))
    }
    private func finish(with cookie: HTTPCookie?) {
        continuation?.resume(returning: cookie)
        continuation = nil
        selfRetain = nil // release self
    }
    // MARK: WKNavigationDelegate ----------------------------------
    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        // Poll for up to 20 seconds (40 × 0.5 s) because Cloudflare sets the
        // cookie via JavaScript and then auto‑redirects.
        pollForClearanceCookie(remainingAttempts: 40)
    }
    private func pollForClearanceCookie(remainingAttempts: Int) {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self else { return }
            if let clearance = cookies.first(where: { $0.name == "cf_clearance" &&
                    ((self.targetURL.host ?? "").hasSuffix($0.domain))
            }) {
                CloudflareCookieManager.store(cookie: clearance)
                self.finish(with: clearance)
                return
            }
            if remainingAttempts > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.pollForClearanceCookie(remainingAttempts: remainingAttempts - 1)
                }
            } else {
                self.finish(with: nil) // Timed out
            }
        }
    }
    func webView(_: WKWebView, didFail _: WKNavigation!, withError _: Error) {
        finish(with: nil)
    }
    // MARK: Persistence -------------------------------------------
    private static func key(for domain: String) -> String { "cf_clearance_\(domain)" }
    /// Directory where cookies are stored as plist files under Application Support.
    private static func cookieDirectoryURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("CloudflareCookieManager", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            Logger.error("Failed to create cookie directory: \(error)")
        }
        return dir
    }
    /// File URL for the stored cookie plist for a given domain.
    private static func cookieFileURL(for domain: String) -> URL {
        let filename = key(for: domain) + ".plist"
        return cookieDirectoryURL().appendingPathComponent(filename)
    }
    // We serialise cookie.properties (a `[HTTPCookiePropertyKey: Any]` dictionary)
    // using `PropertyListSerialization` as it is fully Codable‑free and avoids
    // the NSCoding requirement (HTTPCookie does *not* conform to NSCoding on all
    // platforms).
    private static func existingCookie(for domain: String) -> HTTPCookie? {
        let fileURL = cookieFileURL(for: domain)
        guard
            let data = try? Data(contentsOf: fileURL),
            let rawDict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { return nil }
        // Convert String‑keyed dictionary back to HTTPCookiePropertyKey keys
        var props: [HTTPCookiePropertyKey: Any] = [:]
        for (k, v) in rawDict {
            props[HTTPCookiePropertyKey(k)] = v
        }
        guard let cookie = HTTPCookie(properties: props),
              cookie.expiresDate ?? .distantPast > .now
        else { return nil }
        return cookie
    }
    static func store(cookie: HTTPCookie) {
        guard let props = cookie.properties else { return }
        // Convert keys to String for property‑list
        let stringDict = Dictionary(uniqueKeysWithValues: props.map { ($0.key.rawValue, $0.value) })
        guard let data = try? PropertyListSerialization.data(fromPropertyList: stringDict, format: .binary, options: 0) else {
            return
        }
        let fileURL = cookieFileURL(for: cookie.domain)
        try? data.write(to: fileURL, options: .atomic)
    }
}
