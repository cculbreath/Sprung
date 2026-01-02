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

    /// Max characters for inventory input (truncate very long documents)
    private static let inventoryInputLimit = 200_000

    // MARK: - Properties
    private let documentExtractionService: DocumentExtractionService
    private var llmFacade: LLMFacade?

    // Card pipeline service (inventory determines document type itself)
    private let inventoryService: CardInventoryService

    // MARK: - Initialization
    init(
        documentExtractionService: DocumentExtractionService,
        llmFacade: LLMFacade? = nil,
        inventoryService: CardInventoryService? = nil
    ) {
        self.documentExtractionService = documentExtractionService
        self.llmFacade = llmFacade
        self.inventoryService = inventoryService ?? CardInventoryService(llmFacade: llmFacade)
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

        // Skip summary and card inventory for writing samples - they only need text extraction
        let isWritingSample = documentType == "writing_sample"

        let documentSummary: DocumentSummary?
        let inventory: DocumentInventory?

        if isWritingSample {
            // Writing samples don't need summary or card inventory
            statusCallback?("Writing sample extracted - skipping summary/inventory")
            Logger.info("📝 Skipping summary/inventory for writing sample: \(filename)", category: .ai)
            documentSummary = nil
            inventory = nil
        } else {
            // Steps 3 & 4: Generate summary and card inventory IN PARALLEL
            // Both are independent LLM calls that only need extractedText
            // (PDF-based inventory is no longer used since we have reliable text from vision fallback)
            statusCallback?("Running summary + card inventory in parallel...")

            // Launch both tasks in parallel
            async let summaryTask: DocumentSummary? = generateSummary(
                extractedText: extractedText,
                filename: filename,
                facade: llmFacade
            )
            async let inventoryTask: DocumentInventory? = generateInventory(
                artifactId: artifactId,
                filename: filename,
                extractedText: extractedText
            )

            // Await both results
            (documentSummary, inventory) = await (summaryTask, inventoryTask)
            let summaryChars = documentSummary?.summary.count ?? 0
            let cardCount = inventory?.proposedCards.count ?? 0
            statusCallback?("Summary (\(summaryChars) chars) + \(cardCount) cards complete")
            Logger.info("Parallel processing complete: summary=\(summaryChars) chars, cards=\(cardCount)", category: .ai)
        }

        // Step 5: Create artifact record
        var artifactRecord = JSON()
        artifactRecord["id"].string = artifactId
        artifactRecord["filename"].string = filename
        if let title = extractedTitle {
            artifactRecord["title"].string = title
        }
        artifactRecord["document_type"].string = documentType

        // Set interview_context for uploads that should have full content sent to LLM
        // (writing samples and resumes - helps with voice matching)
        let interviewContextTypes = ["writing_sample", "resume"]
        artifactRecord["interview_context"].bool = interviewContextTypes.contains(documentType)

        artifactRecord["storage_path"].string = storagePath
        artifactRecord["extracted_text"].string = extractedText

        // Two-pass extraction fields (PDFs) - stored in metadata for access via ArtifactRecord
        var graphicsMeta = JSON()
        if let plainText = artifact.plainTextContent {
            graphicsMeta["plain_text_content"].string = plainText
        }
        if let graphics = artifact.graphicsContent {
            graphicsMeta["graphics_content"].string = graphics
        }
        graphicsMeta["graphics_extraction_status"].string = artifact.graphicsExtractionStatus.rawValue
        if let graphicsError = artifact.metadata["graphics_extraction_error"] as? String {
            graphicsMeta["graphics_extraction_error"].string = graphicsError
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
        artifactRecord["content_type"].string = contentType
        artifactRecord["size_bytes"].int = artifact.sizeInBytes
        artifactRecord["sha256"].string = artifact.sha256
        artifactRecord["created_at"].string = ISO8601DateFormatter().string(from: Date())
        if let callId = callId {
            artifactRecord["originating_call_id"].string = callId
        }
        // Add summary if generated
        if let summary = documentSummary {
            artifactRecord["summary"].string = summary.summary
            artifactRecord["brief_description"].string = summary.briefDescription
            artifactRecord["summary_generated_at"].string = ISO8601DateFormatter().string(from: Date())
            // Store structured summary fields in metadata
            var summaryMeta = JSON()
            summaryMeta["document_type"].string = summary.documentType
            summaryMeta["brief_description"].string = summary.briefDescription
            summaryMeta["time_period"].string = summary.timePeriod
            summaryMeta["companies"].arrayObject = summary.companies
            summaryMeta["roles"].arrayObject = summary.roles
            summaryMeta["skills"].arrayObject = summary.skills
            summaryMeta["achievements"].arrayObject = summary.achievements
            summaryMeta["relevance_hints"].string = summary.relevanceHints
            artifactRecord["summary_metadata"] = summaryMeta
        }
        // Store card inventory
        if let inventoryResult = inventory {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.dateEncodingStrategy = .iso8601
            if let inventoryData = try? encoder.encode(inventoryResult),
               let inventoryString = String(data: inventoryData, encoding: .utf8) {
                artifactRecord["card_inventory"].string = inventoryString
            }

            // Add document type detected by inventory
            artifactRecord["document_type_detected"].string = inventoryResult.documentType

            // Add inventory stats convenience fields for LLM message display
            var inventoryStats = JSON()
            inventoryStats["total"].int = inventoryResult.proposedCards.count

            // Count cards by type
            var byType: [String: Int] = [:]
            var primaryCount = 0
            var supportingCount = 0
            for card in inventoryResult.proposedCards {
                let typeKey = card.cardType.rawValue
                byType[typeKey, default: 0] += 1

                // Count primary vs supporting based on evidence strength
                if card.evidenceStrength == .primary {
                    primaryCount += 1
                } else {
                    supportingCount += 1
                }
            }
            inventoryStats["by_type"].dictionaryObject = byType as [String: Any]
            inventoryStats["primary_count"].int = primaryCount
            inventoryStats["supporting_count"].int = supportingCount

            artifactRecord["inventory_stats"] = inventoryStats
        }
        // Persist both upload metadata and extraction metadata
        var combinedMetadata = metadata
        if !artifact.metadata.isEmpty {
            combinedMetadata["extraction"] = JSON(artifact.metadata)
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

    /// Generate document summary (runs in parallel with inventory)
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

    /// Generate card inventory (runs in parallel with summary)
    /// Always uses text-based extraction since upstream PDF router ensures quality.
    private func generateInventory(
        artifactId: String,
        filename: String,
        extractedText: String
    ) async -> DocumentInventory? {
        // Truncate if very long - cards don't need every word
        let inventoryInput = String(extractedText.prefix(Self.inventoryInputLimit))

        do {
            Logger.info("Generating text-based inventory (\(inventoryInput.count) chars)", category: .ai)
            return try await inventoryService.inventoryDocument(
                documentId: artifactId,
                filename: filename,
                content: inventoryInput
            )
        } catch {
            Logger.warning("Card inventory generation failed: \(error.localizedDescription)", category: .ai)
            return nil
        }
    }

    // MARK: - Inventory Regeneration

    /// Regenerate card inventory for an existing artifact using text-based extraction.
    /// Updates the artifact's cardInventoryJSON directly.
    @MainActor
    func generateInventoryForExistingArtifact(_ artifact: ArtifactRecord) async {
        Logger.info("Regenerating inventory for: \(artifact.filename)", category: .ai)

        let artifactId = artifact.idString
        let filename = artifact.filename
        let extractedText = artifact.extractedContent

        // Generate inventory using text-based extraction
        let inventory = await generateInventory(
            artifactId: artifactId,
            filename: filename,
            extractedText: extractedText
        )

        // Update artifact with new inventory
        if let inventoryResult = inventory {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.dateEncodingStrategy = .iso8601
            if let inventoryData = try? encoder.encode(inventoryResult),
               let inventoryString = String(data: inventoryData, encoding: .utf8) {
                artifact.cardInventoryJSON = inventoryString
                Logger.info("Inventory regenerated for \(filename): \(inventoryResult.proposedCards.count) cards", category: .ai)
            }
        } else {
            Logger.warning("Failed to regenerate inventory for: \(filename)", category: .ai)
        }
    }
}
