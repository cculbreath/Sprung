//
//  DocumentArtifactMessenger.swift
//  Sprung
//
//  Thin handler that sends document artifacts to the LLM as user messages.
//  Reacts to artifact creation events.
//
import Foundation
import SwiftyJSON
/// Handles sending document artifacts to the LLM after production
actor DocumentArtifactMessenger: OnboardingEventEmitter {
    // MARK: - Properties
    let eventBus: EventCoordinator
    // MARK: - Lifecycle State
    private var subscriptionTask: Task<Void, Never>?
    private var isActive = false
    // MARK: - Initialization
    init(eventBus: EventCoordinator) {
        self.eventBus = eventBus
        Logger.info("📤 DocumentArtifactMessenger initialized", category: .ai)
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
        Logger.info("▶️ DocumentArtifactMessenger started", category: .ai)
    }
    func stop() {
        guard isActive else { return }
        isActive = false
        subscriptionTask?.cancel()
        subscriptionTask = nil
        Logger.info("⏹️ DocumentArtifactMessenger stopped", category: .ai)
    }
    // MARK: - Event Handling
    private func handleEvent(_ event: OnboardingEvent) async {
        guard case .artifactRecordProduced(let record) = event else {
            return
        }
        // Only send PDF documents to LLM automatically
        let contentType = record["content_type"].stringValue
        guard contentType.lowercased().contains("pdf") else {
            return
        }
        let extractedText = record["extracted_text"].stringValue
        guard !extractedText.isEmpty else {
            Logger.warning("⚠️ Skipping artifact - no extracted text", category: .ai)
            return
        }
        // Format as user message
        let artifactId = record["id"].stringValue
        let documentType = record["document_type"].stringValue
        let filename = record["filename"].stringValue
        var messageText = "I've uploaded a document (\(documentType)): \(filename)\n\n"
        messageText += "Here is the extracted content:\n\n"
        messageText += extractedText
        // Create user message payload
        var payload = JSON()
        payload["text"].string = messageText
        payload["artifact_id"].string = artifactId
        payload["artifact_record"] = record
        // Emit LLM message event
        await emit(.llmSendUserMessage(payload: payload, isSystemGenerated: true))
        Logger.info("📤 Document artifact sent to LLM: \(artifactId)", category: .ai)
    }
}
