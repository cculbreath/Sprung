//
//  SeedGenerationContext.swift
//  Sprung
//
//  Immutable snapshot of all OI outputs needed for seed generation.
//

import Foundation
import SwiftyJSON

/// Immutable snapshot of all OI outputs needed for generation
struct SeedGenerationContext {
    /// Applicant profile data
    let applicantProfile: ApplicantProfileDraft

    /// Skeleton timeline entries from onboarding
    let skeletonTimeline: JSON

    /// Section configuration (enabled sections + custom field definitions)
    let sectionConfig: SectionConfig

    /// Knowledge cards from document extraction
    let knowledgeCards: [KnowledgeCard]

    /// Skills from the skill bank
    let skills: [Skill]

    /// Pre-built voice context string from CoverRefStore.writersVoice
    let writersVoice: String

    /// Candidate dossier with strategic insights (if available)
    let dossier: JSON?

    /// Available title sets from the library (for LLM selection)
    let titleSets: [TitleSetRecord]

    // MARK: - Timeline Entry Access

    /// Get a specific timeline entry by ID
    func getTimelineEntry(id: String) -> JSON? {
        guard let experiences = skeletonTimeline["experiences"].array else {
            return nil
        }
        return experiences.first { entry in
            entry["id"].stringValue == id
        }
    }

    /// Get timeline entries for an ExperienceSectionKey
    func timelineEntries(for section: ExperienceSectionKey) -> [JSON] {
        let experienceType: String
        switch section {
        case .work: experienceType = "work"
        case .education: experienceType = "education"
        case .volunteer: experienceType = "volunteer"
        case .projects: experienceType = "project"
        case .awards: experienceType = "award"
        case .certificates: experienceType = "certificate"
        case .publications: experienceType = "publication"
        case .languages: experienceType = "language"
        case .interests: experienceType = "interest"
        case .references: experienceType = "reference"
        case .skills: return [] // Skills don't have timeline entries
        default: return []
        }
        return timelineEntries(for: experienceType)
    }

    /// Get all timeline entries for a specific experience type
    func timelineEntries(for experienceType: String) -> [JSON] {
        guard let experiences = skeletonTimeline["experiences"].array else {
            return []
        }
        return experiences.filter { entry in
            entry["experienceType"].stringValue == experienceType
        }
    }

    /// Get all work experience entries
    var workEntries: [JSON] {
        timelineEntries(for: "work")
    }

    /// Get all education entries
    var educationEntries: [JSON] {
        timelineEntries(for: "education")
    }

    /// Get all volunteer entries
    var volunteerEntries: [JSON] {
        timelineEntries(for: "volunteer")
    }

    /// Get all project entries from timeline
    var projectEntries: [JSON] {
        timelineEntries(for: "project")
    }

    /// Get all award entries
    var awardEntries: [JSON] {
        timelineEntries(for: "award")
    }

    /// Get all certificate entries
    var certificateEntries: [JSON] {
        timelineEntries(for: "certificate")
    }

    /// Get all publication entries
    var publicationEntries: [JSON] {
        timelineEntries(for: "publication")
    }

    // MARK: - Knowledge Card Relevance

    /// Get knowledge cards relevant to a specific timeline entry
    /// Matches by organization name and/or date range overlap
    func relevantKCs(for entry: JSON) -> [KnowledgeCard] {
        let entryOrg = entry["name"].stringValue.lowercased()
        let entryPosition = entry["position"].stringValue.lowercased()
        let entryStartDate = entry["startDate"].string
        let entryEndDate = entry["endDate"].string

        return knowledgeCards.filter { card in
            // Match by organization
            if let cardOrg = card.organization?.lowercased(),
               !cardOrg.isEmpty,
               (entryOrg.contains(cardOrg) || cardOrg.contains(entryOrg)) {
                return true
            }

            // Match by title in narrative
            if !entryPosition.isEmpty,
               card.narrative.lowercased().contains(entryPosition) {
                return true
            }

            // Match by date range overlap
            if let cardDateRange = card.dateRange,
               let entryStart = entryStartDate,
               datesOverlap(
                cardRange: cardDateRange,
                entryStart: entryStart,
                entryEnd: entryEndDate
               ) {
                return true
            }

            return false
        }
    }

