//
//  JobApp.swift
//  Sprung
//
//
import Foundation
import SwiftData
import SwiftUI

/// Priority level for a job application
enum JobLeadPriority: String, Codable, CaseIterable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"
}

/// Application status - unified pipeline for both sidebar and kanban views
enum Statuses: String, Codable, CaseIterable {
    case new = "new"                        // Identified/gathered lead
    case queued = "Queued"                  // On deck, ready to work on
    case inProgress = "In Progress"         // Actively working on application
    case submitted = "Submitted"            // Application sent
    case interview = "Interview Pending"    // In interview process
    case offer = "Offer"                    // Received an offer
    case accepted = "Accepted"              // Accepted the offer
    case rejected = "Rejected"              // Rejected by company
    case withdrawn = "Withdrawn"            // User withdrew application
}

extension Statuses {
    /// Human-friendly label for UI surfaces
    var displayName: String {
        switch self {
        case .new: return "Identified"
        default: return rawValue
        }
    }

    /// Next status in the pipeline progression
    var next: Statuses? {
        switch self {
        case .new: return .queued
        case .queued: return .inProgress
        case .inProgress: return .submitted
        case .submitted: return .interview
        case .interview: return .offer
        case .offer: return .accepted
        case .accepted, .rejected, .withdrawn: return nil
        }
    }

    /// Whether this status can be advanced to the next stage
    var canAdvance: Bool { next != nil }

    /// Whether this is a terminal status (end of pipeline)
    var isTerminal: Bool {
        switch self {
        case .accepted, .rejected, .withdrawn: return true
        default: return false
        }
    }

    /// Whether this is an active (non-terminal) status
    var isActive: Bool { !isTerminal }

    /// Icon for the status
    var icon: String {
        switch self {
        case .new: return "sparkles"
        case .queued: return "tray.full"
        case .inProgress: return "arrow.triangle.2.circlepath"
        case .submitted: return "paperplane.fill"
        case .interview: return "person.2"
        case .offer: return "gift"
        case .accepted: return "checkmark.seal.fill"
        case .rejected: return "xmark.circle"
        case .withdrawn: return "arrow.uturn.backward"
        }
    }

    /// Color for the status
    var color: SwiftUI.Color {
        switch self {
        case .new: return .blue
        case .queued: return .cyan
        case .inProgress: return .purple
        case .submitted: return .green
        case .interview: return .teal
        case .offer: return .yellow
        case .accepted: return .mint
        case .rejected: return .red
        case .withdrawn: return .gray
        }
    }

    /// All pipeline statuses in order
    static var pipelineStatuses: [Statuses] {
        [.new, .queued, .inProgress, .submitted, .interview, .offer, .accepted, .rejected, .withdrawn]
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
    /// Salary range or compensation details (e.g., "$150K - $200K/yr")
    var salary: String = ""
    var status: Statuses = Statuses.new
    var notes: String = ""

    // MARK: - Discovery Pipeline Properties

    /// Priority level for the application (Discovery Kanban)
    /// Stored as optional for migration compatibility with existing records
    private var _priority: JobLeadPriority?

    /// Priority level accessor (defaults to .medium for existing records)
    var priority: JobLeadPriority {
        get { _priority ?? .medium }
        set { _priority = newValue }
    }

    /// Source where the lead was discovered (e.g., LinkedIn, Indeed)
    var source: String?

    /// Reference to JobSource where this job was found
    var jobSourceId: UUID?

    // MARK: - Job Board Domain Extraction

    /// Extract job board name from a URL
    static func extractJobBoardName(from urlString: String) -> String? {
        guard let url = URL(string: urlString),
              let host = url.host?.lowercased() else { return nil }

        let knownBoards: [String: String] = [
            "linkedin.com": "LinkedIn",
            "indeed.com": "Indeed",
            "glassdoor.com": "Glassdoor",
            "lever.co": "Lever",
            "greenhouse.io": "Greenhouse",
            "workday.com": "Workday",
            "dice.com": "Dice",
            "monster.com": "Monster",
            "ziprecruiter.com": "ZipRecruiter",
            "builtin.com": "Built In",
            "angel.co": "AngelList",
            "wellfound.com": "Wellfound",
            "stackoverflow.com": "Stack Overflow",
            "hired.com": "Hired",
            "simplyhired.com": "SimplyHired",
            "careerbuilder.com": "CareerBuilder",
            "roberthalf.com": "Robert Half",
            "flexjobs.com": "FlexJobs",
            "remote.co": "Remote.co",
            "weworkremotely.com": "We Work Remotely",
            "remoteok.com": "Remote OK",
            "ycombinator.com": "Y Combinator",
            "triplebyte.com": "Triplebyte",
            "otta.com": "Otta",
            "cord.co": "Cord"
        ]

        for (domain, name) in knownBoards {
            if host.contains(domain) { return name }
        }

        // Extract company name from careers subdomain
        if host.contains("careers.") || host.contains("jobs.") {
            let components = host.components(separatedBy: ".")
            if components.count >= 2 {
                return components[1].capitalized + " Careers"
            }
        }

        return nil
    }

    /// Get the job board name from either postingURL or jobApplyLink
    var jobBoardName: String? {
        if let name = Self.extractJobBoardName(from: postingURL), !name.isEmpty {
            return name
        }
        if let name = Self.extractJobBoardName(from: jobApplyLink), !name.isEmpty {
            return name
        }
        return source
    }

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

    // MARK: - Job Preprocessing

    /// Pre-extracted job requirements (populated async after job creation)
    /// Stored as JSON string for SwiftData compatibility
    private var _extractedRequirementsJSON: String?

    /// IDs of knowledge cards identified as relevant during preprocessing
    /// Used when total card tokens exceed the configured limit
    private var _relevantCardIds: [String]?

    /// Decoded extracted requirements
    var extractedRequirements: ExtractedRequirements? {
        get {
            guard let json = _extractedRequirementsJSON,
                  let data = json.data(using: .utf8),
                  let requirements = try? JSONDecoder().decode(ExtractedRequirements.self, from: data) else {
                return nil
            }
            return requirements
        }
        set {
            if let requirements = newValue,
               let data = try? JSONEncoder().encode(requirements),
               let json = String(data: data, encoding: .utf8) {
                _extractedRequirementsJSON = json
            } else {
                _extractedRequirementsJSON = nil
            }
        }
    }

    /// IDs of relevant knowledge cards for this job
    var relevantCardIds: [String]? {
        get { _relevantCardIds }
        set { _relevantCardIds = newValue }
    }

    /// Whether preprocessing has been completed
    var hasPreprocessingComplete: Bool {
        extractedRequirements?.isValid ?? false
    }

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

    // MARK: - Initializers

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

            // Advance to inProgress when first resume is created
            if status == .new || status == .queued {
                status = .inProgress
            }
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

    // MARK: - Discovery Computed Properties

    var daysSinceCreated: Int? {
        Calendar.current.dateComponents([.day], from: createdAt, to: Date()).day
    }

    var daysSinceApplied: Int? {
        guard let appliedDate = appliedDate else { return nil }
        return Calendar.current.dateComponents([.day], from: appliedDate, to: Date()).day
    }

    var isActive: Bool {
        status.isActive
    }

}
