//
//  NewAppSheetView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/1/24.
//

import Foundation
import SwiftUI

struct NewAppSheetView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Environment(\.dismiss) private var dismiss

    @AppStorage("scrapingDogApiKey") var scrapingDogApiKey: String = "none"
    @AppStorage("brightDataApiKey") var brightDataApiKey: String = "none"
    @AppStorage("proxycurlApiKey") var proxycurlApiKey: String = "none"

    @AppStorage("preferredApi") var preferredApi: apis = .scrapingDog

    @State private var isLoading: Bool = false
    @State private var urlText: String = ""
    @State private var delayed: Bool = false
    @State private var verydelayed: Bool = false
    @State private var showCloudflareChallenge: Bool = false
    @State private var challengeURL: URL? = nil
    @State private var baddomain: Bool = false

    @Binding var isPresented: Bool

    var body: some View {
        VStack {
            if isLoading {
                VStack {
                    ProgressView("Fetching job details...")
                        .progressViewStyle(CircularProgressViewStyle())
                        .padding()
                    if delayed {
                        Text("Fetch results not ready. Trying again in 10s").font(.caption)
                    }
                    if verydelayed {
                        Text("Something suss going on with scraper. Trying again in 200s").font(.caption)
                    }
                    if baddomain {
                        VStack { Text("URL does not is not a supported job listing site").font(.caption).padding()
                            Button("OK") {
                                isLoading = false
                                isPresented = false
                            }
                        }
                    }
                }
            } else {
                Text("Enter LinkedIn Job URL")
                TextField(
                    "https://www.linkedin.com/jobs/view/3951765732", text: $urlText
                )
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()

                HStack {
                    Button("Cancel") {
                        isPresented = false
                    }
                    Spacer()
                    Button("Scrape URL") {
                        Task {
                            await handleNewApp()
                        }
                    }
                }
            }
        }
        .padding()
        .sheet(isPresented: $showCloudflareChallenge) {
            if let challengeURL {
                CloudflareChallengeView(url: challengeURL, isPresented: $showCloudflareChallenge) {
                    // After success retry the import
                    Task {
                        isLoading = true
                        if let urlString = challengeURL.absoluteString as String?,
                           let _ = await JobApp.importFromIndeed(urlString: urlString, jobAppStore: jobAppStore)
                        {
                            isLoading = false
                            isPresented = false
                        } else {
                            isLoading = false
                        }
                    }
                }.defaultSize()
            }
        }
    }

    private func handleNewApp() async {
        if let url = URL(string: urlText) {
            switch url.host {
            case "www.linkedin.com":
                isLoading = true
                if preferredApi == .scrapingDog {
                    if let jobID = url.pathComponents.last {
                        await ScrapingDogfetchLinkedInJobDetails(jobID: jobID, posting_url: url)
                    }
                }
                if preferredApi == .brightData {
                    await BrightDatafetchLinkedInJobDetails(posting_url: url)
                }
                if preferredApi == .proxycurl {
                    await ProxycurlfetchLinkedInJobDetails(posting_url: url)
                }
            case "jobs.apple.com":
                isLoading = true
                Task {
                    do {
                        let htmlContent = try await JobApp.fetchHTMLContent(from: urlText)
                        JobApp.parseAppleJobListing(
                            jobAppStore: jobAppStore, html: htmlContent, url: urlText
                        )
                        if let jobApp = jobAppStore.selectedApp {
                            // Now you can access the extracted data from jobApp
                        }
                        isLoading = false
                        isPresented = false
                    } catch {}
                }
            case "www.indeed.com", "indeed.com":
                isLoading = true
                Task {
                    if let _ = await JobApp.importFromIndeed(urlString: urlText, jobAppStore: jobAppStore) {
                        isLoading = false
                        isPresented = false
                    } else {
                        // likely Cloudflare challenge – show web view
                        isLoading = false
                        if let u = URL(string: urlText) {
                            challengeURL = u
                            showCloudflareChallenge = true
                        }
                    }
                }
            default:
                baddomain = true
            }
            return
        }
    }

    private func ScrapingDogfetchLinkedInJobDetails(jobID: String, posting_url: URL) async {
        let apiKey = scrapingDogApiKey
        let requestURL =
            "https://api.scrapingdog.com/linkedinjobs?api_key=\(apiKey)&job_id=\(jobID)"

        guard let url = URL(string: requestURL) else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode != 200
            {
                // Handle HTTP error (non-200 status code)
                isLoading = false
                return
            }

            let jobDetails = try JSONDecoder().decode([JobApp].self, from: data)
            if let jobDetail = jobDetails.first {
                jobDetail.postingURL = posting_url.absoluteString
                jobAppStore.selectedApp = jobAppStore.addJobApp(jobDetail)
                isPresented = false
            }
        } catch {
            // Handle network or decoding error
        }

        isLoading = false
    }

    private func BrightDatafetchLinkedInJobDetails(posting_url: URL) async {
        let apiKey = brightDataApiKey
        let requestURL_string = "https://api.brightdata.com/datasets/v3/trigger?dataset_id=gd_lpfll7v5hcqtkxl6l"

        guard let requestUrl = URL(string: requestURL_string) else { return }

        // Create the URLRequest
        var request = URLRequest(url: requestUrl)
        request.httpMethod = "POST"

        // Set the headers
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // The job URL you have as a starting point
        let payload = [
            ["url": posting_url.absoluteString],
        ]

        do {
            // Serialize the payload to JSON data
            let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [])
            request.httpBody = jsonData

            // Perform the request
            let (data, response) = try await URLSession.shared.data(for: request)

            // Check the HTTP response status
            guard let httpResponse = response as? HTTPURLResponse else {
                isLoading = false
                isPresented = false

                return
            }

            if httpResponse.statusCode == 200 {
                // Parse the response to get the snapshot_id
                if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
                   let jsonDict = jsonObject as? [String: Any],
                   let snapshotId = jsonDict["snapshot_id"] as? String
                {
                    // Wait for the data to be ready (optional, depending on API behavior)
                    try await Task.sleep(nanoseconds: 5 * 1_000_000_000) // Sleep for 5 seconds

                    // Second Request: Retrieve the snapshot data
                    try await fetchSnapshotData(snapshotId: snapshotId, posting_url: posting_url)

                } else {
                    isLoading = false
                    isPresented = false
                }
            } else {
                // Handle HTTP error
                isLoading = false
                isPresented = false

                if let responseBody = String(data: data, encoding: .utf8) {}
            }
        } catch {
            // Handle errors (e.g., serialization, network errors)
            isLoading = false
            isPresented = false
        }
        isLoading = false
    }

    func fetchSnapshotData(snapshotId: String, posting_url _: URL) async throws {
        // Construct the request URL for the snapshot
        let snapshotURLString = "https://api.brightdata.com/datasets/v3/snapshot/\(snapshotId)?format=json"
        guard let snapshotURL = URL(string: snapshotURLString) else {
            return
        }

        // Create the URLRequest
        var snapshotRequest = URLRequest(url: snapshotURL)
        snapshotRequest.httpMethod = "GET"

        // Set the Authorization header
        snapshotRequest.setValue("Bearer \(brightDataApiKey)", forHTTPHeaderField: "Authorization")

        // Initialize a retry counter
        var retryCount = 0
        let maxRetries = 2

        var snapshotData: Data?
        var httpResponse: HTTPURLResponse?

        repeat {
            // Perform the snapshot request
            let (data, response) = try await URLSession.shared.data(for: snapshotRequest)

            // Check the HTTP response status
            guard let responseHttp = response as? HTTPURLResponse else {
                return
            }
            httpResponse = responseHttp
            snapshotData = data

            if httpResponse?.statusCode == 202 {
                // Data not ready, wait and retry
                if retryCount < 1 {
                    delayed = true
                    try await Task.sleep(nanoseconds: 10 * 1_000_000_000) // Sleep for 10 seconds
                    retryCount += 1
                } else if retryCount < maxRetries {
                    delayed = false
                    verydelayed = true
                    try await Task.sleep(nanoseconds: 200 * 1_000_000_000) // Sleep for 10 seconds
                } else {
                    isLoading = false
                    // Optionally, you can throw an error or handle it as needed
                    return
                }
            } else {
                delayed = false
                // Exit the loop if status code is not 202
                break
            }
        } while retryCount <= maxRetries

        if httpResponse?.statusCode == 200, let data = snapshotData {
            // Process the snapshot data
            if let jobDetail = JobApp.parseBrightDataJobApp(jobAppStore: jobAppStore, jsonData: data) {
            } else {}
            isLoading = false
            isPresented = false

        } else {
            // Handle HTTP error
            isLoading = false
            if let statusCode = httpResponse?.statusCode {
            } else {}
            if let data = snapshotData, let responseBody = String(data: data, encoding: .utf8) {}
        }
    }

    private func ProxycurlfetchLinkedInJobDetails(posting_url: URL) async {
        let apiKey = proxycurlApiKey

        // Build the URL with the job URL as a query parameter
        let baseURL = "https://nubela.co/proxycurl/api/linkedin/job"
        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "url", value: posting_url.absoluteString),
        ]

        guard let requestURL = components?.url else {
            isLoading = false
            return
        }

        // Create request with authorization header
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    // Process successful response
                    if let jobDetail = JobApp.parseProxycurlJobApp(
                        jobAppStore: jobAppStore,
                        jsonData: data,
                        postingUrl: posting_url.absoluteString
                    ) {
                        isPresented = false
                    } else {}
                } else {
                    // Handle error response
                    if let errorText = String(data: data, encoding: .utf8) {}
                }
            }
        } catch {}

        isLoading = false
    }
}