    /// Get knowledge cards by type
    func knowledgeCards(ofType type: CardType) -> [KnowledgeCard] {
        knowledgeCards.filter { $0.cardType == type }
    }

    /// Get all project-related knowledge cards
    var projectKnowledgeCards: [KnowledgeCard] {
        knowledgeCards(ofType: .project)
    }

    /// Get all achievement-related knowledge cards
    var achievementKnowledgeCards: [KnowledgeCard] {
        knowledgeCards(ofType: .achievement)
    }

    // MARK: - Section Enablement

    /// Check if a section is enabled
    func isEnabled(_ section: ExperienceSectionKey) -> Bool {
        sectionConfig.isEnabled(section)
    }

    /// Get all enabled section keys
    var enabledSections: [ExperienceSectionKey] {
        sectionConfig.enabledStandardSections
    }

    /// Get custom field definitions for enabled custom fields
    var enabledCustomFields: [CustomFieldDefinition] {
        sectionConfig.customFields.filter { field in
            sectionConfig.enabledSections.contains(field.key)
        }
    }

    // MARK: - Private Helpers

    private func datesOverlap(
        cardRange: String,
        entryStart: String,
        entryEnd: String?
    ) -> Bool {
        // Simple date overlap check based on year-month format
        // cardRange format: "2020-09 to 2024-06" or "2020 to Present"
        let components = cardRange.lowercased().components(separatedBy: " to ")
        guard components.count == 2 else { return false }

        let cardStart = components[0].trimmingCharacters(in: .whitespaces)
        let cardEnd = components[1].trimmingCharacters(in: .whitespaces)

        // Extract years for simple comparison
        let cardStartYear = extractYear(from: cardStart)
        let cardEndYear = cardEnd == "present" ? 9999 : extractYear(from: cardEnd)
        let entryStartYear = extractYear(from: entryStart)
        let entryEndYear = entryEnd.map { extractYear(from: $0) } ?? 9999

        // Check for overlap
        return cardStartYear <= entryEndYear && cardEndYear >= entryStartYear
    }

    private func extractYear(from dateString: String) -> Int {
        // Extract 4-digit year from various formats
        let pattern = #"(\d{4})"#
        if let match = dateString.range(of: pattern, options: .regularExpression) {
            return Int(dateString[match]) ?? 0
        }
        return 0
    }
}

// MARK: - Context Builder

extension SeedGenerationContext {
    /// Build context from ArtifactRepository and related stores
    static func build(
        from artifacts: OnboardingArtifacts,
        knowledgeCards: [KnowledgeCard],
        skills: [Skill],
        writersVoice: String,
        dossier: JSON?,
        titleSets: [TitleSetRecord]
    ) -> SeedGenerationContext {
        let profile: ApplicantProfileDraft
        if let profileJSON = artifacts.applicantProfile {
            profile = ApplicantProfileDraft(json: profileJSON)
        } else {
            profile = ApplicantProfileDraft()
        }

        let sectionConfig = SectionConfig(
            enabledSections: artifacts.enabledSections,
            customFields: artifacts.customFieldDefinitions
        )

        return SeedGenerationContext(
            applicantProfile: profile,
            skeletonTimeline: artifacts.skeletonTimeline ?? JSON(),
            sectionConfig: sectionConfig,
            knowledgeCards: knowledgeCards,
            skills: skills,
            writersVoice: writersVoice,
            dossier: dossier,
            titleSets: titleSets
        )
    }

