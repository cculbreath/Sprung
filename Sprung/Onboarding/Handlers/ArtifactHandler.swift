//
//  ArtifactHandler.swift
//  Sprung
//
//  Artifact management handler (Spec §4.8)
//  Manages artifact creation, retrieval, and extraction coordination
//

import Foundation
import SwiftyJSON

/// Coordinates artifact management and document extraction
/// Responsibilities (Spec §4.8):
/// - Subscribe to Artifact.get and Artifact.new events
/// - Delegate to DocumentExtractionService for extraction
/// - Manage artifact store integration
/// - Emit Artifact.added and Artifact.updated events
actor ArtifactHandler: OnboardingEventEmitter {
    // MARK: - Properties

    let eventBus: EventCoordinator
    private let extractionService: DocumentExtractionService
    private let artifactStore: OnboardingArtifactStore
    private let dataStore: InterviewDataStore

    // Track ongoing extractions
    private var activeExtractions: [UUID: Date] = [:] // extractionId -> startTime

    // MARK: - Initialization

    init(
        eventBus: EventCoordinator,
        extractionService: DocumentExtractionService,
        artifactStore: OnboardingArtifactStore,
        dataStore: InterviewDataStore
    ) {
        self.eventBus = eventBus
        self.extractionService = extractionService
        self.artifactStore = artifactStore
        self.dataStore = dataStore
        Logger.info("📦 ArtifactHandler initialized", category: .ai)
    }

    // MARK: - Event Subscriptions

    /// Start listening to artifact events
    func startEventSubscriptions() {
        Task {
            for await event in await eventBus.stream(topic: .artifact) {
                await handleArtifactEvent(event)
            }
        }

        Logger.info("📡 ArtifactHandler subscribed to artifact events", category: .ai)
    }

    // MARK: - Event Handlers

    private func handleArtifactEvent(_ event: OnboardingEvent) async {
        switch event {
        case .artifactNewRequested(let fileURL, let kind, let performExtraction):
            if performExtraction {
                do {
                    let extractedText = try await extractDocument(fileURL: fileURL, kind: kind)
                    await emit(.artifactAdded(id: UUID(), kind: kind))
                    Logger.info("Artifact created and extracted", category: .ai)
                } catch {
                    Logger.error("Failed to create/extract artifact: \(error)", category: .ai)
                }
            }

        default:
            break
        }
    }

    // MARK: - Public API (called by tools until events are added)

    /// Extract document and store results
    func extractDocument(fileURL: URL, kind: OnboardingUploadKind) async throws -> String {
        let extractionId = UUID()
        activeExtractions[extractionId] = Date()

        Logger.info("🔍 Starting extraction for: \(fileURL.lastPathComponent)", category: .ai)

        defer {
            activeExtractions.removeValue(forKey: extractionId)
        }

        do {
            // Delegate to extraction service
            let extractionRequest = DocumentExtractionService.ExtractionRequest(
                fileURL: fileURL,
                purpose: "Resume/Profile extraction",
                returnTypes: ["text", "markdown"],
                autoPersist: false,
                timeout: 60.0
            )

            let result = try await extractionService.extract(using: extractionRequest)

            guard let artifact = result.artifact else {
                throw NSError(domain: "ArtifactHandler", code: 1, userInfo: [NSLocalizedDescriptionKey: "No artifact returned from extraction"])
            }

            // Emit artifact updated event
            await emit(.artifactUpdated(id: UUID(), extractedText: artifact.extractedContent))

            Logger.info("✅ Extraction complete: \(fileURL.lastPathComponent)", category: .ai)

            return artifact.extractedContent

        } catch {
            Logger.error("❌ Extraction failed: \(error)", category: .ai)
            throw error
        }
    }
}
