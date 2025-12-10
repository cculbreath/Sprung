import Foundation

/// Fetches and inlines external fonts (e.g., Google Fonts) for offline PDF rendering.
/// Replaces @import url(...) statements with embedded @font-face declarations using base64 data URIs.
extension NativePDFGenerator {

    /// Inlines external font imports by fetching CSS and font files, converting to base64 data URIs.
    /// This enables headless Chrome to render fonts without network access during virtual-time-budget.
    func inlineExternalFonts(in html: String) async -> String {
        // Match @import url('...') or @import url("...") statements
        let importPattern = #"@import\s+url\(['\"]([^'\"]+)['\"\)]\s*\)?\s*;?"#
        guard let regex = try? NSRegularExpression(pattern: importPattern, options: [.caseInsensitive]) else {
            return html
        }

        let nsHTML = html as NSString
        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsHTML.length))

        if matches.isEmpty {
            return html
        }

        var result = html

        // Process each @import in reverse order to preserve string indices
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2,
                  let urlRange = Range(match.range(at: 1), in: html) else {
                continue
            }

            let importURL = String(html[urlRange])

            // Only process Google Fonts URLs
            guard importURL.contains("fonts.googleapis.com") else {
                continue
            }

            Logger.info("FontInliner: Processing font import: \(importURL)")

            // Fetch and inline the fonts
            if let inlinedCSS = await fetchAndInlineFonts(from: importURL) {
                // Replace the @import statement with inlined @font-face declarations
                if let fullMatchRange = Range(match.range, in: result) {
                    result.replaceSubrange(fullMatchRange, with: inlinedCSS)
                    Logger.info("FontInliner: Successfully inlined fonts from \(importURL)")
                }
            } else {
                Logger.warning("FontInliner: Failed to inline fonts from \(importURL)")
            }
        }

        return result
    }

    /// Fetches the Google Fonts CSS and converts font URLs to base64 data URIs.
    private func fetchAndInlineFonts(from cssURL: String) async -> String? {
        guard let url = URL(string: cssURL) else { return nil }

        // Create request with a browser user-agent (Google Fonts serves different formats based on UA)
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let cssContent = String(data: data, encoding: .utf8) else {
                Logger.warning("FontInliner: Failed to fetch CSS from \(cssURL)")
                return nil
            }

            // Parse and inline all font URLs in the CSS
            return await inlineFontURLs(in: cssContent)
        } catch {
            Logger.warning("FontInliner: Error fetching CSS: \(error.localizedDescription)")
            return nil
        }
    }

    /// Replaces all url(...) references in CSS with base64 data URIs.
    private func inlineFontURLs(in css: String) async -> String {
        // Match url(...) patterns for font files
        let urlPattern = #"url\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: urlPattern, options: []) else {
            return css
        }

        let nsCSS = css as NSString
        let matches = regex.matches(in: css, options: [], range: NSRange(location: 0, length: nsCSS.length))

        if matches.isEmpty {
            return css
        }

        var result = css

        // Replace URLs in reverse order to preserve string indices
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2,
                  let urlRange = Range(match.range(at: 1), in: result),
                  let fullRange = Range(match.range, in: result) else {
                continue
            }

            let fontURL = String(result[urlRange]).trimmingCharacters(in: .whitespaces)

            if let dataURI = await fetchFontAsDataURI(fontURL) {
                result.replaceSubrange(fullRange, with: "url(\(dataURI))")
            }
        }

        return result
    }

    /// Fetches a font file and converts it to a base64 data URI.
    private func fetchFontAsDataURI(_ urlString: String) async -> String? {
        // Clean up the URL string (remove quotes if present)
        let cleanURL = urlString.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))

        guard let url = URL(string: cleanURL) else {
            Logger.debug("FontInliner: Invalid font URL: \(urlString)")
            return nil
        }

        // Skip non-http URLs (already data URIs, etc.)
        guard url.scheme == "http" || url.scheme == "https" else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                Logger.debug("FontInliner: Failed to fetch font: \(cleanURL)")
                return nil
            }

            // Determine MIME type from URL extension or response
            let mimeType = detectFontMimeType(url: url, response: httpResponse)

            // Convert to base64 data URI
            let base64 = data.base64EncodedString()
            let dataURI = "data:\(mimeType);base64,\(base64)"

            Logger.debug("FontInliner: Inlined font \(url.lastPathComponent) (\(data.count) bytes)")
            return dataURI
        } catch {
            Logger.debug("FontInliner: Error fetching font \(cleanURL): \(error.localizedDescription)")
            return nil
        }
    }

    /// Detects the MIME type for a font file.
    private func detectFontMimeType(url: URL, response: HTTPURLResponse) -> String {
        // Check Content-Type header first
        if let contentType = response.value(forHTTPHeaderField: "Content-Type"),
           !contentType.isEmpty,
           contentType != "application/octet-stream" {
            return contentType
        }

        // Fall back to extension-based detection
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "woff2":
            return "font/woff2"
        case "woff":
            return "font/woff"
        case "ttf":
            return "font/ttf"
        case "otf":
            return "font/otf"
        case "eot":
            return "application/vnd.ms-fontobject"
        default:
            return "font/ttf"
        }
    }
}
