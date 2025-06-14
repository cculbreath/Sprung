//
//  AppleJobScrape.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 1/31/25.
//

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

            // Try to parse from JSON data first (more reliable)
            if html.contains("window.__staticRouterHydrationData") {
                let jsonPattern = "window\\.__staticRouterHydrationData = JSON\\.parse\\(\"(.*)\"\\);"
                if let regex = try? NSRegularExpression(pattern: jsonPattern, options: []),
                   let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
                   let jsonRange = Range(match.range(at: 1), in: html) {
                    let escapedJson = String(html[jsonRange])
                    // Unescape the JSON string
                    let unescapedJson = escapedJson
                        .replacingOccurrences(of: "\\\"", with: "\"")
                        .replacingOccurrences(of: "\\\\", with: "\\")
                    
                    if let jsonData = unescapedJson.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                       let loaderData = json["loaderData"] as? [String: Any],
                       let detailsData = loaderData["routes/external.jobdetails.$positionId"] as? [String: Any] {
                        
                        // Extract data from JSON
                        jobApp.jobPosition = (detailsData["postingTitle"] as? String ?? "").decodingHTMLEntities()
                        
                        if let localeLocation = detailsData["localeLocation"] as? [[String: Any]],
                           let firstLocation = localeLocation.first {
                            let city = firstLocation["city"] as? String ?? ""
                            let state = firstLocation["stateProvince"] as? String ?? ""
                            let country = firstLocation["countryName"] as? String ?? ""
                            jobApp.jobLocation = [city, state, country]
                                .filter { !$0.isEmpty }
                                .map { $0.decodingHTMLEntities() }
                                .joined(separator: ", ")
                        }
                        
                        jobApp.companyName = "Apple"
                        jobApp.jobPostingTime = detailsData["postingDate"] as? String ?? ""
                        
                        // Build description from various fields
                        var desc = ""
                        if let summary = detailsData["descriptionOfRole"] as? String {
                            desc += summary + "\n\n"
                        }
                        if let minQual = detailsData["minimumQualifications"] as? String {
                            desc += "Minimum Qualifications:\n" + minQual + "\n\n"
                        }
                        if let prefQual = detailsData["preferredQualifications"] as? String {
                            desc += "Preferred Qualifications:\n" + prefQual
                        }
                        jobApp.jobDescription = desc.trimmingCharacters(in: .whitespacesAndNewlines).decodingHTMLEntities()
                        
                        if let location = detailsData["location"] as? [String: Any],
                           let teams = location["teams"] as? [[String: Any]],
                           let firstTeam = teams.first {
                            jobApp.jobFunction = (firstTeam["name"] as? String ?? "").decodingHTMLEntities()
                        }
                        
                        jobApp.postingURL = url
                        jobApp.status = .new
                        jobAppStore.selectedApp = jobAppStore.addJobApp(jobApp)
                        return
                    }
                }
            }
            
            // Fallback to HTML parsing with new selectors
            // Title
            if let titleEl = try doc.select("#jobdetails-postingtitle").first() {
                jobApp.jobPosition = try titleEl.text().decodingHTMLEntities()
            }

            // Location
            if let locEl = try doc.select("#jobdetails-joblocation").first() {
                jobApp.jobLocation = try locEl.text().decodingHTMLEntities()
            }

            jobApp.companyName = "Apple"

            // Posting time
            if let dateEl = try doc.select("#jobdetails-jobpostdate").first() {
                jobApp.jobPostingTime = try dateEl.text()
            }

            // Description (summary + description + min & preferred qualifications)
            var desc = ""
            
            // Summary
            if let summaryEl = try doc.select("#jobdetails-jobdetails-jobsummary-content-row").first() {
                desc += try summaryEl.text() + "\n\n"
            }
            
            // Main description
            if let mainEl = try doc.select("#jobdetails-jobdetails-jobdescription-content-row").first() {
                desc += try mainEl.text() + "\n\n"
            }
            
            // Minimum qualifications
            if let minQEl = try doc.select("#jobdetails-jobdetails-minimumqualifications-content-row").first() {
                desc += "Minimum Qualifications:\n" + (try minQEl.text()) + "\n\n"
            }
            
            // Preferred qualifications
            if let prefQEl = try doc.select("#jobdetails-jobdetails-preferredqualifications-content-row").first() {
                desc += "Preferred Qualifications:\n" + (try prefQEl.text())
            }
            
            jobApp.jobDescription = desc.trimmingCharacters(in: .whitespacesAndNewlines).decodingHTMLEntities()

            // Team / Function
            if let teamEl = try doc.select("#jobdetails-teamname").first() {
                jobApp.jobFunction = try teamEl.text().decodingHTMLEntities()
            }

            jobApp.postingURL = url
            jobApp.status = .new

            jobAppStore.selectedApp = jobAppStore.addJobApp(jobApp)

        } catch {}
    }
}
