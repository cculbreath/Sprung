//
//  DocumentArtifactHandler.swift
//  Sprung
//
//  Thin handler that processes uploaded documents and produces artifact records.
//  Delegates business logic to DocumentProcessingService.
//
import Foundation
import SwiftyJSON
/// Handles document upload completion by processing files and emitting artifact records
actor DocumentArtifactHandler: OnboardingEventEmitter {
    // MARK: - Properties
    let eventBus: EventCoordinator
    private let documentProcessingService: DocumentProcessingService
    // MARK: - Lifecycle State
    private var subscriptionTask: Task<Void, Never>?
    private var isActive = false
    // MARK: - Initialization
    init(
        eventBus: EventCoordinator,
        documentProcessingService: DocumentProcessingService
    ) {
        self.eventBus = eventBus
        self.documentProcessingService = documentProcessingService
        Logger.info("📄 DocumentArtifactHandler initialized", category: .ai)
    }
    // MARK: - Lifecycle
    func start() {
        guard !isActive else { return }
        isActive = true
        subscriptionTask = Task { [weak self] in
            guard let self else { return }
            for await event in await self.eventBus.stream(topic: .artifact) {
                if Task.isCancelled { break }
                await self.handleEvent(event)
            }
        }
        Logger.info("▶️ DocumentArtifactHandler started", category: .ai)
    }
    func stop() {
        guard isActive else { return }
        isActive = false
        subscriptionTask?.cancel()
        subscriptionTask = nil
        Logger.info("⏹️ DocumentArtifactHandler stopped", category: .ai)
    }
    // MARK: - Event Handling
    private func handleEvent(_ event: OnboardingEvent) async {
        guard case .uploadCompleted(let files, let requestKind, let callId, let metadata) = event else {
            return
        }
        // Process uploaded documents
        for file in files {
            Logger.info("📄 Document detected: \(file.filename)", category: .ai)
            do {
                // Call service to perform business logic
                let artifactRecord = try await documentProcessingService.processDocument(
                    fileURL: file.storageURL,
                    documentType: requestKind,
                    callId: callId,
                    metadata: metadata
                )
                // Emit artifact record produced event
                await emit(.artifactRecordProduced(record: artifactRecord))
            } catch {
                Logger.error("❌ Document processing failed: \(error.localizedDescription)", category: .ai)
                // Emit error to UI with user-friendly message
                let userMessage: String
                if let extractionError = error as? DocumentExtractionService.ExtractionError {
                    userMessage = extractionError.userFacingMessage
                } else {
                    userMessage = "Failed to process document: \(error.localizedDescription)"
                }
                await emit(.errorOccurred(userMessage))
            }
        }
    }
}
