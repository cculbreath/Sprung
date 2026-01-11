//
//  WebExtractionService.swift
//  Sprung
//
//  Service for extracting content from web URLs.
//  Follows the same pipeline as DocumentProcessingService:
//  1. Fetch URL content
//  2. Create artifact with extracted text
//  3. Generate narrative knowledge cards
//  4. Extract skills
//

import Foundation
import SwiftyJSON
import SwiftSoup

/// Service that handles web content extraction workflow
@MainActor
final class WebExtractionService {

    // MARK: - Properties

    private var llmFacade: LLMFacade?

    // MARK: - Initialization

    init(llmFacade: LLMFacade? = nil) {
        self.llmFacade = llmFacade
        Logger.info("🌐 WebExtractionService initialized", category: .ai)
    }

    // MARK: - Public API

    /// Process a URL and return extracted content with knowledge cards and skills
    /// - Parameters:
    ///   - url: The URL to fetch and process
    ///   - statusCallback: Optional callback for status updates
    /// - Returns: WebExtractionResult containing extracted content and knowledge
    func processURL(
        url: URL,
        statusCallback: (@Sendable (String) -> Void)? = nil
    ) async throws -> WebExtractionResult {
        let urlString = url.absoluteString
        let filename = url.host ?? "web_content"
        Logger.info("🌐 Processing URL: \(urlString)", category: .ai)

        // Step 1: Fetch HTML content
        statusCallback?("Fetching content from \(url.host ?? "website")...")
        let html = try await WebResourceService.fetchHTML(from: url)
        Logger.info("✅ Fetched HTML content: \(html.count) characters", category: .ai)

        // Step 2: Extract text from HTML
        statusCallback?("Extracting text content...")
        let (extractedText, title) = extractTextFromHTML(html)
        Logger.info("✅ Extracted text: \(extractedText.count) characters, title: \(title ?? "none")", category: .ai)

        // Generate artifact ID
        let artifactId = UUID().uuidString

        // Step 3: Run knowledge extraction in parallel
        statusCallback?("Running knowledge extraction...")

        let skillBankService = SkillBankService(llmFacade: llmFacade)
        let kcExtractionService = KnowledgeCardExtractionService(llmFacade: llmFacade)

        async let skillsTask: [Skill]? = generateSkills(
            service: skillBankService,
            artifactId: artifactId,
            filename: filename,
            extractedText: extractedText
        )
        async let cardsTask: [KnowledgeCard]? = generateNarrativeCards(
            service: kcExtractionService,
            artifactId: artifactId,
            filename: filename,
            extractedText: extractedText
        )

        let (skills, narrativeCards) = await (skillsTask, cardsTask)
        let skillCount = skills?.count ?? 0
        let kcCount = narrativeCards?.count ?? 0
        statusCallback?("Extraction complete: \(skillCount) skills, \(kcCount) narrative cards")
        Logger.info("✅ Knowledge extraction complete: \(skillCount) skills, \(kcCount) KCs", category: .ai)

        return WebExtractionResult(
            id: artifactId,
            url: urlString,
            title: title,
            extractedText: extractedText,
            skills: skills ?? [],
            narrativeCards: narrativeCards ?? []
        )
    }

    /// Create an artifact record from extraction result
    func createArtifactRecord(from result: WebExtractionResult) -> JSON {
        var artifactRecord = JSON()
        artifactRecord["id"].string = result.id
        artifactRecord["filename"].string = result.title ?? result.url
        if let title = result.title {
            artifactRecord["title"].string = title
        }
        artifactRecord["documentType"].string = "web_page"
        artifactRecord["sourceUrl"].string = result.url
        artifactRecord["extractedText"].string = result.extractedText
        artifactRecord["interviewContext"].bool = false

        // Add skill bank
        if !result.skills.isEmpty {
            var skillBank = JSON()
            skillBank["skills"] = JSON(result.skills.map { skill -> [String: Any] in
                var skillDict: [String: Any] = [
                    "canonical": skill.canonical,
                    "atsVariants": skill.atsVariants,
                    "category": skill.category.rawValue,
                    "proficiency": skill.proficiency.rawValue
                ]
                if !skill.evidence.isEmpty {
                    skillDict["evidence"] = skill.evidence.map { evidence -> [String: Any] in
                        [
                            "documentId": evidence.documentId,
                            "location": evidence.location,
                            "context": evidence.context,
                            "strength": evidence.strength.rawValue
                        ]
                    }
                }
                return skillDict
            })
            artifactRecord["skillBank"] = skillBank
        }

        // Add narrative cards
        if !result.narrativeCards.isEmpty {
            var cardsArray: [JSON] = []
            for card in result.narrativeCards {
                var cardJSON = JSON()
                cardJSON["id"].string = card.id.uuidString
                cardJSON["title"].string = card.title
                cardJSON["cardType"].string = card.cardType?.rawValue ?? "unknown"
                cardJSON["narrative"].string = card.narrative
                if let dateRange = card.dateRange {
                    cardJSON["dateRange"].string = dateRange
                }
                cardsArray.append(cardJSON)
            }
            artifactRecord["narrativeCards"] = JSON(cardsArray.map { $0.rawValue })
        }

        return artifactRecord
    }

    // MARK: - Private Helpers

    /// Extract readable text from HTML using SwiftSoup
    private func extractTextFromHTML(_ html: String) -> (text: String, title: String?) {
        do {
            let document = try SwiftSoup.parse(html)

            // Extract title
            let title = try? document.title()

            // Remove script and style elements
            try document.select("script, style, nav, header, footer, aside").remove()

            // Get text content
            let text = try document.text()

            // Clean up whitespace
            let cleanedText = text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            return (cleanedText, title)
        } catch {
            Logger.warning("⚠️ HTML parsing failed: \(error.localizedDescription)", category: .ai)
            // Fall back to basic text extraction
            let basicText = html
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (basicText, nil)
        }
    }

    /// Generate skills from extracted text
    private func generateSkills(
        service: SkillBankService,
        artifactId: String,
        filename: String,
        extractedText: String
    ) async -> [Skill]? {
        guard llmFacade != nil else {
            Logger.warning("⚠️ No LLM facade available for skill extraction", category: .ai)
            return nil
        }

        do {
            let skills = try await service.extractSkills(
                documentId: artifactId,
                filename: filename,
                content: extractedText
            )
            Logger.info("🔧 Generated \(skills.count) skills from \(filename)", category: .ai)
            return skills
        } catch {
            Logger.error("❌ Skill extraction failed: \(error.localizedDescription)", category: .ai)
            return nil
        }
    }

    /// Generate narrative knowledge cards from extracted text
    private func generateNarrativeCards(
        service: KnowledgeCardExtractionService,
        artifactId: String,
        filename: String,
        extractedText: String
    ) async -> [KnowledgeCard]? {
        guard llmFacade != nil else {
            Logger.warning("⚠️ No LLM facade available for KC extraction", category: .ai)
            return nil
        }

        do {
            let cards = try await service.extractCards(
                documentId: artifactId,
                filename: filename,
                content: extractedText
            )
            Logger.info("📖 Generated \(cards.count) narrative cards from \(filename)", category: .ai)
            return cards
        } catch {
            Logger.error("❌ KC extraction failed: \(error.localizedDescription)", category: .ai)
            return nil
        }
    }
}

// MARK: - Result Type

/// Result of web content extraction
struct WebExtractionResult {
    let id: String
    let url: String
    let title: String?
    let extractedText: String
    let skills: [Skill]
    let narrativeCards: [KnowledgeCard]
}
