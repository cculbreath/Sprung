//
//  IndeedJobScrape.swift
//  Sprung
//
//
import Foundation
import SwiftSoup
// MARK: - Indeed HTML → JobApp
extension JobApp {
    /// Attempts to parse an Indeed job‑posting HTML page and create a populated `JobApp`.
    /// The function looks for the Schema.org JSON‑LD ``JobPosting`` block which Indeed
    /// embeds for Google Jobs indexing.  This is far more stable than scraping visible
    /// `<div>` elements whose class names change frequently.
    ///
    /// If the JSON‑LD blob cannot be found or decoded the method returns `nil`.
    /// On success the new `JobApp` is inserted into `jobAppStore` and returned.
    @MainActor
    static func parseIndeedJobListing(
        jobAppStore: JobAppStore,
        html: String,
        url: String
    ) -> JobApp? {
        do {
            // 1. Parse the HTML.
            let doc: Document = try SwiftSoup.parse(html)
            // 2. Find the JobPosting JSON‑LD block. Indeed embeds it for Google
            // Jobs indexing; several JSON‑LD objects may be present and may be
            // wrapped in HTML comments, so decode every ld+json script.
            let jsonLDObjects = ScriptJSONExtractor.objects(
                in: html,
                cssSelector: "script[type=application/ld+json]",
                stripHTMLComments: true
            )
            guard let jobDict = ScriptJSONExtractor.firstJSONLD(ofType: "JobPosting", among: jsonLDObjects) else {
                // Dump HTML for debugging so the user can provide the file.
                if UserDefaults.standard.bool(forKey: "saveDebugPrompts") {
                    DebugFileWriter.write(html, prefix: "IndeedNoJSONLD")
                }
                // -------- Fallback Path 1: Legacy "EmbeddedData" script --------
                if let embedded = try? doc.select("#jobsearch-Viewjob-EmbeddedData").first() {
                    if let rawJSON = try? embedded.text(),
                       let data = rawJSON.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let wrapper = obj["jobInfoWrapperModel"] as? [String: Any],
                       let info = wrapper["jobInfoModel"] as? [String: Any] {
                        return mapEmbeddedJobInfo(info, url: url, store: jobAppStore)
                    }
                }
                // -------- Fallback Path 2: Mosaic provider script --------
                if let mosaicScript = try? doc.select("script[id^=mosaic-provider-jobsearch-viewjob]").first() {
                    // Use `.html()` to get raw JSON without entity decoding.
                    if let rawJSON = try? mosaicScript.html(),
                       let data = rawJSON.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        // The hierarchy we care about lives under props.pageProps.jobInfoWrapperModel
                        if let props = obj["props"] as? [String: Any],
                           let pageProps = props["pageProps"] as? [String: Any],
                           let wrapper = pageProps["jobInfoWrapperModel"] as? [String: Any],
                           let info = wrapper["jobInfoModel"] as? [String: Any] {
                            return mapEmbeddedJobInfo(info, url: url, store: jobAppStore)
                        }
                    }
                }
                return nil
            }
            // 4. Map JSON → JobApp
            let jobApp = JobApp()
            // Title
            if let title = jobDict["title"] as? String {
                jobApp.jobPosition = title.decodingHTMLEntities()
            }
            // Description (HTML in JSON – strip tags, preserving block structure).
            if let descriptionHTML = jobDict["description"] as? String {
                jobApp.jobDescription = stripHTMLPreservingBlocks(descriptionHTML)
            }
            // Company
            if let org = jobDict["hiringOrganization"] as? [String: Any],
               let companyName = org["name"] as? String {
                jobApp.companyName = companyName.decodingHTMLEntities()
            }
            // Employment type
            if let employmentType = jobDict["employmentType"] as? String {
                jobApp.employmentType = employmentType
            }
            // Date posted
            if let datePosted = jobDict["datePosted"] as? String {
                jobApp.jobPostingTime = datePosted
            }
            // Location – the JobPosting schema nests Address inside JobLocation.
            if let jobLocation = jobDict["jobLocation"] {
                // jobLocation can be an array or a single dict.
                func extractAddress(from loc: Any) -> String? {
                    guard let locDict = loc as? [String: Any],
                          let addr = locDict["address"] as? [String: Any] else { return nil }
                    let locality = addr["addressLocality"] as? String ?? ""
                    let region = addr["addressRegion"] as? String ?? ""
                    let country = addr["addressCountry"] as? String ?? ""
                    // Assemble non‑empty parts.
                    let parts = [locality, region, country].filter { !$0.isEmpty }
                    return parts.isEmpty ? nil : parts.joined(separator: ", ")
                }
                var locationString: String?
                if let locArray = jobLocation as? [[String: Any]] {
                    // Prefer the first location.
                    if let first = locArray.first {
                        locationString = extractAddress(from: first)
                    }
                } else {
                    locationString = extractAddress(from: jobLocation)
                }
                if let locationString {
                    jobApp.jobLocation = locationString.decodingHTMLEntities()
                }
            }
            // Apply URL (not always present).
            if let applyLink = jobDict["url"] as? String {
                jobApp.jobApplyLink = applyLink
            }
            // Industries are not exposed directly; attempt to derive from category.
            if let industry = jobDict["industry"] as? String {
                jobApp.industries = industry
            }
            // Store the original Indeed posting link.
            jobApp.postingURL = url
            // Default status.
            jobApp.status = .new
            // 5. Check for duplicates before persisting (URL match, then title+company).
            if let existing = jobAppStore.findDuplicateJobApp(
                url: url,
                title: jobApp.jobPosition,
                company: jobApp.companyName
            ) {
                // Update the existing job with any new information and select it
                jobAppStore.selectedApp = existing
                return existing
            }
            // No duplicate found, persist in the store and return
            jobAppStore.selectedApp = jobAppStore.addJobApp(jobApp)
            return jobApp
        } catch {
            return nil
        }
    }
    // MARK: - HTML Stripping

    /// Strip HTML tags from a job description while preserving its block
    /// structure: block-level tags (paragraphs, list items, headings, rows, …)
    /// become newlines so the result is readable line-oriented text instead of
    /// one giant line; inline tags become spaces.
    private static func stripHTMLPreservingBlocks(_ html: String) -> String {
        let blockTagPattern = "</?(?:p|br|div|li|ul|ol|h[1-6]|tr|table|thead|tbody|section|article|header|footer|blockquote|pre|dl|dt|dd)\\b[^>]*>"
        var text = html.replacingOccurrences(
            of: blockTagPattern,
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        // Collapse horizontal whitespace runs, tidy space around newlines, and
        // cap blank runs at one empty line.
        text = text.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: " ?\\n ?", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .decodingHTMLEntities()
    }

    // MARK: - EmbeddedData mapping fallback
    @MainActor
    private static func mapEmbeddedJobInfo(_ info: [String: Any], url: String, store: JobAppStore) -> JobApp? {
        let jobApp = JobApp()
        if let title = info["jobTitle"] as? String {
            jobApp.jobPosition = title.decodingHTMLEntities()
        }
        if let company = info["companyName"] as? String {
            jobApp.companyName = company.decodingHTMLEntities()
        }
        if let location = info["formattedLocation"] as? String {
            jobApp.jobLocation = location.decodingHTMLEntities()
        }
        if let description = info["sanitizedJobDescription"] as? String {
            jobApp.jobDescription = stripHTMLPreservingBlocks(description)
        }
        jobApp.postingURL = url
        jobApp.status = .new
        store.selectedApp = store.addJobApp(jobApp)
        return jobApp
    }
    /// Convenience wrapper – fetches the Indeed page, parses it, and returns the resulting `JobApp`.
    @discardableResult
    @MainActor
    static func importFromIndeed(
        urlString: String,
        jobAppStore: JobAppStore
    ) async -> JobApp? {
        guard let url = URL(string: urlString) else {
            Logger.error("🚨 [IndeedJobScrape] Invalid URL: \(urlString)")
            return nil
        }

        // Use WebResourceService which handles URLSession + WebView fallback automatically
        guard let html = try? await WebResourceService.fetchHTML(from: url) else {
            Logger.error("🚨 [IndeedJobScrape] Failed to fetch HTML from: \(urlString)")
            return nil
        }

        return JobApp.parseIndeedJobListing(jobAppStore: jobAppStore, html: html, url: urlString)
    }
}
