//
//  AppleJobScrape.swift
//  PhysCloudResume
//
//  Contains only the Apple‐specific HTML → JobApp parser.  The shared HTML
//  downloader lives in UtilityClasses/HTMLFetcher.swift.

import Foundation
import SwiftSoup

extension JobApp {
    /// Parse Apple careers HTML and populate a JobApp. Returns the newly added
    /// instance that is also selected in `jobAppStore`.
    @MainActor
    static func parseAppleJobListing(jobAppStore: JobAppStore, html: String, url: String) {
        do {
            let doc: Document = try SwiftSoup.parse(html)
            let jobApp = JobApp()

            // Title
            if let titleEl = try doc.select("#jdPostingTitle").first() {
                jobApp.jobPosition = try titleEl.text()
            }

            // Location
            if let loc = try doc.select("#job-location-name").first() {
                let locality = try loc.select("span[itemProp=addressLocality]").text()
                let region = try loc.select("span[itemProp=addressRegion]").text()
                let country = try loc.select("span[itemProp=addressCountry]").text()
                jobApp.jobLocation = [locality, region, country]
                    .filter { !$0.isEmpty }.joined(separator: ", ")
            }

            jobApp.companyName = "Apple"

            // Posting time
            if let dateEl = try doc.select("#jobPostDate").first() {
                jobApp.jobPostingTime = try dateEl.text()
            }

            // Description (description + min & preferred qualifications)
            var desc = ""
            if let main = try doc.select("#jd-description").first() {
                desc += try main.text() + "\n\n"
            }
            if let minQ = try doc.select("#jd-minimum-qualifications").first() {
                try desc += "Minimum Qualifications:\n" + (minQ.text()) + "\n\n"
            }
            if let prefQ = try doc.select("#jd-preferred-qualifications").first() {
                try desc += "Preferred Qualifications:\n" + (prefQ.text())
            }
            jobApp.jobDescription = desc.trimmingCharacters(in: .whitespacesAndNewlines)

            // Team / Function
            if let team = try doc.select("#job-team-name").first() {
                jobApp.jobFunction = try team.text()
            }

            jobApp.postingURL = url
            jobApp.status = .new

            jobAppStore.selectedApp = jobAppStore.addJobApp(jobApp)

        } catch let Exception.Error(type, message) {
        } catch {
        }
    }
}
