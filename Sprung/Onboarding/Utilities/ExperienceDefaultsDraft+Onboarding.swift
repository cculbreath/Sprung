import Foundation

extension ExperienceDefaultsDraft {
    mutating func setEnabledSections(_ enabled: Set<ExperienceSectionKey>) {
        for key in ExperienceSectionKey.allCases {
            let isEnabled = enabled.contains(key)
            setEnabled(isEnabled, for: key)
        }
    }

    mutating func replaceSection(_ key: ExperienceSectionKey, with other: ExperienceDefaultsDraft) {
        switch key {
        case .work:
            work = other.work
            isWorkEnabled = !work.isEmpty
        case .volunteer:
            volunteer = other.volunteer
            isVolunteerEnabled = !volunteer.isEmpty
        case .education:
            education = other.education
            isEducationEnabled = !education.isEmpty
        case .projects:
            projects = other.projects
            isProjectsEnabled = !projects.isEmpty
        case .skills:
            skills = other.skills
            isSkillsEnabled = !skills.isEmpty
        case .awards:
            awards = other.awards
            isAwardsEnabled = !awards.isEmpty
        case .certificates:
            certificates = other.certificates
            isCertificatesEnabled = !certificates.isEmpty
        case .publications:
            publications = other.publications
            isPublicationsEnabled = !publications.isEmpty
        case .languages:
            languages = other.languages
            isLanguagesEnabled = !languages.isEmpty
        case .interests:
            interests = other.interests
            isInterestsEnabled = !interests.isEmpty
        case .references:
            references = other.references
            isReferencesEnabled = !references.isEmpty
        }
    }

    func enabledSectionKeys() -> [ExperienceSectionKey] {
        ExperienceSectionKey.allCases.filter { isEnabled(for: $0) }
    }

    private mutating func setEnabled(_ isEnabled: Bool, for key: ExperienceSectionKey) {
        switch key {
        case .work: isWorkEnabled = isEnabled
        case .volunteer: isVolunteerEnabled = isEnabled
        case .education: isEducationEnabled = isEnabled
        case .projects: isProjectsEnabled = isEnabled
        case .skills: isSkillsEnabled = isEnabled
        case .awards: isAwardsEnabled = isEnabled
        case .certificates: isCertificatesEnabled = isEnabled
        case .publications: isPublicationsEnabled = isEnabled
        case .languages: isLanguagesEnabled = isEnabled
        case .interests: isInterestsEnabled = isEnabled
        case .references: isReferencesEnabled = isEnabled
        }
    }

    private func isEnabled(for key: ExperienceSectionKey) -> Bool {
        switch key {
        case .work: return isWorkEnabled
        case .volunteer: return isVolunteerEnabled
        case .education: return isEducationEnabled
        case .projects: return isProjectsEnabled
        case .skills: return isSkillsEnabled
        case .awards: return isAwardsEnabled
        case .certificates: return isCertificatesEnabled
        case .publications: return isPublicationsEnabled
        case .languages: return isLanguagesEnabled
        case .interests: return isInterestsEnabled
        case .references: return isReferencesEnabled
        }
    }
}
