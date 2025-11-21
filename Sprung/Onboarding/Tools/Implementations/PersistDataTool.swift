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
            "dataType": JSONSchema(
                type: .string,
                description: """
                    Type of data being persisted. Each type triggers specific coordinator events and state updates.
                    Valid types:
                    - applicant_profile: Contact info (name, email, phone, location, URLs, social profiles)
                    - skeleton_timeline: Complete timeline of positions/education entries
                    - experience_defaults: Enabled resume sections configuration
                    - enabled_sections: Alternative format for enabled sections (array of section names)
                    - candidate_dossier_entry: Single Q&A entry for dossier seed (requires: question, answer, asked_at)
                    - knowledge_card: Deep dive expertise card from Phase 2
                    """,
                enum: [
                    "applicant_profile",
                    "skeleton_timeline",
                    "experience_defaults",
                    "enabled_sections",
                    "candidate_dossier_entry",
                    "knowledge_card"
                ]
            ),
            "data": JSONSchema(
                type: .object,
                description: "JSON payload containing the data to persist. Schema varies by dataType.",
                additionalProperties: true
            )
        ]
        return JSONSchema(
            type: .object,
            description: """
                Persist validated interview data to disk and trigger state updates.
                Use this after user validation confirms data accuracy. Each dataType has specific schema requirements and triggers corresponding coordinator events.
                RETURNS: { "persisted": { "id": "<uuid>", "type": "<dataType>", "status": "created" } }
                USAGE: Call after submit_for_validation returns user_validated status, or when persisting incremental data like candidate_dossier_entry.
                Phase 1 dataTypes: applicant_profile, skeleton_timeline, experience_defaults, candidate_dossier_entry
                Phase 2+ dataTypes: knowledge_card
                ERROR: Will fail if dataType is not in the enum or if required fields are missing from payload.
                """,
            properties: properties,
            required: ["dataType", "data"],
            additionalProperties: false
        )
    }()
    private let dataStore: InterviewDataStore
    private let eventBus: EventCoordinator
    var name: String { "persist_data" }
    var description: String { "Persist validated data to disk (applicant_profile, skeleton_timeline, enabled_sections, candidate_dossier_entry, etc). Returns {persisted: {id, type, status}}." }
    var parameters: JSONSchema { Self.schema }
    init(dataStore: InterviewDataStore, eventBus: EventCoordinator) {
        self.dataStore = dataStore
        self.eventBus = eventBus
    }
    func execute(_ params: JSON) async throws -> ToolResult {
        guard let dataType = params["dataType"].string, !dataType.isEmpty else {
            throw ToolError.invalidParameters("dataType must be a non-empty string")
        }
        let payload = params["data"]
        guard payload != .null else {
            throw ToolError.invalidParameters("data must be a JSON object to persist")
        }
        do {
            let identifier = try await dataStore.persist(dataType: dataType, payload: payload)
            // Emit domain-specific events after successful persist
            await emitDomainEvent(for: dataType, payload: payload)
            var response = JSON()
            response["status"].string = "completed"
            response["persisted"]["id"].string = identifier
            response["persisted"]["type"].string = dataType
            response["persisted"]["status"].string = "created"
            return .immediate(response)
        } catch {
            return .error(.executionFailed("Failed to persist data: \(error.localizedDescription)"))
        }
    }
    // MARK: - Domain Event Emission
    /// Emit domain-specific events based on dataType to update StateCoordinator
    private func emitDomainEvent(for dataType: String, payload: JSON) async {
        switch dataType {
        case "applicant_profile":
            // Extract the profile data and emit event
            let profileData = payload
            await eventBus.publish(.applicantProfileStored(profileData))
            Logger.info("📤 Emitted .applicantProfileStored event", category: .ai)
        case "skeleton_timeline":
            // Normalize timeline data and emit event
            let normalizedTimeline = TimelineCardAdapter.normalizedTimeline(payload)
            await eventBus.publish(.skeletonTimelineStored(normalizedTimeline))
            Logger.info("📤 Emitted .skeletonTimelineStored event", category: .ai)
        case "experience_defaults", "enabled_sections":
            // Extract enabled sections and emit event
            if let sections = extractEnabledSections(from: payload) {
                await eventBus.publish(.enabledSectionsUpdated(sections))
                Logger.info("📤 Emitted .enabledSectionsUpdated event with \(sections.count) sections", category: .ai)
            }
        case "candidate_dossier_entry":
            // No state mutation required for dossier entries - just persist
            Logger.info("💾 Persisted candidate_dossier_entry (no event emission)", category: .ai)
        case "knowledge_card":
            // Optional: emit knowledge card persisted event
            await eventBus.publish(.knowledgeCardPersisted(card: payload))
            Logger.info("📤 Emitted .knowledgeCardPersisted event", category: .ai)
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
