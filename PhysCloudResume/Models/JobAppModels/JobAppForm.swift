import SwiftData

@Observable class JobAppForm {
    var job_position: String = ""
    var job_location: String = ""
    var company_name: String = ""
    var company_linkedin_id: String = ""
    var job_posting_time: String = ""
    var job_description: String = ""
    var seniority_level: String = ""
    var employment_type: String = ""
    var job_function: String = ""
    var industries: String = ""
    var job_apply_link: String = ""
    var posting_url: String = ""

    init() {}

    func populateFormFromObj(_ source: JobApp) {
        job_position = source.job_position
        job_location = source.job_location
        company_name = source.company_name
        company_linkedin_id = source.company_linkedin_id
        job_posting_time = source.job_posting_time
        job_description = source.job_description
        seniority_level = source.seniority_level
        employment_type = source.employment_type
        job_function = source.job_function
        industries = source.industries
        job_apply_link = source.job_apply_link
        posting_url = source.posting_url
    }
}
