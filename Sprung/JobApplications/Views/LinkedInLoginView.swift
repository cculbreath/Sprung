//
//  LinkedInLoginView.swift
//  Sprung
//
import SwiftUI
import WebKit
import ObjectiveC
/// Interactive LinkedIn login view that handles Google SSO and other authentication methods
struct LinkedInLoginView: NSViewRepresentable {
    @Binding var isPresented: Bool
    let sessionManager: LinkedInSessionStore
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        // Enable JavaScript and popups (required for Google SSO)
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.autoresizingMask = [.width, .height]
        // Start with LinkedIn login page
        let loginURL = URL(string: "https://www.linkedin.com/login")!
        webView.load(URLRequest(url: loginURL))
        return webView
    }
    func updateNSView(_ webView: WKWebView, context: Context) {
        // Update coordinator reference
        context.coordinator.parent = self
    }
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: LinkedInLoginView
        init(parent: LinkedInLoginView) {
            self.parent = parent
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("window.location.href") { result, _ in
                if let urlString = result as? String, urlString.contains("linkedin.com") {
                    Logger.debug("🔗 [LinkedIn Login] Page loaded: \(urlString)")
                    self.injectLoginHelpers(webView)
                }
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
            if let url = navigationAction.request.url {
                Logger.debug("🔗 LinkedIn navigation to: \(url.absoluteString)")
                // Detect Google OAuth completion so we can close the popup window
                if url.absoluteString.contains("accounts.google.com") &&
                   (url.absoluteString.contains("oauth") || url.absoluteString.contains("signin/oauth")) {
                    Logger.debug("🔗 Google OAuth flow detected in popup")
                    if let window = objc_getAssociatedObject(webView, "popupWindow") as? NSWindow {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            self.checkForOAuthCompletion(webView, window: window)
                        }
                    }
                }
            }
        }
        // MARK: - WKUIDelegate for popup handling
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            Logger.debug("🪟 [LinkedIn Login] Creating popup for: \(navigationAction.request.url?.absoluteString ?? "unknown")")
            // For Google SSO, create a proper popup webview that can communicate back
            if let url = navigationAction.request.url,
               url.host?.contains("google") == true || url.host?.contains("accounts.google.com") == true {
                Logger.info("🔗 Creating Google SSO popup webview: \(url.absoluteString)")
                // Create a popup webview with the same configuration to maintain session
                let popupWebView = WKWebView(frame: CGRect(x: 0, y: 0, width: 500, height: 600), configuration: configuration)
                popupWebView.navigationDelegate = self
                popupWebView.uiDelegate = self
                // Create a window to host the popup
                let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 600),
                                    styleMask: [.titled, .closable, .resizable],
                                    backing: .buffered,
                                    defer: false)
                window.title = "Sign in with Google"
                window.contentView = popupWebView
                window.center()
                window.makeKeyAndOrderFront(nil)
                // Store strong reference to keep window alive while webview exists
                // Using RETAIN to prevent use-after-free during window animations
                objc_setAssociatedObject(popupWebView, "popupWindow", window, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                return popupWebView
            }
            // For other popups, create a standard webview
            let popupWebView = WKWebView(frame: .zero, configuration: configuration)
            popupWebView.navigationDelegate = self
            popupWebView.uiDelegate = self
            return popupWebView
        }
        func webViewDidClose(_ webView: WKWebView) {
            Logger.debug("🪟 [LinkedIn Login] WebView popup closed")
            // Close associated window if it exists and is still valid
            if let window = objc_getAssociatedObject(webView, "popupWindow") as? NSWindow,
               window.isVisible {
                DispatchQueue.main.async {
                    window.close()
                    // Clean up association AFTER close to prevent use-after-free during animations
                    objc_setAssociatedObject(webView, "popupWindow", nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                }
            } else {
                // No visible window, safe to clean up immediately
                objc_setAssociatedObject(webView, "popupWindow", nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
        }
        private func checkForOAuthCompletion(_ webView: WKWebView, window: NSWindow) {
            // Check if window is still valid before proceeding
            guard window.isVisible else {
                Logger.debug("🔍 [Google OAuth] Window closed, stopping monitoring")
                return
            }
            // Check if the Google OAuth flow has completed
            webView.evaluateJavaScript("window.location.href") { result, _ in
                if let urlString = result as? String {
                    Logger.debug("🔍 [Google OAuth] Checking completion status: \(urlString)")
                    // Check for completion indicators or if the page has closed itself
                    if urlString.contains("close") ||
                       urlString.contains("success") ||
                       urlString == "about:blank" {
                        Logger.info("✅ Google OAuth completed, closing popup")
                        DispatchQueue.main.async {
                            if window.isVisible {
                                window.close()
                            }
                            // Clean up association AFTER close with delay to allow animations to complete
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                objc_setAssociatedObject(webView, "popupWindow", nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                            }
                        }
                    } else {
                        // Continue monitoring only if window is still visible
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            if window.isVisible {
                                self.checkForOAuthCompletion(webView, window: window)
                            }
                        }
                    }
                }
            }
        }
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            Logger.debug("⚠️ [LinkedIn Login] JavaScript alert: \(message)")
            completionHandler()
        }
        private func injectLoginHelpers(_ webView: WKWebView) {
            // Inject helpful CSS and JavaScript for better login experience (LinkedIn only)
            let script = """
                (function() {
                    // Only run on LinkedIn pages
                    if (!window.location.href.includes('linkedin.com')) {
                        return;
                    }
                    // Highlight the Google sign-in button if available
                    const googleButton = document.querySelector('[data-test-id="google-oauth"], [aria-label*="Google"], .google-auth-button, button[title*="Google"]');
                    if (googleButton) {
                        googleButton.style.border = '2px solid #4285f4';
                        googleButton.style.borderRadius = '4px';
                        console.log('Google SSO button found and highlighted');
                    }
                    // Add visual indicator for LinkedIn direct login
                    const linkedinButton = document.querySelector('[data-test-id="sign-in-form__submit-btn"], .sign-in-form__submit-button');
                    if (linkedinButton) {
                        linkedinButton.style.border = '2px solid #0077b5';
                        linkedinButton.style.borderRadius = '4px';
                    }
                    // Focus the email field if present
                    const emailField = document.querySelector('#username, [name="session_key"], input[type="email"]');
                    if (emailField) {
                        emailField.focus();
                    }
                })();
            """
            webView.evaluateJavaScript(script) { _, error in
                if let error = error {
                    Logger.debug("📱 Login helper injection failed: \(error)")
                }
            }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Logger.error("🚨 LinkedIn login navigation failed: \(error)")
        }
    }
}
// MARK: - LinkedIn Login Sheet
struct LinkedInLoginSheet: View {
    @Binding var isPresented: Bool
    var sessionManager: LinkedInSessionStore
    var onSuccess: (() -> Void)?
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Sign in to LinkedIn")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.borderless)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color.gray.opacity(0.3)),
                alignment: .bottom
            )
            // Instructions
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text("Sign in to LinkedIn to import job details")
                        .font(.subheadline)
                }
                Text("• Use your Google account if that's how you normally sign in")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("• This session will be saved for future job imports")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            // Web View
            LinkedInLoginView(
                isPresented: $isPresented,
                sessionManager: sessionManager
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Footer with status
            HStack {
                if sessionManager.isLoggedIn {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Successfully signed in")
                            .font(.subheadline)
                    }
                } else {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Waiting for sign in...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button("Done") {
                    isPresented = false
                }
                .disabled(!sessionManager.isLoggedIn)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color.gray.opacity(0.3)),
                alignment: .top
            )
        }
        .frame(minWidth: 600, idealWidth: 800, maxWidth: .infinity,
               minHeight: 700, idealHeight: 900, maxHeight: .infinity)
        .onChange(of: sessionManager.isLoggedIn) { _, newValue in
            guard newValue else { return }
            onSuccess?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                isPresented = false
            }
        }
    }
}
// MARK: - LinkedIn Session Status View
struct LinkedInSessionStatusView: View {
    var sessionManager: LinkedInSessionStore
    @State private var showLoginSheet = false
    var body: some View {
        HStack(spacing: 12) {
            // LinkedIn logo and status indicator
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue)
                        .frame(width: 24, height: 24)
                    Text("in")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("LinkedIn")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        // Status indicator
                        Circle()
                            .fill(sessionManager.isLoggedIn ? .green : .orange)
                            .frame(width: 6, height: 6)
                    }
                    Text(sessionManager.isLoggedIn ? "Connected" : "Not connected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            // Action button
            if sessionManager.sessionExpired {
                Button("Reconnect") {
                    showLoginSheet = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else if !sessionManager.isLoggedIn {
                Button("Connect") {
                    showLoginSheet = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                Button("Disconnect") {
                    sessionManager.clearSession()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(sessionManager.isLoggedIn ? Color.green.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
        .sheet(isPresented: $showLoginSheet) {
            LinkedInLoginSheet(
                isPresented: $showLoginSheet,
                sessionManager: sessionManager
            )
        }
    }
}
