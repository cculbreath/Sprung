//
//  SectionCardAdapter.swift
//  Sprung
//
//  Converts onboarding section cards to Experience Draft models.
//  Used when transitioning from Phase 2 to Phase 3 or when populating
//  ExperienceDefaults from collected section data.
//

import Foundation

/// Adapter for converting onboarding section cards to Experience Draft models
struct SectionCardAdapter {

    // MARK: - Section Card Conversions

    /// Convert an AdditionalSectionEntry to its corresponding Draft model
    /// Returns a tuple with the section type and the draft (as Any for type erasure)
    static func toDraft(_ entry: AdditionalSectionEntry) -> (type: String, draft: Any)? {
        switch entry.sectionType {
        case .award:
            let draft = AwardExperienceDraft(
                id: UUID(uuidString: entry.id) ?? UUID(),
                title: entry.title ?? "",
                date: entry.date ?? "",
                awarder: entry.awarder ?? "",
                summary: entry.awardSummary ?? ""
            )
            return ("award", draft)

        case .language:
            let draft = LanguageExperienceDraft(
                id: UUID(uuidString: entry.id) ?? UUID(),
                language: entry.language ?? "",
                fluency: entry.fluency ?? ""
            )
            return ("language", draft)

        case .reference:
            let draft = ReferenceExperienceDraft(
                id: UUID(uuidString: entry.id) ?? UUID(),
                name: entry.referenceName ?? "",
                reference: entry.referenceText ?? "",
                url: entry.referenceUrl ?? ""
            )
            return ("reference", draft)
        }
    }

    /// Convert an AdditionalSectionEntry (award) to AwardExperienceDraft
    static func toAwardDraft(_ entry: AdditionalSectionEntry) -> AwardExperienceDraft? {
        guard entry.sectionType == .award else { return nil }
        return AwardExperienceDraft(
            id: UUID(uuidString: entry.id) ?? UUID(),
            title: entry.title ?? "",
            date: entry.date ?? "",
            awarder: entry.awarder ?? "",
            summary: entry.awardSummary ?? ""
        )
    }

    /// Convert an AdditionalSectionEntry (language) to LanguageExperienceDraft
    static func toLanguageDraft(_ entry: AdditionalSectionEntry) -> LanguageExperienceDraft? {
        guard entry.sectionType == .language else { return nil }
        return LanguageExperienceDraft(
            id: UUID(uuidString: entry.id) ?? UUID(),
            language: entry.language ?? "",
            fluency: entry.fluency ?? ""
        )
    }

    /// Convert an AdditionalSectionEntry (reference) to ReferenceDraft
    static func toReferenceDraft(_ entry: AdditionalSectionEntry) -> ReferenceExperienceDraft? {
        guard entry.sectionType == .reference else { return nil }
        return ReferenceExperienceDraft(
            id: UUID(uuidString: entry.id) ?? UUID(),
            name: entry.referenceName ?? "",
            reference: entry.referenceText ?? "",
            url: entry.referenceUrl ?? ""
        )
    }

    // MARK: - Publication Card Conversions

    /// Convert a PublicationCard to PublicationExperienceDraft
    static func toPublicationDraft(_ card: PublicationCard) -> PublicationExperienceDraft {
        PublicationExperienceDraft(
            id: UUID(uuidString: card.id) ?? UUID(),
            name: card.name,
            publisher: card.publisher,
            releaseDate: card.releaseDate,
            url: card.url,
            summary: card.summary
        )
    }

    // MARK: - Batch Conversions

    /// Convert all section cards to their corresponding draft arrays
    /// Returns a tuple with arrays for each section type
    static func convertAllSectionCards(_ entries: [AdditionalSectionEntry]) -> (
        awards: [AwardExperienceDraft],
        languages: [LanguageExperienceDraft],
        references: [ReferenceExperienceDraft]
    ) {
        var awards: [AwardExperienceDraft] = []
        var languages: [LanguageExperienceDraft] = []
        var references: [ReferenceExperienceDraft] = []

        for entry in entries {
            switch entry.sectionType {
            case .award:
                if let draft = toAwardDraft(entry) {
                    awards.append(draft)
                }
            case .language:
                if let draft = toLanguageDraft(entry) {
                    languages.append(draft)
                }
            case .reference:
                if let draft = toReferenceDraft(entry) {
                    references.append(draft)
                }
            }
        }

        return (awards, languages, references)
    }

    /// Convert all publication cards to PublicationExperienceDrafts
    static func convertAllPublicationCards(_ cards: [PublicationCard]) -> [PublicationExperienceDraft] {
        cards.map { toPublicationDraft($0) }
    }

    // MARK: - Merge with ExperienceDefaultsDraft

    /// Merge section cards into an existing ExperienceDefaultsDraft
    /// This adds the converted cards to the appropriate arrays
    static func mergeSectionCards(
        _ entries: [AdditionalSectionEntry],
        into draft: inout ExperienceDefaultsDraft
    ) {
        let converted = convertAllSectionCards(entries)
        draft.awards.append(contentsOf: converted.awards)
        draft.languages.append(contentsOf: converted.languages)
        draft.references.append(contentsOf: converted.references)

        // Enable sections if we have entries
        if !converted.awards.isEmpty { draft.isAwardsEnabled = true }
        if !converted.languages.isEmpty { draft.isLanguagesEnabled = true }
        if !converted.references.isEmpty { draft.isReferencesEnabled = true }
    }

    /// Merge publication cards into an existing ExperienceDefaultsDraft
    static func mergePublicationCards(
        _ cards: [PublicationCard],
        into draft: inout ExperienceDefaultsDraft
    ) {
        let converted = convertAllPublicationCards(cards)
        draft.publications.append(contentsOf: converted)

        // Enable publications section if we have entries
        if !converted.isEmpty { draft.isPublicationsEnabled = true }
    }
}
