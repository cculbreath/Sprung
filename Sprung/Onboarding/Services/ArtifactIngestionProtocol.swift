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
}

/// Events emitted by the ingestion system
extension OnboardingEvent {
    /// Create an artifact pending event
    static func artifactIngestionStarted(pending: PendingArtifact) -> OnboardingEvent {
        var payload = JSON()
        payload["artifact_id"].string = pending.id
        payload["source"].string = pending.source.rawValue
        payload["filename"].string = pending.filename
        if let planItemId = pending.planItemId {
            payload["plan_item_id"].string = planItemId
        }
        payload["status"].string = "pending"
        payload["message"].string = "Processing \(pending.filename)..."
        return .llmSendDeveloperMessage(payload: payload)
    }

    /// Create an artifact completed event
    static func artifactIngestionCompleted(result: IngestionResult, planItemId: String?) -> OnboardingEvent {
        var payload = JSON()
        payload["type"].string = "artifact_ready"
        payload["artifact_id"].string = result.artifactId
        payload["source"].string = result.source.rawValue
        if let planItemId = planItemId {
            payload["plan_item_id"].string = planItemId
        }
        payload["message"].string = "Artifact ready. Use list_artifacts to see details."
        return .llmSendDeveloperMessage(payload: payload)
    }
}
