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
}

@Model class JobApp: Equatable, Identifiable, Decodable, Hashable {
  @Relationship(deleteRule: .cascade, inverse: \Resume.jobApp)
  var resumes: [Resume] = []

  @Relationship(deleteRule: .cascade, inverse: \CoverLetter.jobApp)
  var coverLetters: [CoverLetter] = []

  @Transient
  private var _selectedCover: CoverLetter?
  var selectedCover: CoverLetter? {
    get {
      if _selectedCover == nil && !coverLetters.isEmpty {
        return coverLetters.last
      } else {
        return _selectedCover
      }
    }
    set {
      if let newValue = newValue, coverLetters.contains(where: { $0.id == newValue.id }) {
        _selectedCover = newValue
      } else {
        _selectedCover = nil
      }
    }
  }

  @Transient
  private var _selectedRes: Resume?


  var selectedRes: Resume? {
    get {
      if _selectedRes == nil && !resumes.isEmpty {
        return resumes.last
      } else {
        return _selectedRes
      }
    }
    set {
      if let newValue = newValue, resumes.contains(where: { $0.id == newValue.id }) {
        _selectedRes = newValue
      } else {
        _selectedRes = nil
      }
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
  var status: Statuses = Statuses.new

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

  @ViewBuilder
  var statusTag: some View {
    switch self.status {
      case .new:
        RoundedTagView(tagText: "New", backgroundColor: .green, foregroundColor: .white)
      case .inProgress:
        RoundedTagView(tagText: "In Progress", backgroundColor: .mint, foregroundColor: .white)
      case .unsubmitted:
        RoundedTagView(tagText: "Unsubmitted", backgroundColor: .cyan, foregroundColor: .white)
      case .submitted:
        RoundedTagView(tagText: "Submitted", backgroundColor: .indigo, foregroundColor: .white)
      case .interview:
        RoundedTagView(tagText: "Interview", backgroundColor: .pink, foregroundColor: .white)
      case .closed:
        RoundedTagView(tagText: "Closed", backgroundColor: .gray, foregroundColor: .white)
      case .followUp:
        RoundedTagView(tagText: "Follow Up", backgroundColor: .yellow, foregroundColor: .white)
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
    job_apply_link: String = ""
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
  }

  static func == (lhs: JobApp, rhs: JobApp) -> Bool {
    return lhs.id == rhs.id
  }

  func addResume(_ resume: Resume) {
    if self.status == .new {
      self.status = .inProgress
    }

    // Ensure uniqueness
    if !resumes.contains(where: { $0.id == resume.id }) {
      resumes.append(resume)
    }

    if selectedRes == nil { selectedRes = resume }
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }

  required init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.job_position = try container.decode(String.self, forKey: .job_position)
    self.job_location = try container.decode(String.self, forKey: .job_location)
    self.company_name = try container.decode(String.self, forKey: .company_name)
    self.company_linkedin_id = try container.decodeIfPresent(String.self, forKey: .company_linkedin_id) ?? ""
    self.job_posting_time = try container.decodeIfPresent(String.self, forKey: .job_posting_time) ?? ""
    self.job_description = try container.decode(String.self, forKey: .job_description)
    self.seniority_level = try container.decodeIfPresent(String.self, forKey: .seniority_level) ?? ""
    self.employment_type = try container.decodeIfPresent(String.self, forKey: .employment_type) ?? ""
    self.job_function = try container.decodeIfPresent(String.self, forKey: .job_function) ?? ""
    self.industries = try container.decodeIfPresent(String.self, forKey: .industries) ?? ""
    self.job_apply_link = try container.decodeIfPresent(String.self, forKey: .job_apply_link) ?? ""
    self.status = try container.decodeIfPresent(Statuses.self, forKey: .status) ?? .new
  }

  public func assignPropsFromForm(_ sourceJobAppForm: JobAppForm) {
    self.job_position = sourceJobAppForm.job_position
    self.job_location = sourceJobAppForm.job_location
    self.company_name = sourceJobAppForm.company_name
    self.company_linkedin_id = sourceJobAppForm.company_linkedin_id
    self.job_posting_time = sourceJobAppForm.job_posting_time
    self.job_description = sourceJobAppForm.job_description
    self.seniority_level = sourceJobAppForm.seniority_level
    self.employment_type = sourceJobAppForm.employment_type
    self.job_function = sourceJobAppForm.job_function
    self.industries = sourceJobAppForm.industries
    self.job_apply_link = sourceJobAppForm.job_apply_link
  }
}
