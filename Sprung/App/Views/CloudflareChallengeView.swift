//
//  CloudflareChallengeView.swift
//  Sprung
//
//
import SwiftUI
import WebKit
/// A SwiftUI wrapper around `WKWebView` that is presented when the automated
/// Cloudflare handling fails and the user needs to complete a manual
/// verification (e.g. CAPTCHA). The view watches for the job page content
/// and dismisses itself once the actual job listing page is loaded.
///
/// This view uses the shared `WebViewNavigationHelper` to handle navigation
/// logic, success detection, and cookie storage.
struct CloudflareChallengeView: NSViewRepresentable {
    let url: URL
    @Binding var isPresented: Bool
    var onSuccess: (() -> Void)?

    // MARK: NSViewRepresentable

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: cfg)
        webView.navigationDelegate = context.coordinator.navigationHelper
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

    // MARK: Coordinator

    @MainActor
    class Coordinator: NSObject {
        let parent: CloudflareChallengeView
        let navigationHelper: WebViewNavigationHelper

        init(parent: CloudflareChallengeView) {
            self.parent = parent

            // Configure the navigation helper with Indeed-specific success detection
            var config = WebViewNavigationHelper.Configuration()
            config.successDetectionScript = """
                (document.querySelector('.jobsearch-JobInfoHeader-title') !== null) ||
                (document.querySelector('#jobDescriptionText') !== null) ||
                (document.querySelector('.jobsearch-JobComponent') !== null)
            """
            config.storeClearanceCookies = true
            config.maxWaitTime = 15.0
            config.successDelay = 1.0  // Give user a moment to verify the page loaded

            self.navigationHelper = WebViewNavigationHelper(
                url: parent.url,
                config: config
            ) {
                // Notify the caller that the challenge has been solved
                // *before* we close the sheet so it can immediately retry
                // the failed network request.
                parent.onSuccess?()

                // Dismiss the sheet after the configured delay
                parent.isPresented = false
            }

            super.init()
        }
    }
}
