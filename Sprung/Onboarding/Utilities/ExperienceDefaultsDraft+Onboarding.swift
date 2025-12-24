import Foundation
extension ExperienceDefaultsDraft {
    mutating func setEnabledSections(_ enabled: Set<ExperienceSectionKey>) {
        for key in ExperienceSectionKey.allCases {
            let isEnabled = enabled.contains(key)
            setEnabled(isEnabled, for: key)
        }
    }
    func enabledSectionKeys() -> [ExperienceSectionKey] {
        ExperienceSectionKey.allCases.filter { isEnabled(for: $0) }
    }
    private mutating func setEnabled(_ isEnabled: Bool, for key: ExperienceSectionKey) {
        switch key {
        case .summary: isSummaryEnabled = isEnabled
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
        case .custom: isCustomEnabled = isEnabled
        }
    }
    private func isEnabled(for key: ExperienceSectionKey) -> Bool {
        switch key {
        case .summary: return isSummaryEnabled
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
        case .custom: return isCustomEnabled
        }
    }
}
