// Sprung/AI/Views/MarkdownView.swift
import SwiftUI
import WebKit

// Create a wrapper View struct that contains the NSViewRepresentable
struct MarkdownView: View {
    let markdown: String

    var body: some View {
        MarkdownWebView(markdown: markdown)
    }
}

// Rename the original NSViewRepresentable to MarkdownWebView
struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    @Environment(\.colorScheme) var colorScheme

    // HTML template that includes marked.js from a CDN and basic styling
    // Placeholders will be replaced with dynamic values (e.g., for dark mode)
    private func getHtmlTemplate() -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, shrink-to-fit=no, user-scalable=no">
            <title>Markdown Render</title>
            <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                    font-size: 15px;
                    line-height: 1.6;
                    padding: 0px; /* SwiftUI will handle padding around this view */
                    margin: 0px;
                    color: \(colorScheme == .dark ? "#E0E0E0" : "#222222");
                    background-color: transparent;
                    word-wrap: break-word; /* Ensure long words in text or table cells break */
                }
                table {
                    border-collapse: collapse;
                    width: 100%;
                    margin-top: 1em;
                    margin-bottom: 1em;
                    border: 1px solid \(colorScheme == .dark ? "#555555" : "#CCCCCC");
                }
                th, td {
                    border: 1px solid \(colorScheme == .dark ? "#505050" : "#D3D3D3");
                    padding: 8px;
                    text-align: left;
                }
                th {
                    background-color: \(colorScheme == .dark ? "#3A3A3A" : "#F0F0F0");
                    font-weight: bold;
                }
                h1, h2, h3, h4, h5, h6 { 
                    margin-top: 1.2em; 
                    margin-bottom: 0.6em; 
                    font-weight: 600;
                    color: \(colorScheme == .dark ? "#F0F0F0" : "#111111");
                }
                p { 
                    margin-top: 0;
                    margin-bottom: 0.8em; 
                }
                ul, ol { 
                    margin-left: 0; /* Reset default browser margin */
                    padding-left: 1.8em; /* Indent lists */
                    margin-bottom: 0.8em; 
                }
                li { 
                    margin-bottom: 0.3em; 
                }
                code { 
                    font-family: "SF Mono", Menlo, Consolas, "Courier New", monospace; 
                    background-color: \(colorScheme == .dark ? "#383838" : "#F5F5F5"); 
                    padding: 0.2em 0.4em; 
                    border-radius: 4px; 
                    font-size: 90%;
                    border: 1px solid \(colorScheme == .dark ? "#4A4A4A" : "#E5E5E5");
                }
                pre { 
                    background-color: \(colorScheme == .dark ? "#2C2C2C" : "#F8F8F8"); 
                    padding: 12px; 
                    border-radius: 6px; 
                    overflow-x: auto; 
                    border: 1px solid \(colorScheme == .dark ? "#454545" : "#E0E0E0");
                    font-size: 85%;
                }
                pre code { 
                    padding: 0; 
                    background-color: transparent; 
                    border-radius: 0; 
                    border: none;
                }
                blockquote { 
                    border-left: 4px solid \(colorScheme == .dark ? "#666666" : "#BBBBBB"); 
                    padding-left: 1em; 
                    margin-left: 0; 
                    margin-top: 1em;
                    margin-bottom: 1em;
                    color: \(colorScheme == .dark ? "#B0B0B0" : "#555555");
                    font-style: italic;
                }
                a { 
                    color: #007AFF; /* Standard iOS blue link color */
                    text-decoration: none; 
                }
                a:hover { 
                    text-decoration: underline; 
                }
                img { 
                    max-width: 100%; 
                    height: auto; 
                    border-radius: 4px;
                }
            </style>
        </head>
        <body>
            <div id="markdown-content"></div>
            <script>
                // Safely escape the markdown content for JavaScript string
                // Then decode it for marked.parse
                var rawMarkdown = decodeURIComponent("MARKDOWN_JS_PLACEHOLDER");
                try {
                    if (typeof marked !== 'undefined') {
                        document.getElementById('markdown-content').innerHTML = marked.parse(rawMarkdown);
                    } else {
                        document.getElementById('markdown-content').innerText = "Error: marked.js library not loaded.\\n\\nRaw Markdown:\\n" + rawMarkdown;
                    }
                } catch (e) {
                    document.getElementById('markdown-content').innerText = "Error rendering markdown: " + e.message + "\\n\\nRaw Markdown:\\n" + rawMarkdown;
                }
            </script>
        </body>
        </html>
        """
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        // For macOS, to make the background transparent:
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context _: Context) {
        // URL-encode the markdown string to safely inject it into the JavaScript block
        guard let encodedMarkdown = markdown.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            nsView.loadHTMLString("<html><body>Error: Could not encode markdown content.</body></html>", baseURL: nil)
            return
        }

        let finalHtml = getHtmlTemplate().replacingOccurrences(of: "MARKDOWN_JS_PLACEHOLDER", with: encodedMarkdown)
        nsView.loadHTMLString(finalHtml, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKNavigationDelegate {

        // Example: Open external links in the system browser
        func webView(_: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                // Check if it's an external link (http or https)
                if ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                    NSWorkspace.shared.open(url)
                    decisionHandler(.cancel) // Cancel navigation in WKWebView
                    return
                }
            }
            decisionHandler(.allow) // Allow other navigation types
        }
    }
}
