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

    @AppStorage("scrapingDogApiKey") var scrapingDogApiKey: String = "none"
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
                    if let _ = JobApp.parseProxycurlJobApp(
                        jobAppStore: jobAppStore,
                        jsonData: data,
                        postingUrl: posting_url.absoluteString
                    ) {
                        isPresented = false
                    }
                } else {
                    // Handle error response
                }
            }
        } catch {}

        isLoading = false
    }
}
