//
//  ArtifactIngestionProtocol.swift
//  Sprung
//
//  Unified protocol for artifact ingestion from any source.
//  Document extraction (Gemini) and Git analysis (async agent) share this interface.
//
import Foundation
import SwiftyJSON

/// Result of an ingestion operation
struct IngestionResult {
    let artifactId: String
    let artifactRecord: JSON
    let source: IngestionSource
}

/// Source type for ingestion
enum IngestionSource: String {
    case document = "document"
    case gitRepository = "git_repository"
}

/// Status of an ingestion operation
enum IngestionStatus: String {
    case pending = "pending"
    case processing = "processing"
    case completed = "completed"
    case failed = "failed"
}

/// Pending artifact tracking info
struct PendingArtifact: Identifiable, Equatable {
    let id: String
    let source: IngestionSource
    let filename: String
    let planItemId: String?
    let startTime: Date
    var status: IngestionStatus
    var statusMessage: String?
}

/// Protocol for artifact ingestion services
/// Both document extraction and git analysis implement this
protocol ArtifactIngestionKernel {
    /// Unique identifier for this kernel type
    var kernelType: IngestionSource { get }

    /// Start ingestion and return immediately with a pending artifact ID
    /// The actual processing happens asynchronously
    func startIngestion(
        source: URL,
        planItemId: String?,
        metadata: JSON
    ) async throws -> PendingArtifact

    /// Called internally when ingestion completes
    /// Returns the completed artifact record
    func completeIngestion(
        pendingId: String
    ) async throws -> IngestionResult

    /// Cancel all active ingestion tasks
    func cancelAllTasks() async
}

/// Events emitted by the ingestion system
extension OnboardingEvent {
    /// Create an artifact pending event
    /// Note: Only payload["text"] is used by LLMMessenger - other fields are ignored
    static func artifactIngestionStarted(pending: PendingArtifact) -> OnboardingEvent {
        var payload = JSON()
        var messageText = "Developer status: Processing artifact \(pending.filename) (ID: \(pending.id), source: \(pending.source.rawValue))"
        if let planItemId = pending.planItemId {
            messageText += ", plan_item_id: \(planItemId)"
        }
        messageText += ". Please wait for completion."
        payload["text"].string = messageText
        return .llmSendDeveloperMessage(payload: payload)
    }

}
