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
    private let uploadStorage: OnboardingUploadStorage
    private let dataStore: InterviewDataStore

    // MARK: - Initialization

    init(
        documentExtractionService: DocumentExtractionService,
        uploadStorage: OnboardingUploadStorage,
        dataStore: InterviewDataStore
    ) {
        self.documentExtractionService = documentExtractionService
        self.uploadStorage = uploadStorage
        self.dataStore = dataStore
        Logger.info("📄 DocumentProcessingService initialized", category: .ai)
    }

    // MARK: - Public API

    /// Process a document file and return an artifact record
    func processDocument(
        fileURL: URL,
        documentType: String,
        callId: String?,
        metadata: JSON
    ) async throws -> JSON {
        let filename = fileURL.lastPathComponent

        Logger.info("📄 Processing document: \(filename)", category: .ai)

        // Step 1: Ensure file is saved to storage
        let processedUpload = try uploadStorage.processFile(at: fileURL)
        let storagePath = processedUpload.storageURL.path

        Logger.info("💾 Document saved to: \(storagePath)", category: .ai)

        // Step 2: Extract text using configured model
        let modelId = "google/gemini-2.0-flash-001" // TODO: Get from settings
        Logger.info("🔍 Extracting text with model: \(modelId)", category: .ai)

        let extractionRequest = DocumentExtractionService.ExtractionRequest(
            fileURL: processedUpload.storageURL,
            purpose: documentType,
            returnTypes: ["text"],
            autoPersist: false,
            timeout: nil
        )

        let extractionResult = try await documentExtractionService.extract(
            using: extractionRequest,
            progress: nil
        )

        guard let artifact = extractionResult.artifact else {
            throw NSError(
                domain: "DocumentProcessing",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No artifact produced from extraction"]
            )
        }

        let extractedText = artifact.extractedContent
        let artifactId = artifact.id

        Logger.info("✅ Text extraction completed: \(artifactId)", category: .ai)

        // Step 3: Create artifact record
        var artifactRecord = JSON()
        artifactRecord["id"].string = artifactId
        artifactRecord["filename"].string = filename
        artifactRecord["document_type"].string = documentType
        artifactRecord["storage_path"].string = storagePath
        artifactRecord["extracted_text"].string = extractedText
        artifactRecord["content_type"].string = processedUpload.contentType ?? "application/pdf"
        artifactRecord["size_bytes"].int = artifact.sizeInBytes
        artifactRecord["sha256"].string = artifact.sha256
        artifactRecord["created_at"].string = ISO8601DateFormatter().string(from: Date())

        if let callId = callId {
            artifactRecord["originating_call_id"].string = callId
        }

        // Merge any additional metadata from upload form
        if metadata.dictionaryValue.count > 0 {
            artifactRecord["metadata"] = metadata
        }

        Logger.info("📦 Artifact record created: \(artifactId)", category: .ai)

        return artifactRecord
    }
}
