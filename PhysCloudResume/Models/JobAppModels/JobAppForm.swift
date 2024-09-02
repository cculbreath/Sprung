import SwiftData

@Model class JobAppForm {
    var job_position: String = ""
    var job_location: String = ""
    var company_name: String = ""
    var company_linkedin_id:String = ""
    var job_posting_time: String = ""
    var job_description: String = ""
    var seniority_level: String = ""
    var employment_type: String = ""
    var job_function: String = ""
    var industries: String = ""
    var job_apply_link: String = ""

    init() {
    }
    func populateFormFromObj(_ source: JobApp) {
        self.job_position = source.job_position
        self.job_location = source.job_location
        self.company_name = source.company_name
        self.company_linkedin_id = source.company_linkedin_id
        self.job_posting_time = source.job_posting_time
        self.job_description = source.job_description
        self.seniority_level = source.seniority_level
        self.employment_type = source.employment_type
        self.job_function = source.job_function
        self.industries = source.industries
        self.job_apply_link = source.job_apply_link
    }
}
