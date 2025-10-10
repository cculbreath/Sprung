import Foundation
import SwiftData
import SwiftUI

/// Script to import JobApps using the same code path as the UI
/// This mimics the working UI flow that successfully persists JobApps
@MainActor
class ImportJobAppsScript {
    
    /// Import JobApps from exported JSON using the UI's working code path
    static func importUsingUIPath(from fileURL: URL, jobAppStore: JobAppStore) async throws -> Int {
        Logger.debug("🚀 Starting import using UI code path...")
        
        // Read the JSON file
        let data = try Data(contentsOf: fileURL)
        let json = try JSONSerialization.jsonObject(with: data)
        
        // Handle both regular and SQL export formats
        var jobAppsToImport: [[String: Any]] = []
        
        if let exportData = json as? [String: Any] {
            // SQL export format
            if let jobAppsData = exportData["jobApps"] as? [[String: Any]] {
                Logger.debug("📂 Detected SQL export format with \(jobAppsData.count) JobApps")
                jobAppsToImport = jobAppsData
            }
            // Regular export format
            else if let jobApps = exportData["jobApplications"] as? [[String: Any]] {
                Logger.debug("📂 Detected regular export format with \(jobApps.count) JobApps")
                jobAppsToImport = jobApps
            }
        }
        
        guard !jobAppsToImport.isEmpty else {
            Logger.debug("⚠️ No JobApps found in export file")
            return 0
        }
        
        var importedCount = 0
        
        for jobAppData in jobAppsToImport {
            do {
                // Create JobApp using the same initialization as UI
                let jobApp = createJobAppFromData(jobAppData)
                
                // Use the exact same method the UI uses to add JobApps
                let addedJobApp = jobAppStore.addJobApp(jobApp)
                
                if addedJobApp != nil {
                    importedCount += 1
                    Logger.debug("✅ Imported: \(jobApp.companyName) - \(jobApp.jobPosition)")
                } else {
                    Logger.debug("⚠️ Failed to add: \(jobApp.companyName) - \(jobApp.jobPosition)")
                }
                
                // Add small delay to avoid overwhelming the system
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                
            } catch {
                Logger.error("x Error importing JobApp: \(error)")
            }
        }
        
        Logger.debug("✅ Successfully imported \(importedCount) JobApps using UI path")
        
        // Refresh the store to ensure UI updates
        jobAppStore.refreshJobApps()
        
        return importedCount
    }
    
    /// Create JobApp from export data, handling both regular and SQL formats
    private static func createJobAppFromData(_ data: [String: Any]) -> JobApp {
        // Handle SQL export format (fields prefixed with Z)
        if data.keys.contains(where: { $0.hasPrefix("Z") }) {
            return createJobAppFromSQLData(data)
        } else {
            // Regular export format
            return createJobAppFromRegularData(data)
        }
    }
    
    /// Create JobApp from SQL export data
    private static func createJobAppFromSQLData(_ data: [String: Any]) -> JobApp {
        let jobApp = JobApp()
        
        // Map SQL fields to JobApp properties
        jobApp.companyName = (data["ZCOMPANYNAME"] as? String) ?? ""
        jobApp.jobPosition = (data["ZJOBPOSITION"] as? String) ?? ""
        jobApp.postingURL = (data["ZJOBURL"] as? String) ?? ""
        jobApp.jobApplyLink = (data["ZJOBAPPLYLINK"] as? String) ?? ""
        jobApp.jobDescription = (data["ZJOBDESCRIPTION"] as? String) ?? ""
        jobApp.jobLocation = (data["ZJOBLOCATION"] as? String) ?? ""
        jobApp.notes = (data["ZNOTES"] as? String) ?? ""
        
        // Map status string to enum
        if let statusString = data["ZJOBSTATUS"] as? String {
            jobApp.status = Statuses(rawValue: statusString) ?? .new
        }
        
        // Map additional fields to existing properties
        jobApp.seniorityLevel = (data["ZSENIORITYLEVEL"] as? String) ?? ""
        jobApp.employmentType = (data["ZEMPLOYMENTTYPE"] as? String) ?? ""
        jobApp.jobFunction = (data["ZJOBFUNCTION"] as? String) ?? ""
        jobApp.industries = (data["ZINDUSTRIES"] as? String) ?? ""
        jobApp.companyLinkedinId = (data["ZCOMPANYLINKEDINID"] as? String) ?? ""
        jobApp.jobPostingTime = (data["ZJOBPOSTINGTIME"] as? String) ?? ""
        
        return jobApp
    }
    
