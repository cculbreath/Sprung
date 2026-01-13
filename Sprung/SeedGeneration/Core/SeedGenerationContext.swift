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

    /// Writing samples for voice/style guidance
    let writingSamples: [CoverRef]

    /// Voice primer for style guidance (if available)
    let voicePrimer: CoverRef?

    // MARK: - Timeline Entry Access

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

    // MARK: - Voice/Style Guidance

    /// Get voice primer content for LLM context
    var voiceGuidance: String? {
        if let primer = voicePrimer {
            return primer.content
        }
        // Fall back to writing samples summary
        if !writingSamples.isEmpty {
            return writingSamples
                .map { "Sample: \($0.name)\n\($0.content.prefix(500))..." }
                .joined(separator: "\n\n")
        }
        return nil
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
        writingSamples: [CoverRef],
        voicePrimer: CoverRef?
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
            writingSamples: writingSamples.filter { $0.type == .writingSample },
            voicePrimer: voicePrimer
        )
    }
}
