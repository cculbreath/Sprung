//
//  IndeedJobScrape.swift
//  Sprung
//
//  Created by Christopher Culbreath on 4/19/25.
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
            // 2. Find the JobPosting JSON‑LD block. Indeed may add whitespace or
            // wrap several JSON‑LD objects in an array, so we parse each script
            // tag instead of relying on a raw substring search.
            let scriptTags = try doc.select("script[type=application/ld+json]")
            func containsJobPostingType(in dict: [String: Any]) -> Bool {
                if let typeStr = dict["@type"] as? String, typeStr.lowercased() == "jobposting" {
                    return true
                }
                if let typeArr = dict["@type"] as? [String] {
                    return typeArr.contains { $0.lowercased() == "jobposting" }
                }
                return false
            }
            func jobPostingDictionary(from json: Any) -> [String: Any]? {
                if let dict = json as? [String: Any], containsJobPostingType(in: dict) {
                    return dict
                }
                if let dictArray = json as? [[String: Any]] {
                    return dictArray.first(where: { containsJobPostingType(in: $0) })
                }
                if let anyArray = json as? [Any] {
                    for element in anyArray {
                        if let dict = element as? [String: Any], containsJobPostingType(in: dict) {
                            return dict
                        }
                    }
                }
                return nil
            }
            var jobDict: [String: Any]?
            outer: for tag in scriptTags.array() {
                var content = try tag.html()
                // Remove HTML comment markers if present.
                content = content.replacingOccurrences(of: "<!--", with: "")
                    .replacingOccurrences(of: "-->", with: "")
                guard let data = content.data(using: .utf8) else { continue }
                if let topObj = try? JSONSerialization.jsonObject(with: data, options: []),
                   let posting = jobPostingDictionary(from: topObj) {
                    jobDict = posting
                    break outer
                }
            }
            guard let jobDict else {
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
                       let info = wrapper["jobInfoModel"] as? [String: Any]
                    {
                        return mapEmbeddedJobInfo(info, url: url, store: jobAppStore)
                    }
                }
                // -------- Fallback Path 2: Mosaic provider script --------
                if let mosaicScript = try? doc.select("script[id^=mosaic-provider-jobsearch-viewjob]").first() {
                    // Use `.html()` to get raw JSON without entity decoding.
                    if let rawJSON = try? mosaicScript.html(),
                       let data = rawJSON.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    {
                        // The hierarchy we care about lives under props.pageProps.jobInfoWrapperModel
                        if let props = obj["props"] as? [String: Any],
                           let pageProps = props["pageProps"] as? [String: Any],
                           let wrapper = pageProps["jobInfoWrapperModel"] as? [String: Any],
                           let info = wrapper["jobInfoModel"] as? [String: Any]
                        {
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
            // Description (HTML in JSON – strip tags quickly).
            if let descriptionHTML = jobDict["description"] as? String {
                // Attempt to remove HTML tags using a tiny helper.
                jobApp.jobDescription = descriptionHTML
                    .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .decodingHTMLEntities()
            }
            // Company
            if let org = jobDict["hiringOrganization"] as? [String: Any],
               let companyName = org["name"] as? String
            {
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
            // 5. Check for duplicates before persisting
            // Check if a job with the same URL already exists
            let existingJobWithURL = jobAppStore.jobApps.first { $0.postingURL == url }
            if let existingJob = existingJobWithURL {
                // Update the existing job with any new information and select it
                jobAppStore.selectedApp = existingJob
                return existingJob
            }
            // Or check if a job with the same position and company already exists
            let existingJob = jobAppStore.jobApps.first {
                $0.jobPosition == jobApp.jobPosition &&
                    $0.companyName == jobApp.companyName
            }
            if let existing = existingJob {
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
            jobApp.jobDescription = description
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .decodingHTMLEntities()
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
        let html: String?
        if let primary = try? await JobApp.fetchHTMLContent(from: urlString) {
            html = primary
        } else if let url = URL(string: urlString),
                  let webHTML = try? await WebViewHTMLFetcher.html(for: url)
        {
            // Fallback: load the same desktop URL in a hidden WKWebView.
            html = webHTML
        } else {
            html = nil
        }
        guard let html else {
            return nil
        }
        return JobApp.parseIndeedJobListing(jobAppStore: jobAppStore, html: html, url: urlString)
    }
}