    /// Create JobApp from regular export data
    private static func createJobAppFromRegularData(_ data: [String: Any]) -> JobApp {
        let jobApp = JobApp()
        
        jobApp.companyName = (data["companyName"] as? String) ?? ""
        jobApp.jobPosition = (data["jobPosition"] as? String) ?? ""
        jobApp.postingURL = (data["jobURL"] as? String) ?? (data["postingURL"] as? String) ?? ""
        jobApp.jobApplyLink = (data["jobApplyLink"] as? String) ?? ""
        jobApp.jobDescription = (data["jobDescription"] as? String) ?? ""
        jobApp.jobLocation = (data["jobLocation"] as? String) ?? ""
        jobApp.notes = (data["notes"] as? String) ?? ""
        
        // Map status string to enum
        if let statusString = data["jobStatus"] as? String {
            jobApp.status = Statuses(rawValue: statusString) ?? .new
        }
        
        // Map additional fields
        jobApp.seniorityLevel = (data["seniorityLevel"] as? String) ?? ""
        jobApp.employmentType = (data["employmentType"] as? String) ?? ""
        jobApp.jobFunction = (data["jobFunction"] as? String) ?? ""
        jobApp.industries = (data["industries"] as? String) ?? ""
        jobApp.companyLinkedinId = (data["companyLinkedinId"] as? String) ?? ""
        jobApp.jobPostingTime = (data["jobPostingTime"] as? String) ?? ""
        
        return jobApp
    }
    
