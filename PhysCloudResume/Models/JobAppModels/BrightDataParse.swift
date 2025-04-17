import Foundation

extension JobApp {
    @MainActor
    static func parseBrightDataJobApp(jobAppStore: JobAppStore, jsonData: Data) -> JobApp? {
        if let jsonArray = (try? JSONSerialization.jsonObject(with: jsonData, options: [])) as? [[String: Any]],
           let jsonDict = jsonArray.first
        {
            // Create a new JobApp instance
            let jobApp = JobApp()

            // Manually assign attributes
            jobApp.job_position = jsonDict["job_title"] as? String ?? ""
            jobApp.job_location = jsonDict["job_location"] as? String ?? ""
            jobApp.company_name = jsonDict["company_name"] as? String ?? ""
            jobApp.company_linkedin_id = jsonDict["company_id"] as? String ?? ""
            jobApp.job_posting_time = jsonDict["job_posted_time"] as? String ?? ""
            jobApp.job_description = jsonDict["job_summary"] as? String ?? ""
            jobApp.seniority_level = jsonDict["job_seniority_level"] as? String ?? ""
            jobApp.employment_type = jsonDict["job_employment_type"] as? String ?? ""
            jobApp.job_function = jsonDict["job_function"] as? String ?? ""
            jobApp.industries = jsonDict["job_industries"] as? String ?? ""
            jobApp.job_apply_link = jsonDict["apply_link"] as? String ?? ""
            jobApp.posting_url = jsonDict["url"] as? String ?? ""

            // Handle any additional properties or default values
            jobApp.status = .new // or assign based on logic

            // Add jobApp to the store
            jobAppStore.selectedApp = jobAppStore.addJobApp(jobApp)

            return jobApp
        } else {
            print("Failed to parse JSON or JSON structure is unexpected")
            return nil
        }
    }
}
