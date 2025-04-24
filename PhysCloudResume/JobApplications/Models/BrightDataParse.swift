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
            jobApp.jobPosition = jsonDict["job_title"] as? String ?? ""
            jobApp.jobLocation = jsonDict["job_location"] as? String ?? ""
            jobApp.companyName = jsonDict["company_name"] as? String ?? ""
            jobApp.companyLinkedinId = jsonDict["company_id"] as? String ?? ""
            jobApp.jobPostingTime = jsonDict["job_posted_time"] as? String ?? ""
            jobApp.jobDescription = jsonDict["job_summary"] as? String ?? ""
            jobApp.seniorityLevel = jsonDict["job_seniority_level"] as? String ?? ""
            jobApp.employmentType = jsonDict["job_employment_type"] as? String ?? ""
            jobApp.jobFunction = jsonDict["job_function"] as? String ?? ""
            jobApp.industries = jsonDict["job_industries"] as? String ?? ""
            jobApp.jobApplyLink = jsonDict["apply_link"] as? String ?? ""
            jobApp.postingURL = jsonDict["url"] as? String ?? ""

            // Handle any additional properties or default values
            jobApp.status = .new // or assign based on logic

            // Add jobApp to the store
            jobAppStore.selectedApp = jobAppStore.addJobApp(jobApp)

            return jobApp
        } else {
            return nil
        }
    }
}
