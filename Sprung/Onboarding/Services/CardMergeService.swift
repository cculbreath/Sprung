//
//  CardMergeService.swift
//  Sprung
//
//  Service for aggregating skills and narrative cards across documents.
//  Uses SkillBankService for skill deduplication and merging.
//

import Foundation
import SwiftyJSON

/// Service for aggregating skills and narrative cards across documents
actor CardMergeService {
    private var llmFacade: LLMFacade?
    private let artifactRepository: ArtifactRepository
    private let skillBankService: SkillBankService

    init(artifactRepository: ArtifactRepository, llmFacade: LLMFacade?) {
        self.artifactRepository = artifactRepository
        self.llmFacade = llmFacade
        self.skillBankService = SkillBankService(llmFacade: llmFacade)
        Logger.info("🔄 CardMergeService initialized", category: .ai)
    }

    // MARK: - Skill Bank + Narrative Cards Methods

    /// Get merged skill bank from all artifacts
    /// Uses SkillBankService to deduplicate and merge skills across documents
    func getMergedSkillBank() async -> SkillBank? {
        let artifacts = await artifactRepository.getArtifacts()
        var documentSkills: [[Skill]] = []
        var sourceDocumentIds: [String] = []

        Logger.info("🔧 CardMergeService: Checking \(artifacts.artifactRecords.count) artifacts for skills", category: .ai)

        for artifact in artifacts.artifactRecords {
            let filename = artifact["filename"].stringValue
            let artifactId = artifact["id"].stringValue

            guard let skillsString = artifact["skills"].string,
                  let skillsData = skillsString.data(using: .utf8) else {
                Logger.debug("⏭️ Skipping artifact '\(filename)': no skills data", category: .ai)
                continue
            }

            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let skills = try decoder.decode([Skill].self, from: skillsData)
                documentSkills.append(skills)
                sourceDocumentIds.append(artifactId)
                Logger.debug("🔧 Decoded \(skills.count) skills from artifact: \(filename)", category: .ai)
            } catch {
                Logger.warning("⚠️ Failed to decode skills for artifact \(artifactId): \(error.localizedDescription)", category: .ai)
            }
        }

        guard !documentSkills.isEmpty else {
            Logger.info("🔧 No skills found in any artifacts", category: .ai)
            return nil
        }

        // Use SkillBankService to merge and deduplicate
        let mergedBank = await skillBankService.mergeSkillBank(
            documentSkills: documentSkills,
            sourceDocumentIds: sourceDocumentIds
        )

        Logger.info("✅ Merged skill bank: \(mergedBank.skills.count) skills from \(documentSkills.count) documents", category: .ai)
        return mergedBank
    }

    /// Get all narrative cards from all artifacts
    /// Returns cards grouped by document with document metadata
    func getAllNarrativeCards() async -> [NarrativeCardCollection] {
        let artifacts = await artifactRepository.getArtifacts()
        var collections: [NarrativeCardCollection] = []

        Logger.info("📖 CardMergeService: Checking \(artifacts.artifactRecords.count) artifacts for narrative cards", category: .ai)

        for artifact in artifacts.artifactRecords {
            let filename = artifact["filename"].stringValue
            let artifactId = artifact["id"].stringValue
            let documentType = artifact["document_type"].stringValue

            guard let cardsString = artifact["narrative_cards"].string,
                  let cardsData = cardsString.data(using: .utf8) else {
                Logger.debug("⏭️ Skipping artifact '\(filename)': no narrative_cards data", category: .ai)
                continue
            }

            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let cards = try decoder.decode([KnowledgeCard].self, from: cardsData)

                let collection = NarrativeCardCollection(
                    documentId: artifactId,
                    filename: filename,
                    documentType: documentType,
                    cards: cards
                )
                collections.append(collection)
                Logger.debug("📖 Decoded \(cards.count) narrative cards from artifact: \(filename)", category: .ai)
            } catch {
                Logger.warning("⚠️ Failed to decode narrative cards for artifact \(artifactId): \(error.localizedDescription)", category: .ai)
            }
        }

        let totalCards = collections.reduce(0) { $0 + $1.cards.count }
        Logger.info("✅ Found \(totalCards) narrative cards across \(collections.count) documents", category: .ai)
        return collections
    }

    /// Get a flat list of all narrative cards across all documents
    func getAllNarrativeCardsFlat() async -> [KnowledgeCard] {
        let collections = await getAllNarrativeCards()
        return collections.flatMap { $0.cards }
    }

    enum CardMergeError: Error, LocalizedError {
        case llmNotConfigured
        case noSkillsFound
        case noCardsFound

        var errorDescription: String? {
            switch self {
            case .llmNotConfigured:
                return "LLM facade is not configured"
            case .noSkillsFound:
                return "No skills found in artifacts"
            case .noCardsFound:
                return "No narrative cards found in artifacts"
            }
        }
    }
}

/// Collection of narrative cards from a single document
struct NarrativeCardCollection {
    let documentId: String
    let filename: String
    let documentType: String
    let cards: [KnowledgeCard]
}
