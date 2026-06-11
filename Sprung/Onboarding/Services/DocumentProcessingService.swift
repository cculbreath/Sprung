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
    // MARK: - Properties
    private let documentExtractionService: DocumentExtractionService
    private var llmFacade: LLMFacade?

    // Skill bank + narrative KC services
    private let skillBankService: SkillBankService
    private let kcExtractionService: KnowledgeCardExtractionService

    // Anthropic analysis orchestrator (created lazily; requires the facade)
    private var documentAnalysisService: AnthropicDocumentAnalysisService?

    // Supplies the rendered voice-anchor text for the narrative analysis passes
    // (nil when no Phase 1 voice profile / writing samples exist). Set once at
    // container wiring; the analysis service resolves and memoizes it.
    private var voiceAnchorProvider: (@Sendable () async -> String?)?

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

            let analysis = try await runAnalysis(
                documentId: artifactId,
                filename: filename,
                fileURL: fileURL,
                extractedText: extractedText,
                passes: .knowledgeOnly,
                statusCallback: statusCallback
            )
            skills = analysis?.skills
            narrativeCards = analysis?.narrativeCards
            let skillCount = skills?.count ?? 0
            let kcCount = narrativeCards?.count ?? 0
            statusCallback?("Extraction complete: \(skillCount) skills, \(kcCount) narrative cards")
        } else {
            // Steps 3 & 4: Run the full Anthropic analysis pass-set against one
            // cached document prefix: summary first (warms the prompt cache),
            // then skills + narrative cards concurrently, then enrichment.
            statusCallback?("Running document analysis (summary, skills, narrative cards)...")

            let analysis = try await runAnalysis(
                documentId: artifactId,
                filename: filename,
                fileURL: fileURL,
                extractedText: extractedText,
                passes: .all,
                statusCallback: statusCallback
            )
            documentSummary = analysis?.summary ?? DocumentSummary.fallback(from: extractedText, filename: filename)
            skills = analysis?.skills
            narrativeCards = analysis?.narrativeCards

            let summaryChars = documentSummary?.summary.count ?? 0
            let skillCount = skills?.count ?? 0
            let kcCount = narrativeCards?.count ?? 0
            statusCallback?("Summary (\(summaryChars) chars) + \(skillCount) skills + \(kcCount) narrative cards complete")
            Logger.info("Document analysis complete: summary=\(summaryChars) chars, skills=\(skillCount), KCs=\(kcCount)", category: .ai)
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
                byCategory[skill.category, default: 0] += 1
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
        if !combinedMetadata.dictionaryValue.isEmpty {
            artifactRecord["metadata"] = combinedMetadata
        }
        Logger.info("📦 Artifact record created: \(artifactId)", category: .ai)
        return artifactRecord
    }

    // MARK: - Anthropic Analysis

    /// Install the voice-anchor provider used by the narrative analysis passes.
    /// Drops any previously memoized analysis service so the next analysis
    /// picks the provider up.
    func setVoiceAnchorProvider(_ provider: @escaping @Sendable () async -> String?) {
        voiceAnchorProvider = provider
        documentAnalysisService = nil
    }

    private func getOrCreateAnalysisService() -> AnthropicDocumentAnalysisService? {
        if let service = documentAnalysisService { return service }
        guard let facade = llmFacade else { return nil }
        let service = AnthropicDocumentAnalysisService(
            llmFacade: facade,
            skillBankService: skillBankService,
            kcExtractionService: kcExtractionService,
            voiceAnchorProvider: voiceAnchorProvider
        )
        documentAnalysisService = service
        return service
    }

    /// Run the Anthropic document-analysis pass-set for a document.
    ///
    /// PDFs are analyzed as actual documents (Files API document blocks) so every
    /// pass sees figures, tables, and layout. Other sources use their extracted
    /// text (capped centrally by the analysis service) in a single pass.
    ///
    /// Throws `ModelConfigurationError` (so the UI can surface the model picker)
    /// and `PDFPreflightError` (encrypted/unpreparable PDFs). Other analysis
    /// failures degrade gracefully: the artifact is stored without
    /// summary/cards/skills and the failure is logged.
    private func runAnalysis(
        documentId: String,
        filename: String,
        fileURL: URL?,
        extractedText: String,
        passes: AnthropicDocumentAnalysisService.PassSelection,
        statusCallback: (@Sendable (String) -> Void)? = nil
    ) async throws -> AnthropicDocumentAnalysisService.AnalysisResult? {
        guard let analysisService = getOrCreateAnalysisService() else {
            Logger.warning("⚠️ LLMFacade not configured, skipping document analysis for \(filename)", category: .ai)
            return nil
        }

        do {
            if let fileURL, fileURL.pathExtension.lowercased() == "pdf" {
                let pdfData = try Data(contentsOf: fileURL)
                return try await analysisService.analyzePDF(
                    documentId: documentId,
                    filename: filename,
                    pdfData: pdfData,
                    passes: passes,
                    statusCallback: statusCallback
                )
            }
            return try await analysisService.analyzeText(
                documentId: documentId,
                filename: filename,
                text: extractedText,
                passes: passes,
                statusCallback: statusCallback
            )
        } catch let error as ModelConfigurationError {
            throw error
        } catch let error as PDFPreflightError {
            throw error
        } catch {
            Logger.warning("⚠️ Document analysis failed for \(filename): \(error.localizedDescription)", category: .ai)
            return nil
        }
    }

    // MARK: - Regeneration Methods

    /// Run the analysis pass-set for an existing artifact's stored text.
    /// Regeneration operates on the stored extracted content (the raw file may
    /// no longer be available), so it always uses the text path.
    private func regenerate(
        _ artifact: ArtifactRecord,
        passes: AnthropicDocumentAnalysisService.PassSelection
    ) async -> AnthropicDocumentAnalysisService.AnalysisResult? {
        let filename = artifact.filename
        do {
            return try await runAnalysis(
                documentId: artifact.idString,
                filename: filename,
                fileURL: nil,
                extractedText: artifact.extractedContent,
                passes: passes
            )
        } catch {
            Logger.warning("Regeneration analysis failed for \(filename): \(error.localizedDescription)", category: .ai)
            return nil
        }
    }

    /// Write regenerated results back to the artifact on the MainActor.
    private func applyRegenerationResults(
        _ result: AnthropicDocumentAnalysisService.AnalysisResult?,
        to artifact: ArtifactRecord
    ) async {
        let filename = artifact.filename
        await MainActor.run { [artifact] in
            if let summary = result?.summary {
                artifact.summary = summary.summary
                artifact.briefDescription = summary.briefDescription
                Logger.info("Summary regenerated for \(filename): \(summary.summary.count) chars", category: .ai)
            }

            // Note: Skill/KnowledgeCard models have explicit CodingKeys for snake_case - no conversion needed
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601

            if let skills = result?.skills,
               let skillsData = try? encoder.encode(skills),
               let skillsString = String(data: skillsData, encoding: .utf8) {
                artifact.skillsJSON = skillsString
                Logger.info("Skills regenerated for \(filename): \(skills.count) skills", category: .ai)
            }

            if let cards = result?.narrativeCards,
               let cardsData = try? encoder.encode(cards),
               let cardsString = String(data: cardsData, encoding: .utf8) {
                artifact.narrativeCardsJSON = cardsString
                Logger.info("Narrative cards regenerated for \(filename): \(cards.count) cards", category: .ai)
            }
        }
    }

    /// Regenerate summary only for an existing artifact.
    /// Updates the artifact's summary and briefDescription directly.
    func generateSummaryForExistingArtifact(_ artifact: ArtifactRecord) async {
        Logger.info("Regenerating summary for: \(artifact.filename)", category: .ai)
        let result = await regenerate(artifact, passes: .summaryOnly)
        if result?.summary == nil {
            Logger.warning("Failed to regenerate summary for: \(artifact.filename)", category: .ai)
        }
        await applyRegenerationResults(result, to: artifact)
    }

    /// Regenerate knowledge extraction for an existing artifact.
    /// Updates the artifact's skillsJSON and narrativeCardsJSON directly.
    func generateKnowledgeExtractionForExistingArtifact(_ artifact: ArtifactRecord) async {
        Logger.info("Regenerating knowledge extraction for: \(artifact.filename)", category: .ai)
        let result = await regenerate(artifact, passes: .knowledgeOnly)
        await applyRegenerationResults(result, to: artifact)
        Logger.info("✅ Knowledge extraction regeneration complete for: \(artifact.filename)", category: .ai)
    }

    /// Regenerate skills only for an existing artifact.
    /// Updates the artifact's skillsJSON directly.
    func generateSkillsOnlyForExistingArtifact(_ artifact: ArtifactRecord) async {
        Logger.info("Regenerating skills only for: \(artifact.filename)", category: .ai)
        let passes = AnthropicDocumentAnalysisService.PassSelection(
            summary: false, skills: true, narrativeCards: false, enrichment: false
        )
        let result = await regenerate(artifact, passes: passes)
        await applyRegenerationResults(result, to: artifact)
        Logger.info("✅ Skills regeneration complete for: \(artifact.filename)", category: .ai)
    }

    /// Regenerate narrative cards only for an existing artifact.
    /// Updates the artifact's narrativeCardsJSON directly.
    func generateNarrativeCardsOnlyForExistingArtifact(_ artifact: ArtifactRecord) async {
        Logger.info("Regenerating narrative cards only for: \(artifact.filename)", category: .ai)
        let passes = AnthropicDocumentAnalysisService.PassSelection(
            summary: false, skills: false, narrativeCards: true, enrichment: true
        )
        let result = await regenerate(artifact, passes: passes)
        await applyRegenerationResults(result, to: artifact)
        Logger.info("✅ Narrative cards regeneration complete for: \(artifact.filename)", category: .ai)
    }

    /// Regenerate both summary and knowledge extraction for an existing artifact.
    func generateSummaryAndKnowledgeExtractionForExistingArtifact(_ artifact: ArtifactRecord) async {
        Logger.info("Regenerating summary + knowledge extraction for: \(artifact.filename)", category: .ai)
        let result = await regenerate(artifact, passes: .all)
        await applyRegenerationResults(result, to: artifact)
        Logger.info("✅ Summary + knowledge extraction regeneration complete for: \(artifact.filename)", category: .ai)
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
                modelId: modelId
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
