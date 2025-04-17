//
//  AppleJobScrape.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/27/24.
//
import Foundation
import SwiftSoup

extension JobApp {
    static func fetchHTMLContent(from urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        // Configure the URLSession to mimic a browser request
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        // Check for HTTP response errors
        if let httpResponse = response as? HTTPURLResponse, !(200 ... 299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }

        // Convert data to string
        if let htmlContent = String(data: data, encoding: .utf8) {
            return htmlContent
        } else {
            throw URLError(.cannotDecodeContentData)
        }
    }

    @MainActor
    static func parseAppleJobListing(jobAppStore: JobAppStore, html: String, url: String) {
        do {
            let doc: Document = try SwiftSoup.parse(html)
            let jobApp = JobApp()
            // Extract job position
            if let jobTitleElement = try doc.select("#jdPostingTitle").first() {
                jobApp.job_position = try jobTitleElement.text()
            }

            // Extract job location
            if let jobLocationElement = try doc.select("#job-location-name").first() {
                let locality = try jobLocationElement.select("span[itemProp=addressLocality]").text()
                let region = try jobLocationElement.select("span[itemProp=addressRegion]").text()
                let country = try jobLocationElement.select("span[itemProp=addressCountry]").text()
                jobApp.job_location = "\(locality), \(region), \(country)"
            }

            // Set company name
            jobApp.company_name = "Apple"

            // Extract job posting time
            if let jobPostDateElement = try doc.select("#jobPostDate").first() {
                jobApp.job_posting_time = try jobPostDateElement.text()
            }

            // Extract job description, combining description, minimum qualifications, and preferred qualifications
            var descriptionText = ""

            if let descriptionElement = try doc.select("#jd-description").first() {
                descriptionText += try descriptionElement.text() + "\n\n"
            }
            if let minQualificationsElement = try doc.select("#jd-minimum-qualifications").first() {
                descriptionText += "Minimum Qualifications:\n"
                descriptionText += try minQualificationsElement.text() + "\n\n"
            }
            if let prefQualificationsElement = try doc.select("#jd-preferred-qualifications").first() {
                descriptionText += "Preferred Qualifications:\n"
                descriptionText += try prefQualificationsElement.text() + "\n"
            }
            jobApp.job_description = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)

            // Extract job function (department or division)
            if let jobTeamElement = try doc.select("#job-team-name").first() {
                jobApp.job_function = try jobTeamElement.text()
            }
            jobApp.posting_url = url

            jobAppStore.selectedApp = jobAppStore.addJobApp(jobApp)
        } catch let Exception.Error(type, message) {
            print("Type: \(type), Message: \(message)")
        } catch {
            print("Unexpected error: \(error).")
        }
    }
}
