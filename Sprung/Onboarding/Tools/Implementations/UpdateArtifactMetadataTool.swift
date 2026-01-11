//
//  UpdateArtifactMetadataTool.swift
//  Sprung
//
//  LLM tool to update metadata fields on artifact records.
//
import Foundation
import SwiftyJSON
import SwiftOpenAI

struct UpdateArtifactMetadataTool: InterviewTool {
    private static let schema: JSONSchema = ArtifactSchemas.updateArtifactMetadata
    private weak var coordinator: OnboardingInterviewCoordinator?
    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }
    var name: String { "update_artifact_metadata" }
    var description: String { "Update metadata fields on an artifact record (field-level merge)." }
    var parameters: JSONSchema { Self.schema }
    func execute(_ params: JSON) async throws -> ToolResult {
        guard let coordinator else {
            return .error(ToolError.executionFailed("Coordinator unavailable"))
        }
        guard let artifactId = params["artifactId"].string, !artifactId.isEmpty else {
            throw ToolError.invalidParameters("artifactId must be provided")
        }
        guard let metadataUpdates = params["metadataUpdates"].dictionary, !metadataUpdates.isEmpty else {
            throw ToolError.invalidParameters("metadataUpdates must be a non-empty object")
        }
        // Validate that the artifact exists
        let existingArtifact = await coordinator.getArtifactRecord(id: artifactId)
        guard existingArtifact != nil else {
            throw ToolError.invalidParameters("Artifact not found: \(artifactId)")
        }
        // Basic type validation for known fields
        if let targetPhaseObjectives = metadataUpdates["targetPhaseObjectives"] {
            guard targetPhaseObjectives.array != nil else {
                throw ToolError.invalidParameters("targetPhaseObjectives must be an array")
            }
        }
        if let targetDeliverable = metadataUpdates["targetDeliverable"] {
            guard targetDeliverable.string != nil else {
                throw ToolError.invalidParameters("targetDeliverable must be a string")
            }
        }
        if let userValidated = metadataUpdates["userValidated"] {
            guard userValidated.bool != nil else {
                throw ToolError.invalidParameters("userValidated must be a boolean")
            }
        }
        // Emit metadata update request
        let updates = JSON(metadataUpdates)
        await coordinator.requestMetadataUpdate(artifactId: artifactId, updates: updates)
        // Return success response
        var result = JSON()
        result["status"].string = "completed"
        result["success"].boolValue = true
        result["artifactId"].stringValue = artifactId
        result["updatedFields"] = JSON(metadataUpdates.keys.map { $0 })
        Logger.info("✅ Artifact metadata update requested: \(artifactId)", category: .ai)
        return .immediate(result)
    }
}
