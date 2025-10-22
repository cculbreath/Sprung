import Foundation

extension ExperienceSectionKey {
    static func fromOnboardingIdentifier(_ identifier: String) -> ExperienceSectionKey? {
        let normalized = identifier
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")

        switch normalized {
        case "work", "work_experience", "jobs", "employment":
            return .work
        case "volunteer", "volunteer_experience":
            return .volunteer
        case "education", "education_experience", "academics":
            return .education
        case "projects", "project", "project_experience":
            return .projects
        case "skills", "skill":
            return .skills
        case "awards", "honors", "achievements":
            return .awards
        case "certificates", "certifications":
            return .certificates
        case "publications", "publication":
            return .publications
        case "languages", "language":
            return .languages
        case "interests", "interest":
            return .interests
        case "references", "reference":
            return .references
        default:
            return ExperienceSectionKey(rawValue: normalized)
        }
    }
}
