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
    /// Note: The fileURL is expected to already be in storage (copied by UploadInteractionHandler)
    func processDocument(
        fileURL: URL,
        documentType: String,
        callId: String?,
        metadata: JSON,
        statusCallback: (@Sendable (String) -> Void)? = nil
    ) async throws -> JSON {
        let filename = fileURL.lastPathComponent
        Logger.info("📄 Processing document: \(filename)", category: .ai)

        // File is already in storage (copied by UploadInteractionHandler before this is called)
        // Just use it directly - no need to copy again
        let storagePath = fileURL.path
        Logger.info("💾 Document location: \(storagePath)", category: .ai)

        // Step 2: Extract text using configured model
        let modelId = UserDefaults.standard.string(forKey: "onboardingPDFExtractionModelId") ?? "google/gemini-2.0-flash-001"
        Logger.info("🔍 Extracting text with model: \(modelId)", category: .ai)
        statusCallback?("Extracting text from \(filename)...")
        let extractionRequest = DocumentExtractionService.ExtractionRequest(
            fileURL: fileURL,
            purpose: documentType,
            returnTypes: ["text"],
            autoPersist: false,
            timeout: nil
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
        let artifactId = artifact.id
        Logger.info("✅ Text extraction completed: \(artifactId)", category: .ai)
        // Step 3: Create artifact record
        var artifactRecord = JSON()
        artifactRecord["id"].string = artifactId
        artifactRecord["filename"].string = filename
        artifactRecord["document_type"].string = documentType
        artifactRecord["storage_path"].string = storagePath
        artifactRecord["extracted_text"].string = extractedText
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
        // Merge any additional metadata from upload form
        if !metadata.dictionaryValue.isEmpty {
            artifactRecord["metadata"] = metadata
        }
        Logger.info("📦 Artifact record created: \(artifactId)", category: .ai)
        return artifactRecord
    }
}