    /// Build context from ExperienceDefaults - used when launching SGM from Experience Editor
    static func build(
        from defaults: ExperienceDefaults,
        applicantProfile: ApplicantProfileDraft,
        knowledgeCards: [KnowledgeCard],
        skills: [Skill],
        writersVoice: String,
        dossier: JSON?,
        titleSets: [TitleSetRecord]
    ) -> SeedGenerationContext {
        // Build enabled sections from defaults flags (as raw strings)
        var enabledSections: Set<String> = []
        if defaults.isWorkEnabled { enabledSections.insert(ExperienceSectionKey.work.rawValue) }
        if defaults.isEducationEnabled { enabledSections.insert(ExperienceSectionKey.education.rawValue) }
        if defaults.isVolunteerEnabled { enabledSections.insert(ExperienceSectionKey.volunteer.rawValue) }
        if defaults.isProjectsEnabled { enabledSections.insert(ExperienceSectionKey.projects.rawValue) }
        if defaults.isSkillsEnabled { enabledSections.insert(ExperienceSectionKey.skills.rawValue) }
        if defaults.isAwardsEnabled { enabledSections.insert(ExperienceSectionKey.awards.rawValue) }
        if defaults.isCertificatesEnabled { enabledSections.insert(ExperienceSectionKey.certificates.rawValue) }
        if defaults.isPublicationsEnabled { enabledSections.insert(ExperienceSectionKey.publications.rawValue) }
        if defaults.isLanguagesEnabled { enabledSections.insert(ExperienceSectionKey.languages.rawValue) }
        if defaults.isInterestsEnabled { enabledSections.insert(ExperienceSectionKey.interests.rawValue) }
        if defaults.isReferencesEnabled { enabledSections.insert(ExperienceSectionKey.references.rawValue) }
        if defaults.isCustomEnabled { enabledSections.insert(ExperienceSectionKey.custom.rawValue) }

        let sectionConfig = SectionConfig(
            enabledSections: enabledSections,
            customFields: []  // Custom field definitions not stored in ExperienceDefaults
        )

        // Build skeleton timeline JSON from ExperienceDefaults entries
        let skeletonTimeline = buildSkeletonTimeline(from: defaults)

        return SeedGenerationContext(
            applicantProfile: applicantProfile,
            skeletonTimeline: skeletonTimeline,
            sectionConfig: sectionConfig,
            knowledgeCards: knowledgeCards,
            skills: skills,
            writersVoice: writersVoice,
            dossier: dossier,
            titleSets: titleSets
        )
    }

    /// Convert ExperienceDefaults entries to skeleton timeline JSON format
    private static func buildSkeletonTimeline(from defaults: ExperienceDefaults) -> JSON {
        var experiences: [[String: Any]] = []

        // Work entries
        for work in defaults.work {
            experiences.append([
                "id": work.id.uuidString,
                "experienceType": "work",
                "company": work.name,
                "title": work.position,
                "location": work.location,
                "startDate": work.startDate,
                "endDate": work.endDate,
                "description": work.summary,
                "highlights": work.highlights.map { $0.text }
            ])
        }

        // Education entries
        for edu in defaults.education {
            experiences.append([
                "id": edu.id.uuidString,
                "experienceType": "education",
                "institution": edu.institution,
                "area": edu.area,
                "studyType": edu.studyType,
                "startDate": edu.startDate,
                "endDate": edu.endDate,
                "score": edu.score,
                "courses": edu.courses.map { $0.name }
            ])
        }

        // Volunteer entries
        for vol in defaults.volunteer {
            experiences.append([
                "id": vol.id.uuidString,
                "experienceType": "volunteer",
                "organization": vol.organization,
                "position": vol.position,
                "startDate": vol.startDate,
                "endDate": vol.endDate,
                "summary": vol.summary,
                "highlights": vol.highlights.map { $0.text }
            ])
        }

        // Project entries
        for proj in defaults.projects {
            experiences.append([
                "id": proj.id.uuidString,
                "experienceType": "project",
                "name": proj.name,
                "description": proj.description,
                "startDate": proj.startDate,
                "endDate": proj.endDate,
                "url": proj.url,
                "highlights": proj.highlights.map { $0.text },
                "keywords": proj.keywords.map { $0.keyword }
            ])
        }

        return JSON(["experiences": experiences])
    }
}
