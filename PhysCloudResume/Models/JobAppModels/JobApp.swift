import Foundation
import SwiftData
import SwiftUI

enum Statuses: String, Codable, CaseIterable {
    case new = "New"
    case inProgress = "In Progress"
    case unsubmitted = "Unsubmitted"
    case submitted = "Submitted"
    case interview = "Interview Pending"
    case closed = "Closed"
    case followUp = "Follow up Required"
    case abandonned = "Abandonned"
    case rejected = "Rejected"
}

@Model class JobApp: Equatable, Identifiable, Decodable, Hashable {
    @Attribute(.unique) var id: UUID = UUID()

    static func == (lhs: JobApp, rhs: JobApp) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    @Relationship(deleteRule: .cascade, inverse: \Resume.jobApp)
    var resumes: [Resume] = []

    @Relationship(deleteRule: .cascade, inverse: \CoverLetter.jobApp)
    var coverLetters: [CoverLetter] = []
    var selectedResId: UUID?
    var selectedCoverId: UUID?

    var selectedRes: Resume? {
        get {
            if let id = selectedResId {
                return resumes.first(where: { $0.id == id })
            } else if resumes.isEmpty {
                return nil
            } else { return resumes.last }
        }
        set {
            selectedResId = newValue?.id
        }
    }

    var selectedCover: CoverLetter? {
        get {
            if let id = selectedCoverId {
                return coverLetters.first(where: { $0.id == id })
            }
            return coverLetters.last
        }
        set {
            selectedCoverId = newValue?.id
        }
    }

    var job_position: String
    var job_location: String
    var company_name: String
    var company_linkedin_id: String = ""
    var job_posting_time: String = ""
    var job_description: String
    var seniority_level: String = ""
    var employment_type: String = ""
    var job_function: String = ""
    var industries: String = ""
    var job_apply_link: String = ""
    var posting_url: String = ""
    var status: Statuses = Statuses.new
    var notes: String = ""

    enum CodingKeys: String, CodingKey {
        case job_position
        case job_location
        case company_name
        case company_linkedin_id
        case job_posting_time
        case job_description
        case seniority_level
        case employment_type
        case job_function
        case industries
        case job_apply_link
        case resumes
        case coverLetters
        case selectedRes
        case status
        case posting_url
    }

    var jobListingString: String {
        var descriptionParts: [String] = []

        descriptionParts.append("Job Position: \(job_position)")
        descriptionParts.append("Job Location: \(job_location)")
        descriptionParts.append("Company Name: \(company_name)")

        if !company_linkedin_id.isEmpty {
            descriptionParts.append("Company LinkedIn ID: \(company_linkedin_id)")
        }

        if !job_posting_time.isEmpty {
            descriptionParts.append("Job Posting Time: \(job_posting_time)")
        }

        if !seniority_level.isEmpty {
            descriptionParts.append("Seniority Level: \(seniority_level)")
        }

        if !employment_type.isEmpty {
            descriptionParts.append("Employment Type: \(employment_type)")
        }

        if !job_function.isEmpty {
            descriptionParts.append("Job Function: \(job_function)")
        }

        if !industries.isEmpty {
            descriptionParts.append("Industries: \(industries)")
        }

        if !job_description.isEmpty {
            descriptionParts.append("Job Description: \(job_description)")
        }

        return descriptionParts.joined(separator: "\n")
    }



    static func pillColor(_ myCase: String) -> Color {
        let myCase = myCase.lowercased()
        switch myCase {
        case "closed": return Color.gray
        case "follow up": return Color.yellow
        case "interview": return Color.pink
        case "submitted": return Color.indigo
        case "unsubmitted": return Color.cyan
        case "in progress": return Color.mint
        case "new": return Color.green
        case "abandonned": return .secondary
        case "rejected": return Color.black
        default: return Color.black
        }
    }

    init(
        job_position: String = "",
        job_location: String = "",
        company_name: String = "",
        company_linkedin_id: String = "",
        job_posting_time: String = "",
        job_description: String = "",
        seniority_level: String = "",
        employment_type: String = "",
        job_function: String = "",
        industries: String = "",
        job_apply_link: String = "",
        posting_url: String = ""
    ) {
        self.job_position = job_position
        self.job_location = job_location
        self.company_name = company_name
        self.company_linkedin_id = company_linkedin_id
        self.job_posting_time = job_posting_time
        self.job_description = job_description
        self.seniority_level = seniority_level
        self.employment_type = employment_type
        self.job_function = job_function
        self.industries = industries
        self.job_apply_link = job_apply_link
        self.posting_url = posting_url
        resumes = []
    }

    var hasAnyRes: Bool { return !resumes.isEmpty }
    func addResume(_ resume: Resume) {
        // Ensure uniqueness
        if !resumes.contains(where: { $0.id == resume.id }) {
            resumes.append(resume)
            selectedRes = resume
            print("JobApp resume added, jobApp.hasAnyResume is \(hasAnyRes ? "true" : "false")")
        } else {
            if resumes.isEmpty {
                print("Uniqueness test fails: resumes array is empty")
            } else {
                for (index, resume) in resumes.enumerated() {
                    print("resume array \(index): \(resume.createdDateString)")
                }
            }
        }

        if selectedRes == nil {
            selectedRes = resume
            print("selected res set to newly added res")
        }
    }

    func resumeDeletePrep(candidate: Resume) {
        if selectedRes == candidate {
            if resumes.count == 1 {
                selectedRes = nil
                print("SelREs nil")
            } else {
                selectedRes = resumes.first(where: { $0.id != candidate.id })
                print("sel res reassigned")
            }
        }
        print("no change to selRes required. It's another object")
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        job_position = try container.decode(String.self, forKey: .job_position)
        job_location = try container.decode(String.self, forKey: .job_location)
        company_name = try container.decode(String.self, forKey: .company_name)
        company_linkedin_id = try container.decodeIfPresent(String.self, forKey: .company_linkedin_id) ?? ""
        job_posting_time = try container.decodeIfPresent(String.self, forKey: .job_posting_time) ?? ""
        job_description = try container.decode(String.self, forKey: .job_description)
        seniority_level = try container.decodeIfPresent(String.self, forKey: .seniority_level) ?? ""
        employment_type = try container.decodeIfPresent(String.self, forKey: .employment_type) ?? ""
        job_function = try container.decodeIfPresent(String.self, forKey: .job_function) ?? ""
        industries = try container.decodeIfPresent(String.self, forKey: .industries) ?? ""
        job_apply_link = try container.decodeIfPresent(String.self, forKey: .job_apply_link) ?? ""
        status = try container.decodeIfPresent(Statuses.self, forKey: .status) ?? .new
        resumes = []
    }

    public func assignPropsFromForm(_ sourceJobAppForm: JobAppForm) {
        job_position = sourceJobAppForm.job_position
        job_location = sourceJobAppForm.job_location
        company_name = sourceJobAppForm.company_name
        company_linkedin_id = sourceJobAppForm.company_linkedin_id
        job_posting_time = sourceJobAppForm.job_posting_time
        job_description = sourceJobAppForm.job_description
        seniority_level = sourceJobAppForm.seniority_level
        employment_type = sourceJobAppForm.employment_type
        job_function = sourceJobAppForm.job_function
        industries = sourceJobAppForm.industries
        job_apply_link = sourceJobAppForm.job_apply_link
        posting_url = sourceJobAppForm.posting_url
    }
}
