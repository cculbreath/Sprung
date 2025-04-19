import Foundation
import SwiftData

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

    @Attribute(originalName: "job_position")
    var jobPosition: String
    @Attribute(originalName: "job_location")
    var jobLocation: String
    @Attribute(originalName: "company_name")
    var companyName: String
    @Attribute(originalName: "company_linkedin_id")
    var companyLinkedinId: String = ""
    @Attribute(originalName: "job_posting_time")
    var jobPostingTime: String = ""
    @Attribute(originalName: "job_description")
    var jobDescription: String
    @Attribute(originalName: "seniority_level")
    var seniorityLevel: String = ""
    @Attribute(originalName: "employment_type")
    var employmentType: String = ""
    @Attribute(originalName: "job_function")
    var jobFunction: String = ""
    // 'industries' key unchanged
    var industries: String = ""
    @Attribute(originalName: "job_apply_link")
    var jobApplyLink: String = ""
    @Attribute(originalName: "posting_url")
    var postingURL: String = ""
    var status: Statuses = Statuses.new
    var notes: String = ""

    enum CodingKeys: String, CodingKey {
        case jobPosition = "job_position"
        case jobLocation = "job_location"
        case companyName = "company_name"
        case companyLinkedinId = "company_linkedin_id"
        case jobPostingTime = "job_posting_time"
        case jobDescription = "job_description"
        case seniorityLevel = "seniority_level"
        case employmentType = "employment_type"
        case jobFunction = "job_function"
        case industries
        case jobApplyLink = "job_apply_link"
        case resumes
        case coverLetters
        case selectedRes
        case status
        case postingURL = "posting_url"
    }

    var jobListingString: String {
        var descriptionParts: [String] = []

        descriptionParts.append("Job Position: \(jobPosition)")
        descriptionParts.append("Job Location: \(jobLocation)")
        descriptionParts.append("Company Name: \(companyName)")

        if !companyLinkedinId.isEmpty {
            descriptionParts.append("Company LinkedIn ID: \(companyLinkedinId)")
        }

        if !jobPostingTime.isEmpty {
            descriptionParts.append("Job Posting Time: \(jobPostingTime)")
        }

        if !seniorityLevel.isEmpty {
            descriptionParts.append("Seniority Level: \(seniorityLevel)")
        }

        if !employmentType.isEmpty {
            descriptionParts.append("Employment Type: \(employmentType)")
        }

        if !jobFunction.isEmpty {
            descriptionParts.append("Job Function: \(jobFunction)")
        }

        if !industries.isEmpty {
            descriptionParts.append("Industries: \(industries)")
        }

        if !jobDescription.isEmpty {
            descriptionParts.append("Job Description: \(jobDescription)")
        }

        return descriptionParts.joined(separator: "\n")
    }

    // UI helpers have been moved to SwiftUI‑only extension (ViewExtensions).

    init(
        jobPosition: String = "",
        jobLocation: String = "",
        companyName: String = "",
        companyLinkedinId: String = "",
        jobPostingTime: String = "",
        jobDescription: String = "",
        seniorityLevel: String = "",
        employmentType: String = "",
        jobFunction: String = "",
        industries: String = "",
        jobApplyLink: String = "",
        postingURL: String = ""
    ) {
        self.jobPosition = jobPosition
        self.jobLocation = jobLocation
        self.companyName = companyName
        self.companyLinkedinId = companyLinkedinId
        self.jobPostingTime = jobPostingTime
        self.jobDescription = jobDescription
        self.seniorityLevel = seniorityLevel
        self.employmentType = employmentType
        self.jobFunction = jobFunction
        self.industries = industries
        self.jobApplyLink = jobApplyLink
        self.postingURL = postingURL
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
        jobPosition = try container.decode(String.self, forKey: .jobPosition)
        jobLocation = try container.decode(String.self, forKey: .jobLocation)
        companyName = try container.decode(String.self, forKey: .companyName)
        companyLinkedinId = try container.decodeIfPresent(String.self, forKey: .companyLinkedinId) ?? ""
        jobPostingTime = try container.decodeIfPresent(String.self, forKey: .jobPostingTime) ?? ""
        jobDescription = try container.decode(String.self, forKey: .jobDescription)
        seniorityLevel = try container.decodeIfPresent(String.self, forKey: .seniorityLevel) ?? ""
        employmentType = try container.decodeIfPresent(String.self, forKey: .employmentType) ?? ""
        jobFunction = try container.decodeIfPresent(String.self, forKey: .jobFunction) ?? ""
        industries = try container.decodeIfPresent(String.self, forKey: .industries) ?? ""
        jobApplyLink = try container.decodeIfPresent(String.self, forKey: .jobApplyLink) ?? ""
        status = try container.decodeIfPresent(Statuses.self, forKey: .status) ?? .new
        resumes = []
    }

    public func assignPropsFromForm(_ sourceJobAppForm: JobAppForm) {
        jobPosition = sourceJobAppForm.jobPosition
        jobLocation = sourceJobAppForm.jobLocation
        companyName = sourceJobAppForm.companyName
        companyLinkedinId = sourceJobAppForm.companyLinkedinId
        jobPostingTime = sourceJobAppForm.jobPostingTime
        jobDescription = sourceJobAppForm.jobDescription
        seniorityLevel = sourceJobAppForm.seniorityLevel
        employmentType = sourceJobAppForm.employmentType
        jobFunction = sourceJobAppForm.jobFunction
        industries = sourceJobAppForm.industries
        jobApplyLink = sourceJobAppForm.jobApplyLink
        postingURL = sourceJobAppForm.postingURL
    }
}
