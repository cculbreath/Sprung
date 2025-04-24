//
//  CloudflareChallengeView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/19/25.
//

import SwiftUI
import WebKit

/// A SwiftUI wrapper around `WKWebView` that is presented when the automated
/// Cloudflare handling fails and the user needs to complete a manual
/// verification (e.g. CAPTCHA).  The view watches the cookie store and
/// dismisses itself once a valid `cf_clearance` cookie for the target domain
/// has been saved.
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

        func webView(_: WKWebView, didFinish _: WKNavigation!) {
            // On every navigation completion check for the clearance cookie.
            checkForCookie()
        }

        // Poll the cookie store (every 0.5 s, up to 60 times -> 30 s) until we
        // find the clearance cookie.
        private func checkForCookie(remaining: Int = 60) {
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self else { return }
                if let cookie = cookies.first(where: { $0.name == "cf_clearance" &&
                        ((self.parent.url.host ?? "").hasSuffix($0.domain))
                }) {
                    // Persist the Cloudflare clearance cookie so that the
                    // background importer can reuse it.
                    CloudflareCookieManager.store(cookie: cookie)

                    // Notify the caller that the challenge has been solved
                    // *before* we close the sheet so it can immediately retry
                    // the failed network request.
                    self.parent.onSuccess?()

                    // Do not dismiss the web‑view instantly – give the user a
                    // short moment to verify that Cloudflare actually served
                    // the challenge / success page.  After a brief delay the
                    // sheet is closed automatically so that the surrounding
                    // UI continues to work as before.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        self.parent.isPresented = false
                    }
                    return
                }

                if remaining > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.checkForCookie(remaining: remaining - 1)
                    }
                }
            }
        }
    }
}
