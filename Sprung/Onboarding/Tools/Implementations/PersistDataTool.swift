//
//  PersistDataTool.swift
//  Sprung
//
//  Saves intermediate interview data to disk for later retrieval.
//
import Foundation
import SwiftyJSON
import SwiftOpenAI
struct PersistDataTool: InterviewTool {
    private static let schema: JSONSchema = {
        let properties: [String: JSONSchema] = [
            "dataType": MiscSchemas.persistDataType,
            "data": MiscSchemas.persistDataPayload
        ]
        return JSONSchema(
            type: .object,
            description: """
                Persist validated interview data to disk and trigger state updates.
                Use this after user validation confirms data accuracy. Each dataType has specific schema requirements and triggers corresponding coordinator events.
                RETURNS: { "persisted": { "id": "<uuid>", "type": "<dataType>", "status": "created" } }
                USAGE: Call after submit_for_validation returns user_validated status, or when persisting incremental data like candidate_dossier_entry.
                Phase 1 dataTypes: applicant_profile, skeleton_timeline, experience_defaults, candidate_dossier_entry
                Phase 2 dataTypes: knowledge_card
                Phase 3 dataTypes: writing_sample, candidate_dossier
                ERROR: Will fail if dataType is not in the enum or if required fields are missing from payload.
                """,
            properties: properties,
            required: ["dataType", "data"],
            additionalProperties: false
        )
    }()
    private let dataStore: InterviewDataStore
    private let eventBus: EventCoordinator
    var name: String { OnboardingToolName.persistData.rawValue }
    var description: String { "Persist validated data to disk (applicant_profile, skeleton_timeline, enabled_sections, candidate_dossier_entry, etc). Returns {persisted: {id, type, status}}." }
    var parameters: JSONSchema { Self.schema }
    init(dataStore: InterviewDataStore, eventBus: EventCoordinator) {
        self.dataStore = dataStore
        self.eventBus = eventBus
    }
    func execute(_ params: JSON) async throws -> ToolResult {
        let dataType = try ToolResultHelpers.requireString(params["dataType"].string, named: "dataType")

        let payload = params["data"]
        guard payload != .null, payload.type != .null else {
            throw ToolError.invalidParameters("Missing required 'data' parameter. You must include the actual content to persist as a JSON object in the 'data' field. For candidate_dossier, include the full dossier content: {\"dataType\": \"candidate_dossier\", \"data\": {\"headline\": \"...\", \"summary\": \"...\", ...}}")
        }
        do {
            let identifier = try await dataStore.persist(dataType: dataType, payload: payload)
            // Emit domain-specific events after successful persist
            await emitDomainEvent(for: dataType, payload: payload)

            var persistedData = JSON()
            persistedData["id"].string = identifier
            persistedData["type"].string = dataType
            persistedData["status"].string = "created"

            var additionalData = JSON()
            additionalData["persisted"] = persistedData

            return ToolResultHelpers.statusResponse(
                status: "completed",
                additionalData: additionalData
            )
        } catch {
            return ToolResultHelpers.executionFailed("Failed to persist data: \(error.localizedDescription)")
        }
    }
    // MARK: - Domain Event Emission
    /// Emit domain-specific events based on dataType to update StateCoordinator
    private func emitDomainEvent(for dataType: String, payload: JSON) async {
        switch dataType {
        case OnboardingDataType.applicantProfile.rawValue:
            // Extract the profile data and emit event
            let profileData = payload
            await eventBus.publish(.applicantProfileStored(profileData))
            Logger.info("📤 Emitted .applicantProfileStored event", category: .ai)
        case OnboardingDataType.skeletonTimeline.rawValue:
            // Normalize timeline data and emit event
            let normalizedTimeline = TimelineCardAdapter.normalizedTimeline(payload)
            await eventBus.publish(.skeletonTimelineStored(normalizedTimeline))
            Logger.info("📤 Emitted .skeletonTimelineStored event", category: .ai)
        case OnboardingDataType.experienceDefaults.rawValue:
            // Check if this is full experience defaults (has work/education/skills arrays) or just enabled sections
            if payload["work"].exists() || payload["education"].exists() || payload["skills"].exists() || payload["projects"].exists() {
                // Full experience defaults from LLM - emit event to populate ExperienceDefaults store
                await eventBus.publish(.experienceDefaultsGenerated(defaults: payload))
                Logger.info("📤 Emitted .experienceDefaultsGenerated event with full resume data", category: .ai)
            } else if let sections = extractEnabledSections(from: payload) {
                // Legacy format: just enabled section names
                await eventBus.publish(.enabledSectionsUpdated(sections))
                Logger.info("📤 Emitted .enabledSectionsUpdated event with \(sections.count) sections", category: .ai)
            }
        case OnboardingDataType.enabledSections.rawValue:
            // Extract enabled sections and emit event
            if let sections = extractEnabledSections(from: payload) {
                await eventBus.publish(.enabledSectionsUpdated(sections))
                Logger.info("📤 Emitted .enabledSectionsUpdated event with \(sections.count) sections", category: .ai)
            }
        case OnboardingDataType.candidateDossierEntry.rawValue:
            // Emit dossier field collected event for tracking
            if let fieldType = payload["field_type"].string {
                await eventBus.publish(.dossierFieldCollected(field: fieldType))
                Logger.info("📤 Emitted .dossierFieldCollected event for field: \(fieldType)", category: .ai)
            } else {
                Logger.info("💾 Persisted candidate_dossier_entry (no field_type for tracking)", category: .ai)
            }
        case OnboardingDataType.knowledgeCard.rawValue:
            // Optional: emit knowledge card persisted event
            await eventBus.publish(.knowledgeCardPersisted(card: payload))
            Logger.info("📤 Emitted .knowledgeCardPersisted event", category: .ai)
        case OnboardingDataType.writingSample.rawValue:
            // Emit writing sample persisted event
            await eventBus.publish(.writingSamplePersisted(sample: payload))
            Logger.info("📤 Emitted .writingSamplePersisted event", category: .ai)
        case OnboardingDataType.candidateDossier.rawValue:
            // Emit candidate dossier persisted event
            await eventBus.publish(.candidateDossierPersisted(dossier: payload))
            Logger.info("📤 Emitted .candidateDossierPersisted event", category: .ai)
        default:
            // Other data types don't trigger state events
            Logger.debug("💾 Persisted \(dataType) (no domain event)", category: .ai)
        }
    }
    /// Extract enabled sections from payload
    /// Supports two formats:
    /// 1. payload["enabled_sections"] = ["section1", "section2", ...]
    /// 2. payload = ["section1", "section2", ...]
    private func extractEnabledSections(from payload: JSON) -> Set<String>? {
        // Try format 1: payload has "enabled_sections" key
        if let enabledSectionsArray = payload["enabled_sections"].array {
            let sections = enabledSectionsArray.compactMap { $0.string }
            return Set(sections)
        }
        // Try format 2: payload is directly an array of strings
        if let sectionsArray = payload.array {
            let sections = sectionsArray.compactMap { $0.string }
            return Set(sections)
        }
        Logger.warning("⚠️ Could not extract enabled_sections from payload", category: .ai)
        return nil
    }
}
