//
//  DocumentProcessingService.swift
//  Sprung
//
//  Service for processing uploaded documents (PDFs, etc.).
//  Contains business logic for extraction and artifact creation.
//
import Foundation
import SwiftyJSON
/// Service that handles document processing workflow
actor DocumentProcessingService {
    // MARK: - Constants

    /// Max characters for extraction input (truncate very long documents)
    private static let extractionInputLimit = 200_000

    // MARK: - Properties
    private let documentExtractionService: DocumentExtractionService
    private var llmFacade: LLMFacade?

    // Skill bank + narrative KC services
    private let skillBankService: SkillBankService
    private let kcExtractionService: KnowledgeCardExtractionService

    // MARK: - Initialization
    init(
        documentExtractionService: DocumentExtractionService,
        llmFacade: LLMFacade? = nil,
        skillBankService: SkillBankService? = nil,
        kcExtractionService: KnowledgeCardExtractionService? = nil
    ) {
        self.documentExtractionService = documentExtractionService
        self.llmFacade = llmFacade
        self.skillBankService = skillBankService ?? SkillBankService(llmFacade: llmFacade)
        self.kcExtractionService = kcExtractionService ?? KnowledgeCardExtractionService(llmFacade: llmFacade)
        Logger.info("📄 DocumentProcessingService initialized", category: .ai)
    }

    // MARK: - Public API
    /// Process a document file and return an artifact record
    /// Note: The fileURL is expected to already be in storage (copied by UploadInteractionHandler)
    /// - Parameter displayFilename: Original filename for user-facing messages (storage URL may have UUID prefix)
    func processDocument(
        fileURL: URL,
        documentType: String,
        callId: String?,
        metadata: JSON,
        displayFilename: String? = nil,
        statusCallback: (@Sendable (String) -> Void)? = nil
    ) async throws -> JSON {
        // Use displayFilename if provided, otherwise fall back to URL's lastPathComponent
        let filename = displayFilename ?? fileURL.lastPathComponent
        Logger.info("📄 Processing document: \(filename)", category: .ai)

        // File is already in storage (copied by UploadInteractionHandler before this is called)
        // Just use it directly - no need to copy again
        let storagePath = fileURL.path
        Logger.info("💾 Document location: \(storagePath)", category: .ai)

        // Step 2: Extract text using intelligent PDF extraction router
        Logger.info("🔍 Extracting text from: \(filename)", category: .ai)
        statusCallback?("Extracting text from \(filename)...")

        let extractionRequest = DocumentExtractionService.ExtractionRequest(
            fileURL: fileURL,
            purpose: documentType,
            returnTypes: ["text"],
            autoPersist: false,
            timeout: nil,
            displayFilename: filename
        )
        // Create progress handler that maps to status callback
        let progressHandler: ExtractionProgressHandler? = statusCallback.map { callback in
            { @Sendable update in
                if let detail = update.detail {
                    callback(detail)
                }
            }
        }
        let extractionResult = try await documentExtractionService.extract(
            using: extractionRequest,
            progress: progressHandler
        )
        guard let artifact = extractionResult.artifact else {
            throw NSError(
                domain: "DocumentProcessing",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No artifact produced from extraction"]
            )
        }
        let extractedText = artifact.extractedContent
        let extractedTitle = artifact.title
        let artifactId = artifact.id
        Logger.info("✅ Text extraction completed: \(artifactId)", category: .ai)

        // Determine which post-processing steps to run based on document type
        // - Writing samples: skip both summary and knowledge extraction (only need text extraction)
        // - Resumes: skip summary (full text sent to LLM), but do knowledge extraction
        // - Other documents: do both summary and knowledge extraction
        let isWritingSample = documentType == "writingSample" || documentType == "writing_sample"
        let isResume = documentType == "resume"

        let documentSummary: DocumentSummary?
        let skills: [Skill]?
        let narrativeCards: [KnowledgeCard]?

        // For writing samples, generate a descriptive name
        var writingSampleName: String?
        var writingSampleType: String?

        if isWritingSample {
            // Writing samples: generate descriptive name, skip summary/knowledge extraction
            statusCallback?("Generating descriptive name for writing sample...")
            Logger.info("📝 Generating descriptive name for writing sample: \(filename)", category: .ai)

            // Generate a descriptive name for the writing sample
            writingSampleName = try await generateWritingSampleName(
                extractedText: extractedText,
                filename: filename
            )
            writingSampleType = inferWritingType(from: extractedText)

            if let name = writingSampleName {
                Logger.info("📝 Writing sample named: '\(name)' (was: \(filename))", category: .ai)
            }

            statusCallback?("Writing sample extracted")
            documentSummary = nil
            skills = nil
            narrativeCards = nil
        } else if isResume {
            // Resumes skip summary (full text sent to LLM via interviewContext)
            // but still generate skills and narrative cards
            statusCallback?("Generating knowledge extraction for resume...")
            Logger.info("📝 Resume: skipping summary, generating skills + narrative cards: \(filename)", category: .ai)
            documentSummary = nil

            // Run skill and narrative card extraction in parallel
            async let skillsTask: [Skill]? = generateSkills(
                artifactId: artifactId,
                filename: filename,
                extractedText: extractedText
            )
            async let cardsTask: [KnowledgeCard]? = generateNarrativeCards(
                artifactId: artifactId,
                filename: filename,
                extractedText: extractedText
            )

            (skills, narrativeCards) = await (skillsTask, cardsTask)
            let skillCount = skills?.count ?? 0
            let kcCount = narrativeCards?.count ?? 0
            statusCallback?("Extraction complete: \(skillCount) skills, \(kcCount) narrative cards")
        } else {
            // Steps 3 & 4: Generate summary and knowledge extraction IN PARALLEL
            // All are independent LLM calls that only need extractedText
            statusCallback?("Running summary + knowledge extraction in parallel...")

            // Launch all tasks in parallel
            async let summaryTask: DocumentSummary? = generateSummary(
                extractedText: extractedText,
                filename: filename,
                facade: llmFacade
            )
            async let skillsTask: [Skill]? = generateSkills(
                artifactId: artifactId,
                filename: filename,
                extractedText: extractedText
            )
            async let cardsTask: [KnowledgeCard]? = generateNarrativeCards(
                artifactId: artifactId,
                filename: filename,
                extractedText: extractedText
            )

            // Await all results
            (documentSummary, skills, narrativeCards) = await (summaryTask, skillsTask, cardsTask)
            let summaryChars = documentSummary?.summary.count ?? 0
            let skillCount = skills?.count ?? 0
            let kcCount = narrativeCards?.count ?? 0
            statusCallback?("Summary (\(summaryChars) chars) + \(skillCount) skills + \(kcCount) narrative cards complete")
            Logger.info("Parallel processing complete: summary=\(summaryChars) chars, skills=\(skillCount), KCs=\(kcCount)", category: .ai)
        }

        // Step 5: Create artifact record
        var artifactRecord = JSON()
        artifactRecord["id"].string = artifactId
        artifactRecord["filename"].string = filename
        if let title = extractedTitle {
            artifactRecord["title"].string = title
        }
        artifactRecord["documentType"].string = documentType

        // Set interviewContext for uploads that should have full content sent to LLM
        // (writing samples and resumes - helps with voice matching)
        let interviewContextTypes = ["writingSample", "writing_sample", "resume"]
        artifactRecord["interviewContext"].bool = interviewContextTypes.contains(documentType)

        artifactRecord["rawFilePath"].string = storagePath
        artifactRecord["extractedText"].string = extractedText

        // Two-pass extraction fields (PDFs) - stored in metadata for access via ArtifactRecord
        var graphicsMeta = JSON()
        if let plainText = artifact.plainTextContent {
            graphicsMeta["plainTextContent"].string = plainText
        }
        if let graphics = artifact.graphicsContent {
            graphicsMeta["graphicsContent"].string = graphics
        }
        graphicsMeta["graphicsExtractionStatus"].string = artifact.graphicsExtractionStatus.rawValue
        if let graphicsError = artifact.metadata["graphicsExtractionError"] as? String {
            graphicsMeta["graphicsExtractionError"].string = graphicsError
        }

        // Determine content type from file extension
        let contentType: String
        switch fileURL.pathExtension.lowercased() {
        case "pdf": contentType = "application/pdf"
        case "docx": contentType = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "doc": contentType = "application/msword"
        case "txt": contentType = "text/plain"
        default: contentType = "application/octet-stream"
        }
        artifactRecord["contentType"].string = contentType
        artifactRecord["sizeBytes"].int = artifact.sizeInBytes
        artifactRecord["sha256"].string = artifact.sha256
        artifactRecord["createdAt"].string = ISO8601DateFormatter().string(from: Date())
        if let callId = callId {
            artifactRecord["originatingCallId"].string = callId
        }
        // Add summary if generated
        if let summary = documentSummary {
            artifactRecord["summary"].string = summary.summary
            artifactRecord["briefDescription"].string = summary.briefDescription
            artifactRecord["summaryGeneratedAt"].string = ISO8601DateFormatter().string(from: Date())
            // Store structured summary fields in metadata
            var summaryMeta = JSON()
            summaryMeta["documentType"].string = summary.documentType
            summaryMeta["briefDescription"].string = summary.briefDescription
            summaryMeta["timePeriod"].string = summary.timePeriod
            summaryMeta["companies"].arrayObject = summary.companies
            summaryMeta["roles"].arrayObject = summary.roles
            summaryMeta["skills"].arrayObject = summary.skills
            summaryMeta["achievements"].arrayObject = summary.achievements
            summaryMeta["relevanceHints"].string = summary.relevanceHints
            artifactRecord["summaryMetadata"] = summaryMeta
        }

        // Store skill bank extraction
        if let skillsResult = skills {
            let encoder = JSONEncoder()
            // Note: Skill model has explicit CodingKeys for snake_case - no conversion needed
            encoder.dateEncodingStrategy = .iso8601
            if let skillsData = try? encoder.encode(skillsResult),
               let skillsString = String(data: skillsData, encoding: .utf8) {
                artifactRecord["skills"].string = skillsString
            }

            // Add skills stats
            var skillsStats = JSON()
            skillsStats["total"].int = skillsResult.count
            var byCategory: [String: Int] = [:]
            for skill in skillsResult {
                byCategory[skill.category.rawValue, default: 0] += 1
            }
            skillsStats["byCategory"].dictionaryObject = byCategory as [String: Any]
            artifactRecord["skillsStats"] = skillsStats
        }

        // Store narrative knowledge cards
        if let cardsResult = narrativeCards {
            let encoder = JSONEncoder()
            // Note: KnowledgeCard model has explicit CodingKeys for snake_case - no conversion needed
            encoder.dateEncodingStrategy = .iso8601
            if let cardsData = try? encoder.encode(cardsResult),
               let cardsString = String(data: cardsData, encoding: .utf8) {
                artifactRecord["narrativeCards"].string = cardsString
            }

            // Add narrative cards stats
            var kcStats = JSON()
            kcStats["total"].int = cardsResult.count
            var byType: [String: Int] = [:]
            for card in cardsResult {
                byType[card.cardType?.rawValue ?? "other", default: 0] += 1
            }
            kcStats["byType"].dictionaryObject = byType as [String: Any]
            artifactRecord["narrativeCards_stats"] = kcStats
        }

        // Persist both upload metadata and extraction metadata
        var combinedMetadata = metadata
        if !artifact.metadata.isEmpty {
            combinedMetadata["extraction"] = JSON(artifact.metadata)
        }
        // Add writing sample name and type if generated
        if let name = writingSampleName {
            combinedMetadata["name"].string = name
        }
        if let writingType = writingSampleType {
            combinedMetadata["writing_type"].string = writingType
        }
        // Add graphics extraction fields to metadata (for ArtifactRecord access)
        for (key, value) in graphicsMeta.dictionaryValue {
            combinedMetadata[key] = value
        }
        if !combinedMetadata.dictionaryValue.isEmpty {
            artifactRecord["metadata"] = combinedMetadata
        }
        Logger.info("📦 Artifact record created: \(artifactId)", category: .ai)
        return artifactRecord
    }

    // MARK: - Parallel Processing Helpers

    /// Generate document summary (runs in parallel with knowledge extraction)
    private func generateSummary(
        extractedText: String,
        filename: String,
        facade: LLMFacade?
    ) async -> DocumentSummary? {
        guard let facade = facade else {
            Logger.warning("⚠️ LLMFacade not configured, using fallback summary for \(filename)", category: .ai)
            return DocumentSummary.fallback(from: extractedText, filename: filename)
        }
        do {
            let summary = try await facade.generateDocumentSummary(
                content: extractedText,
                filename: filename
            )
            Logger.info("✅ Summary generated for \(filename) (\(summary.summary.count) chars)", category: .ai)
            return summary
        } catch {
            Logger.warning("⚠️ Summary generation failed for \(filename): \(error.localizedDescription)", category: .ai)
            return DocumentSummary.fallback(from: extractedText, filename: filename)
        }
    }

    /// Generate skills using SkillBankService
    private func generateSkills(
        artifactId: String,
        filename: String,
        extractedText: String
    ) async -> [Skill]? {
        let skillInput = String(extractedText.prefix(Self.extractionInputLimit))

        do {
            Logger.info("🔧 Generating skills extraction (\(skillInput.count) chars)", category: .ai)
            return try await skillBankService.extractSkills(
                documentId: artifactId,
                filename: filename,
                content: skillInput
            )
        } catch {
            Logger.warning("🔧 Skills extraction failed: \(error.localizedDescription)", category: .ai)
            return nil
        }
    }

    /// Generate narrative knowledge cards using KCExtractionService
    private func generateNarrativeCards(
        artifactId: String,
        filename: String,
        extractedText: String
    ) async -> [KnowledgeCard]? {
        let kcInput = String(extractedText.prefix(Self.extractionInputLimit))

        do {
            Logger.info("📖 Generating narrative cards (\(kcInput.count) chars)", category: .ai)
            return try await kcExtractionService.extractCards(
                documentId: artifactId,
                filename: filename,
                content: kcInput
            )
        } catch {
            Logger.warning("📖 Narrative card extraction failed: \(error.localizedDescription)", category: .ai)
            return nil
        }
    }

    // MARK: - Regeneration Methods

    /// Regenerate summary only for an existing artifact.
    /// Updates the artifact's summary and briefDescription directly.
    func generateSummaryForExistingArtifact(_ artifact: ArtifactRecord) async {
        let filename = artifact.filename
        let extractedText = artifact.extractedContent
        let facade = self.llmFacade

        Logger.info("Regenerating summary for: \(filename)", category: .ai)

        guard let facade = facade else {
            Logger.warning("⚠️ LLMFacade not configured, skipping summary for \(filename)", category: .ai)
            return
        }

        if let result = await generateSummary(extractedText: extractedText, filename: filename, facade: facade) {
            // Transfer to MainActor for SwiftData model updates
            await MainActor.run { [artifact] in
                artifact.summary = result.summary
                artifact.briefDescription = result.briefDescription
                Logger.info("Summary regenerated for \(filename): \(result.summary.count) chars", category: .ai)
            }
        } else {
            Logger.warning("Failed to regenerate summary for: \(filename)", category: .ai)
        }
    }

    /// Regenerate knowledge extraction for an existing artifact.
    /// Updates the artifact's skillsJSON and narrativeCardsJSON directly.
    func generateKnowledgeExtractionForExistingArtifact(_ artifact: ArtifactRecord) async {
        let artifactId = artifact.idString
        let filename = artifact.filename
        let extractedText = artifact.extractedContent

        Logger.info("Regenerating knowledge extraction for: \(filename)", category: .ai)

        // Run skill and narrative card extraction in parallel
        async let skillsTask: [Skill]? = generateSkills(
            artifactId: artifactId,
            filename: filename,
            extractedText: extractedText
        )
        async let cardsTask: [KnowledgeCard]? = generateNarrativeCards(
            artifactId: artifactId,
            filename: filename,
            extractedText: extractedText
        )

        let (skills, narrativeCards) = await (skillsTask, cardsTask)

        // Transfer to MainActor for SwiftData model updates
        await MainActor.run { [artifact] in
            // Note: Skill/KnowledgeCard models have explicit CodingKeys for snake_case - no conversion needed
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601

            if let skillsResult = skills,
               let skillsData = try? encoder.encode(skillsResult),
               let skillsString = String(data: skillsData, encoding: .utf8) {
                artifact.skillsJSON = skillsString
                Logger.info("Skills regenerated for \(filename): \(skillsResult.count) skills", category: .ai)
            }

            if let cardsResult = narrativeCards,
               let cardsData = try? encoder.encode(cardsResult),
               let cardsString = String(data: cardsData, encoding: .utf8) {
                artifact.narrativeCardsJSON = cardsString
                Logger.info("Narrative cards regenerated for \(filename): \(cardsResult.count) cards", category: .ai)
            }
        }

        Logger.info("✅ Knowledge extraction regeneration complete for: \(filename)", category: .ai)
    }

    /// Regenerate skills only for an existing artifact.
    /// Updates the artifact's skillsJSON directly.
    func generateSkillsOnlyForExistingArtifact(_ artifact: ArtifactRecord) async {
        let artifactId = artifact.idString
        let filename = artifact.filename
        let extractedText = artifact.extractedContent

        Logger.info("Regenerating skills only for: \(filename)", category: .ai)

        let skills = await generateSkills(
            artifactId: artifactId,
            filename: filename,
            extractedText: extractedText
        )

        await MainActor.run { [artifact] in
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601

            if let skillsResult = skills,
               let skillsData = try? encoder.encode(skillsResult),
               let skillsString = String(data: skillsData, encoding: .utf8) {
                artifact.skillsJSON = skillsString
                Logger.info("Skills regenerated for \(filename): \(skillsResult.count) skills", category: .ai)
            }
        }

        Logger.info("✅ Skills regeneration complete for: \(filename)", category: .ai)
    }

    /// Regenerate narrative cards only for an existing artifact.
    /// Updates the artifact's narrativeCardsJSON directly.
    func generateNarrativeCardsOnlyForExistingArtifact(_ artifact: ArtifactRecord) async {
        let artifactId = artifact.idString
        let filename = artifact.filename
        let extractedText = artifact.extractedContent

        Logger.info("Regenerating narrative cards only for: \(filename)", category: .ai)

        let narrativeCards = await generateNarrativeCards(
            artifactId: artifactId,
            filename: filename,
            extractedText: extractedText
        )

        await MainActor.run { [artifact] in
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601

            if let cardsResult = narrativeCards,
               let cardsData = try? encoder.encode(cardsResult),
               let cardsString = String(data: cardsData, encoding: .utf8) {
                artifact.narrativeCardsJSON = cardsString
                Logger.info("Narrative cards regenerated for \(filename): \(cardsResult.count) cards", category: .ai)
            }
        }

        Logger.info("✅ Narrative cards regeneration complete for: \(filename)", category: .ai)
    }

    /// Regenerate both summary and knowledge extraction for an existing artifact.
    func generateSummaryAndKnowledgeExtractionForExistingArtifact(_ artifact: ArtifactRecord) async {
        let filename = artifact.filename
        let extractedText = artifact.extractedContent
        let artifactId = artifact.idString

        // Capture actor-isolated properties before spawning tasks
        let facade = self.llmFacade

        Logger.info("Regenerating summary + knowledge extraction for: \(filename)", category: .ai)

        // Run summary, skills, and narrative cards in parallel
        async let summaryTask: DocumentSummary? = {
            guard let facade = facade else { return nil }
            return await generateSummary(extractedText: extractedText, filename: filename, facade: facade)
        }()

        async let skillsTask: [Skill]? = generateSkills(
            artifactId: artifactId,
            filename: filename,
            extractedText: extractedText
        )

        async let cardsTask: [KnowledgeCard]? = generateNarrativeCards(
            artifactId: artifactId,
            filename: filename,
            extractedText: extractedText
        )

        let (summaryResult, skillsResult, narrativeCardsResult) = await (summaryTask, skillsTask, cardsTask)

        // Transfer to MainActor for SwiftData model updates
        await MainActor.run { [artifact] in
            if let summary = summaryResult {
                artifact.summary = summary.summary
                artifact.briefDescription = summary.briefDescription
                Logger.info("Summary regenerated for \(filename): \(summary.summary.count) chars", category: .ai)
            }

            // Note: Skill/KnowledgeCard models have explicit CodingKeys for snake_case - no conversion needed
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601

            if let skills = skillsResult,
               let skillsData = try? encoder.encode(skills),
               let skillsString = String(data: skillsData, encoding: .utf8) {
                artifact.skillsJSON = skillsString
                Logger.info("Skills regenerated for \(filename): \(skills.count) skills", category: .ai)
            }

            if let cards = narrativeCardsResult,
               let cardsData = try? encoder.encode(cards),
               let cardsString = String(data: cardsData, encoding: .utf8) {
                artifact.narrativeCardsJSON = cardsString
                Logger.info("Narrative cards regenerated for \(filename): \(cards.count) cards", category: .ai)
            }
        }

        Logger.info("✅ Summary + knowledge extraction regeneration complete for: \(filename)", category: .ai)
    }

    // MARK: - Writing Sample Naming

    /// Generate a descriptive name for a writing sample using a quick LLM call.
    /// Falls back to nil if LLM is unavailable or call fails.
    /// Throws ModelConfigurationError if no model is configured.
    private func generateWritingSampleName(
        extractedText: String,
        filename: String
    ) async throws -> String? {
        guard let facade = llmFacade else {
            Logger.warning("⚠️ LLM not available for writing sample naming", category: .ai)
            return nil
        }

        // Use first 2000 chars for context (enough to understand the document)
        let textSample = String(extractedText.prefix(2000))

        let prompt = """
        You are a document naming assistant. Based on this writing sample, generate a short descriptive name (3-6 words) that captures what it is.
        Examples: "Senior Developer Cover Letter", "Marketing Manager Application", "Software Engineer Introduction Email"

        Writing sample:
        \(textSample)

        Respond with ONLY the descriptive name, nothing else.
        """

        // Use KC agent model (fast haiku) for this simple task
        guard let modelId = UserDefaults.standard.string(forKey: "onboardingKCAgentModelId"), !modelId.isEmpty else {
            throw ModelConfigurationError.modelNotConfigured(
                settingKey: "onboardingKCAgentModelId",
                operationName: "Document Name Generation"
            )
        }

        do {
            let response = try await facade.executeText(
                prompt: prompt,
                modelId: modelId,
                temperature: 0.3
            )

            let name = response.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

            // Validate the name is reasonable (not too long, not empty)
            if name.count >= 5 && name.count <= 80 {
                return name
            }

            Logger.warning("⚠️ Generated name was invalid: '\(name)'", category: .ai)
            return nil
        } catch {
            Logger.warning("⚠️ Failed to generate writing sample name: \(error.localizedDescription)", category: .ai)
            return nil
        }
    }

    /// Infer the writing type from the content.
    private func inferWritingType(from text: String) -> String {
        let lowercased = text.lowercased()

        if lowercased.contains("dear hiring") || lowercased.contains("dear recruiter") ||
           lowercased.contains("i am writing to apply") || lowercased.contains("application for") {
            return "cover_letter"
        }

        if lowercased.contains("from:") && lowercased.contains("to:") && lowercased.contains("subject:") {
            return "email"
        }

        if lowercased.contains("executive summary") || lowercased.contains("project proposal") {
            return "proposal"
        }

        if lowercased.contains("introduction") && lowercased.contains("conclusion") {
            return "essay"
        }

        return "document"
    }
}
