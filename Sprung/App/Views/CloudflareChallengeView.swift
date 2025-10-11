//
//  CloudflareChallengeView.swift
//  Sprung
//
//  Created by Christopher Culbreath on 4/19/25.
//

import SwiftUI
import WebKit

/// A SwiftUI wrapper around `WKWebView` that is presented when the automated
/// Cloudflare handling fails and the user needs to complete a manual
/// verification (e.g. CAPTCHA). The view watches for the job page content
/// and dismisses itself once the actual job listing page is loaded.
struct CloudflareChallengeView: NSViewRepresentable {
    let url: URL
    @Binding var isPresented: Bool
    var onSuccess: (() -> Void)?

    // MARK: NSViewRepresentable ----------------------------------

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: cfg)
        webView.navigationDelegate = context.coordinator
        webView.autoresizingMask = [.width, .height]
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_: WKWebView, context _: Context) {
        // nothing
    }

    // Provide a sensible default size when inside `.sheet`.
    func defaultSize() -> some View {
        frame(minWidth: 600, idealWidth: 800, maxWidth: .infinity,
              minHeight: 700, idealHeight: 900, maxHeight: .infinity)
    }

    // MARK: Coordinator -----------------------------------------

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: CloudflareChallengeView
        init(parent: CloudflareChallengeView) { self.parent = parent }

        // Maximum time to wait before auto-dismissing (15 seconds)
        private let maxWaitTime: TimeInterval = 15.0
        // When the challenge view was first shown
        private var startTime = Date()

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            // Check if we've reached the job listing page
            checkForJobPage(webView)

            // Store any clearance cookie for future use
            storeClearanceCookie()

            // Check for timeout as a fallback
            checkForTimeout()
        }

        // Check if we've navigated to the actual job listing page
        private func checkForJobPage(_ webView: WKWebView) {
            // For Indeed.com, check if we're on the actual job page by looking for specific elements
            webView.evaluateJavaScript("""
                (document.querySelector('.jobsearch-JobInfoHeader-title') !== null) ||
                (document.querySelector('#jobDescriptionText') !== null) ||
                (document.querySelector('.jobsearch-JobComponent') !== null)
            """) { [weak self] result, _ in
                guard let self = self else { return }

                if let isJobPage = result as? Bool, isJobPage {
                    // We've reached the job page, complete and dismiss
                    self.completeChallengeAndDismiss()
                }
            }
        }

        // Check if we've exceeded the maximum wait time
        private func checkForTimeout() {
            if Date().timeIntervalSince(startTime) >= maxWaitTime {
                // We've waited long enough, proceed anyway
                completeChallengeAndDismiss()
            }
        }

        // Store the Cloudflare clearance cookie for future requests
        private func storeClearanceCookie() {
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                if let cookie = cookies.first(where: {
                    $0.name == "cf_clearance" &&
                        ((self.parent.url.host ?? "").hasSuffix($0.domain))
                }) {
                    // Persist the cookie for future use
                    CloudflareCookieManager.store(cookie: cookie)
                }
            }
        }

        // Complete the challenge and dismiss the view
        private func completeChallengeAndDismiss() {
            // Notify the caller that the challenge has been solved
            // *before* we close the sheet so it can immediately retry
            // the failed network request.
            parent.onSuccess?()

            // Do not dismiss the web-view instantly – give the user a
            // short moment to verify that Cloudflare actually served
            // the job page. After a brief delay the
            // sheet is closed automatically so that the surrounding
            // UI continues to work as before.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.parent.isPresented = false
            }
        }
    }
}
