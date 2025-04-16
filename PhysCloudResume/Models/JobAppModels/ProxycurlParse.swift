import Foundation

extension JobApp {
    static func parseProxycurlJobApp(jobAppStore: JobAppStore, jsonData: Data, postingUrl: String) -> JobApp? {
        do {
            // Try to decode the JSON response
            let decoder = JSONDecoder()
            let proxycurlJob = try decoder.decode(ProxycurlJob.self, from: jsonData)
            
            // Create a new JobApp instance
            let jobApp = JobApp()
            
            // Map the Proxycurl response fields to JobApp properties
            jobApp.job_position = proxycurlJob.title
            
            // Construct location string
            var locationParts: [String] = []
            if let city = proxycurlJob.location.city, !city.isEmpty {
                locationParts.append(city)
            }
            if let region = proxycurlJob.location.region, !region.isEmpty {
                locationParts.append(region)
            }
            if let country = proxycurlJob.location.country, !country.isEmpty {
                locationParts.append(country)
            }
            jobApp.job_location = locationParts.joined(separator: ", ")
            
            // Company information
            jobApp.company_name = proxycurlJob.company.name
            
            // LinkedIn ID (derived from the internal ID)
            jobApp.company_linkedin_id = proxycurlJob.linkedin_internal_id
            
            // Job description - clean up the title
            var cleanedDescription = proxycurlJob.job_description
            
            // Remove "**Job Description**" or similar titles with asterisks
            let titlePattern = #"\*\*Job Description\*\*[\s\n]*"#
            if let regex = try? NSRegularExpression(pattern: titlePattern, options: [.caseInsensitive]) {
                cleanedDescription = regex.stringByReplacingMatches(
                    in: cleanedDescription,
                    options: [],
                    range: NSRange(location: 0, length: cleanedDescription.count),
                    withTemplate: ""
                )
            }
            
            jobApp.job_description = cleanedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Seniority level
            jobApp.seniority_level = proxycurlJob.seniority_level
            
            // Employment type
            jobApp.employment_type = proxycurlJob.employment_type
            
            // Job function (joining multiple functions if available)
            jobApp.job_function = proxycurlJob.job_functions.joined(separator: ", ")
            
            // Industries (joining multiple industries if available)
            jobApp.industries = proxycurlJob.industry.joined(separator: ", ")
            
            // Apply link
            jobApp.job_apply_link = proxycurlJob.apply_url
            
            // Original posting URL
            jobApp.posting_url = postingUrl
            
            // Set default status for new job application
            jobApp.status = .new
            
            // Add jobApp to the store
            jobAppStore.selectedApp = jobAppStore.addJobApp(jobApp)
            
            return jobApp
        } catch {
            print("Failed to parse Proxycurl JSON: \(error)")
            return nil
        }
    }
}

// Struct to match the Proxycurl JSON response format
struct ProxycurlJob: Codable {
    let linkedin_internal_id: String
    let job_description: String
    let apply_url: String
    let title: String
    let location: JobLocation
    let company: JobCompany
    let seniority_level: String
    let industry: [String]
    let employment_type: String
    let job_functions: [String]
    let total_applicants: Int?
}

struct JobLocation: Codable {
    let country: String?
    let region: String?
    let city: String?
    let postal_code: String?
    let latitude: Double?
    let longitude: Double?
    let street: String?
}

struct JobCompany: Codable {
    let name: String
    let url: String
    let logo: String
}