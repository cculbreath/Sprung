//
//  JobApp.swift
//  Sprung
//
//
import Foundation
import SwiftData

/// Priority level for a job application
enum JobLeadPriority: String, Codable, CaseIterable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"
}

/// Stage in the application pipeline (used by SearchOps Kanban)
enum ApplicationStage: String, Codable, CaseIterable {
    case identified = "Identified"
    case researching = "Researching"
    case applying = "Applying"
    case applied = "Applied"
    case interviewing = "Interviewing"
    case offer = "Offer"
    case accepted = "Accepted"
    case rejected = "Rejected"
    case withdrawn = "Withdrawn"

    /// Next stage in the progression
    var next: ApplicationStage? {
        switch self {
        case .identified: return .researching
        case .researching: return .applying
        case .applying: return .applied
        case .applied: return .interviewing
        case .interviewing: return .offer
        case .offer: return .accepted
        case .accepted, .rejected, .withdrawn: return nil
        }
    }
}

enum Statuses: String, Codable, CaseIterable {
    case new = "new"
    case inProgress = "In Progress"
    case unsubmitted = "Unsubmitted"
    case submitted = "Submitted"
    case interview = "Interview Pending"
    case closed = "Closed"
    case followUp = "Follow up Required"
    case abandonned = "Abandonned" // Legacy spelling maintained for persisted records
    case rejected = "Rejected"
}
extension Statuses {
    /// Human-friendly label for UI surfaces.
    var displayName: String {
        switch self {
        case .abandonned:
            return "Abandoned"
        default:
            return rawValue
        }
    }
}
@Model class JobApp: Equatable, Identifiable, Hashable {
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

    // MARK: - SearchOps Pipeline Properties

    /// Priority level for the application (SearchOps Kanban)
    var priority: JobLeadPriority = JobLeadPriority.medium

    /// Current stage in the application pipeline (SearchOps Kanban)
    var stage: ApplicationStage = ApplicationStage.identified

    /// Source where the lead was discovered (e.g., LinkedIn, Indeed)
    var source: String?

    /// URL to the application form
    var applicationUrl: String?

    // MARK: - Pipeline Dates

    var createdAt: Date = Date()
    var identifiedDate: Date?
    var appliedDate: Date?
    var firstInterviewDate: Date?
    var lastInterviewDate: Date?
    var offerDate: Date?
    var closedDate: Date?

    // MARK: - Interview Tracking

    var interviewCount: Int = 0
    var lastInterviewNotes: String?

    // MARK: - Outcome Details

    var rejectionReason: String?
    var withdrawalReason: String?
    var offerDetails: String?

    // MARK: - LLM Assessment

    var fitScore: Double?
    var llmAssessment: String?

    // MARK: - Computed Properties

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
        }
        if selectedRes == nil {
            selectedRes = resume
        }
    }
    func resumeDeletePrep(candidate: Resume) {
        if selectedRes == candidate {
            if resumes.count <= 1 {
                // This was the last resume, set selection to nil
                selectedResId = nil
            } else {
                // Find another resume to select
                if let anotherResume = resumes.first(where: { $0.id != candidate.id }) {
                    selectedResId = anotherResume.id
                }
            }
        }
        // No else branch needed - if selectedRes != candidate, we don't need to change selection
    }

    func replaceUUIDsWithLetterNames(in text: String) -> String {
        var result = text
        for letter in self.coverLetters {
            let uuidString = letter.id.uuidString
            if result.contains(uuidString) {
                result = result.replacingOccurrences(of: uuidString, with: letter.sequencedName)
            }
        }
        return result
    }

    // MARK: - SearchOps Computed Properties

    var daysSinceCreated: Int? {
        Calendar.current.dateComponents([.day], from: createdAt, to: Date()).day
    }

    var daysSinceApplied: Int? {
        guard let appliedDate = appliedDate else { return nil }
        return Calendar.current.dateComponents([.day], from: appliedDate, to: Date()).day
    }

    var isActive: Bool {
        switch stage {
        case .accepted, .rejected, .withdrawn: return false
        default: return true
        }
    }

    // MARK: - Conversion from JobLead (Legacy)

    /// Initialize JobApp from legacy JobLead model
    /// - Parameter jobLead: The JobLead to convert
    convenience init(from jobLead: JobLead) {
        self.init(
            jobPosition: jobLead.role ?? "",
            jobLocation: "",
            companyName: jobLead.company,
            companyLinkedinId: "",
            jobPostingTime: "",
            jobDescription: "",
            seniorityLevel: "",
            employmentType: "",
            jobFunction: "",
            industries: "",
            jobApplyLink: jobLead.applicationUrl ?? "",
            postingURL: jobLead.url ?? ""
        )

        // Map SearchOps-specific properties
        self.priority = jobLead.priority
        self.stage = jobLead.stage
        self.source = jobLead.source
        self.applicationUrl = jobLead.applicationUrl
        self.notes = jobLead.notes ?? ""

        // Map dates
        self.createdAt = jobLead.createdAt
        self.identifiedDate = jobLead.identifiedDate
        self.appliedDate = jobLead.appliedDate
        self.firstInterviewDate = jobLead.firstInterviewDate
        self.lastInterviewDate = jobLead.lastInterviewDate
        self.offerDate = jobLead.offerDate
        self.closedDate = jobLead.closedDate

        // Map interview tracking
        self.interviewCount = jobLead.interviewCount
        self.lastInterviewNotes = jobLead.lastInterviewNotes

        // Map outcome details
        self.rejectionReason = jobLead.rejectionReason
        self.withdrawalReason = jobLead.withdrawalReason
        self.offerDetails = jobLead.offerDetails

        // Map LLM assessment
        self.fitScore = jobLead.fitScore
        self.llmAssessment = jobLead.llmAssessment

        // Note: resumeId and coverLetterId from JobLead are not directly mapped
        // as JobApp uses relationships instead
    }
}
