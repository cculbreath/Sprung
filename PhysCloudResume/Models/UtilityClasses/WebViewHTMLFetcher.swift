//
//  WebViewHTMLFetcher.swift
//  PhysCloudResume
//
//  A tiny utility that loads a URL in an invisible WKWebView (sharing the
//  default data‑store, hence the same cookies as CloudflareCookieManager)
//  and returns the final rendered HTML of the page once `didFinish` fires.
//  This is a heavier‑weight fallback for sites where a raw `URLSession` fetch
//  continues to be blocked by Cloudflare even after solving the challenge.
//

import Foundation
import WebKit

@MainActor
enum WebViewHTMLFetcher {
    /// Loads the given URL in a hidden WKWebView and returns the page’s outer
    /// HTML once navigation completes.
    /// – Parameter timeout: Optional time‑out in seconds (default 20 s).
    static func html(for url: URL, timeout: TimeInterval = 20) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            let helper = Helper(url: url, timeout: timeout, cont)
            helper.start()
        }
    }

    // MARK: – Internal helper ------------------------------------------------

    private final class Helper: NSObject, WKNavigationDelegate {
        private let url: URL
        private let timeout: TimeInterval
        private var continuation: CheckedContinuation<String, Error>?
        private var webView: WKWebView!
        private var selfRetain: Helper?

        init(url: URL, timeout: TimeInterval, _ cont: CheckedContinuation<String, Error>) {
            self.url = url
            self.timeout = timeout
            continuation = cont
            super.init()
            selfRetain = self

            let cfg = WKWebViewConfiguration()
            cfg.websiteDataStore = .default()
            webView = WKWebView(frame: .zero, configuration: cfg)
            webView.isHidden = true
            webView.navigationDelegate = self
        }

        func start() {
            webView.load(URLRequest(url: url))

            if timeout > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                    self?.finishWithError(URLError(.timedOut))
                }
            }
        }

        // MARK: – WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            webView.evaluateJavaScript("document.documentElement.outerHTML.toString()") { [weak self] result, error in
                guard let self else { return }
                if let html = result as? String {
                    self.finish(html)
                } else {
                    self.finishWithError(error ?? URLError(.cannotDecodeContentData))
                }
            }
        }

        func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
            finishWithError(error)
        }

        // MARK: – Completion helpers

        private func finish(_ html: String) {
            continuation?.resume(returning: html)
            cleanUp()
        }

        private func finishWithError(_ error: Error) {
            continuation?.resume(throwing: error)
            cleanUp()
        }

        private func cleanUp() {
            continuation = nil
            selfRetain = nil
        }
    }
}
