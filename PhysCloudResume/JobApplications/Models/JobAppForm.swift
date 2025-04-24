import SwiftData

@Observable class JobAppForm {
    var jobPosition: String = ""
    var jobLocation: String = ""
    var companyName: String = ""
    var companyLinkedinId: String = ""
    var jobPostingTime: String = ""
    var jobDescription: String = ""
    var seniorityLevel: String = ""
    var employmentType: String = ""
    var jobFunction: String = ""
    var industries: String = ""
    var jobApplyLink: String = ""
    var postingURL: String = ""

    init() {}

    func populateFormFromObj(_ source: JobApp) {
        jobPosition = source.jobPosition
        jobLocation = source.jobLocation
        companyName = source.companyName
        companyLinkedinId = source.companyLinkedinId
        jobPostingTime = source.jobPostingTime
        jobDescription = source.jobDescription
        seniorityLevel = source.seniorityLevel
        employmentType = source.employmentType
        jobFunction = source.jobFunction
        industries = source.industries
        jobApplyLink = source.jobApplyLink
        postingURL = source.postingURL
    }
}
