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
    let artifactRecord: JSON
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
    var status: IngestionStatus
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
        return .llm(.sendCoordinatorMessage(payload: payload))
    }

}