    /// Import that attempts to fetch fresh data from URLs using UI code paths
    @MainActor
    static func quickImportByURL(from fileURL: URL, jobAppStore: JobAppStore) async throws -> Int {
        Logger.debug("⚡ Import with fresh data fetch...")
        
        let data = try Data(contentsOf: fileURL)
        let json = try JSONSerialization.jsonObject(with: data)
        
        guard let exportData = json as? [String: Any],
              let jobAppsData = exportData["jobApps"] as? [[String: Any]] else {
            throw NSError(domain: "ImportJobAppsScript", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid export format"])
        }
        
        var importedCount = 0
        var skippedCount = 0
        
        let scrapingDogKey = UserDefaults.standard.string(forKey: "scrapingDogApiKey") ?? "none"
        
        for jobData in jobAppsData {
            // Get URL
            guard let postingURL = jobData["ZPOSTINGURL"] as? String,
                  let url = URL(string: postingURL) else {
                Logger.debug("⚠️ Skipping job with no valid URL")
                skippedCount += 1
                continue
            }
            
            // Get status from export
            let statusString = jobData["ZJOBSTATUS"] as? String ?? "new"
            let status = Statuses(rawValue: statusString) ?? .new
            
            let companyName = (jobData["ZCOMPANYNAME"] as? String) ?? "Unknown"
            let position = (jobData["ZJOBPOSITION"] as? String) ?? "Unknown"
            
            Logger.debug("📥 Processing: \(companyName) - \(position)")
            
            var importedJobApp: JobApp? = nil
            
            // Handle different URL types
            switch url.host {
            case "www.linkedin.com", "linkedin.com":
                if scrapingDogKey != "none" {
                    importedJobApp = await fetchLinkedInWithScrapingDog(
                        url: url,
                        jobAppStore: jobAppStore,
                        apiKey: scrapingDogKey
                    )
                    
                    if importedJobApp == nil {
                        Logger.debug("⚠️ LinkedIn job no longer available (ScrapingDog returned no data)")
                        skippedCount += 1
                        continue
                    }
                } else {
                    importedJobApp = createBasicJobApp(from: jobData, jobAppStore: jobAppStore)
                }
                
            case "www.indeed.com", "indeed.com":
                // Try Indeed import
                importedJobApp = await JobApp.importFromIndeed(
                    urlString: postingURL,
                    jobAppStore: jobAppStore
                )
                
                if importedJobApp == nil {
                    Logger.debug("⚠️ Indeed job no longer available or blocked")
                    skippedCount += 1
                    continue // Skip this job entirely
                }
                
            case "jobs.apple.com":
                // Try Apple import
                do {
                    let htmlContent = try await JobApp.fetchHTMLContent(from: postingURL)
                    await MainActor.run {
                        JobApp.parseAppleJobListing(
                            jobAppStore: jobAppStore,
                            html: htmlContent,
                            url: postingURL
                        )
                    }
                    
                    // Apple parser adds directly to store, find the job we just added
                    if let lastJob = jobAppStore.jobApps.last,
                       lastJob.postingURL == postingURL {
                        importedJobApp = lastJob
                    }
                } catch {
                    Logger.debug("⚠️ Apple job no longer available: \(error)")
                    skippedCount += 1
                    continue // Skip this job entirely
                }
                
            default:
                // For other sites, create basic entry with all data
                importedJobApp = createBasicJobApp(from: jobData, jobAppStore: jobAppStore)
            }
            
            // Set the status if we successfully imported
            if let imported = importedJobApp {
                imported.status = status
                importedCount += 1
                Logger.debug("✅ Imported: \(imported.companyName) - \(imported.jobPosition) [Status: \(status.rawValue)]")
            }
            
            // Delay to avoid rate limiting
            try await Task.sleep(nanoseconds: 500_000_000) // 500ms delay for API calls
        }
        
        Logger.debug("⚡ Import complete: \(importedCount) imported, \(skippedCount) skipped (no longer available)")
        jobAppStore.refreshJobApps()
        
        return importedCount
    }
    
    /// Fetch LinkedIn job details using ScrapingDog API
    @MainActor
    private static func fetchLinkedInWithScrapingDog(url: URL, jobAppStore: JobAppStore, apiKey: String) async -> JobApp? {
        guard let jobId = extractLinkedInJobId(from: url) else {
            Logger.debug("x Unable to parse job ID from LinkedIn URL: \(url.absoluteString)")
            return nil
        }

        guard let requestURL = URL(string: "https://api.scrapingdog.com/linkedinjobs?api_key=\(apiKey)&job_id=\(jobId)") else {
            return nil
        }

        do {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 60
            config.timeoutIntervalForResource = 60
            let session = URLSession(configuration: config)

            let (data, response) = try await session.data(from: requestURL)

            if let httpResponse = response as? HTTPURLResponse {
                guard httpResponse.statusCode == 200 else {
                    Logger.debug("x ScrapingDog error: HTTP \(httpResponse.statusCode)")
                    return nil
                }
            }

            let jobDetails = try JSONDecoder().decode([JobApp].self, from: data)
            if let jobDetail = jobDetails.first {
                jobDetail.postingURL = url.absoluteString
                return jobAppStore.addJobApp(jobDetail)
            }
        } catch {
            Logger.debug("x ScrapingDog request failed: \(error)")
        }
        
        return nil
    }

    private static func extractLinkedInJobId(from url: URL) -> String? {
        let pathComponents = url.pathComponents.reversed()
        for component in pathComponents {
            guard component != "view", !component.isEmpty else { continue }
            if component.allSatisfy(\.isNumber) {
                return component
            }
        }
        return nil
    }
    
    /// Create basic JobApp from export data
    private static func createBasicJobApp(from jobData: [String: Any], jobAppStore: JobAppStore) -> JobApp? {
        let jobApp = JobApp()
        
        // Set all available data from export
        jobApp.postingURL = (jobData["ZPOSTINGURL"] as? String) ?? ""
        jobApp.companyName = (jobData["ZCOMPANYNAME"] as? String) ?? ""
        jobApp.jobPosition = (jobData["ZJOBPOSITION"] as? String) ?? ""
        jobApp.jobLocation = (jobData["ZJOBLOCATION"] as? String) ?? ""
        jobApp.jobDescription = (jobData["ZJOBDESCRIPTION"] as? String) ?? ""
        jobApp.employmentType = (jobData["ZEMPLOYMENTTYPE"] as? String) ?? ""
        jobApp.seniorityLevel = (jobData["ZSENIORITYLEVEL"] as? String) ?? ""
        jobApp.jobFunction = (jobData["ZJOBFUNCTION"] as? String) ?? ""
        jobApp.industries = (jobData["ZINDUSTRIES"] as? String) ?? ""
        jobApp.companyLinkedinId = (jobData["ZCOMPANYLINKEDINID"] as? String) ?? ""
        jobApp.jobApplyLink = (jobData["ZJOBAPPLYLINK"] as? String) ?? ""
        jobApp.notes = (jobData["ZNOTES"] as? String) ?? ""
        jobApp.jobPostingTime = (jobData["ZJOBPOSTINGTIME"] as? String) ?? ""
        
        return jobAppStore.addJobApp(jobApp)
    }
}
