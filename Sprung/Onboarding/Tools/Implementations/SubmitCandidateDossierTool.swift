//
//  SubmitCandidateDossierTool.swift
//  Sprung
//
//  Submit the finalized candidate dossier with explicit schema validation.
//  Auto-generates dossier_id and timestamps.
//
import Foundation
import SwiftyJSON
import SwiftOpenAI

struct SubmitCandidateDossierTool: InterviewTool {
    private static let schema: JSONSchema = {
        let properties: [String: JSONSchema] = [
            "job_search_context": JSONSchema(
                type: .string,
                description: """
                    REQUIRED. Why looking, what seeking, priorities, non-negotiables, ideal role attributes.
                    Include: Push factors (leaving), pull factors (seeking), top priorities ranked,
                    compensation expectations if shared. 2-6 sentences or bullets.
                    Example: "Seeking greater technical ownership and product impact; frustrated by
                    bureaucracy at current role. Priorities: 1) High autonomy 2) Small team 3) Modern stack.
                    Compensation target $160-180k base, flexible for equity upside."
                    """
            ),
            "work_arrangement_preferences": JSONSchema(
                type: .string,
                description: """
                    Remote/hybrid/onsite preferences, relocation willingness, location constraints, travel tolerance.
                    Example: "Strong preference for remote-first. Would consider hybrid 2 days/week max.
                    Based in Austin, open to relocating to SF or Seattle for Staff+ role with strong equity."
                    """
            ),
            "availability": JSONSchema(
                type: .string,
                description: """
                    Start timing window, notice period, scheduling constraints.
                    Example: "Currently employed with 2-week notice. Could start 3 weeks from offer.
                    No major timing constraints."
                    """
            ),
            "unique_circumstances": JSONSchema(
                type: .string,
                description: """
                    Context for gaps, pivots, visa status, non-compete, sabbatical, or anything unconventional.
                    Keep factual and neutral. Frame positively where possible.
                    Example: "6-month sabbatical in 2023 for open-source work and learning Rust.
                    Intentional skill investment, not unemployment."
                    """
            ),
            "strengths_to_emphasize": JSONSchema(
                type: .string,
                description: """
                    Hidden or under-emphasized strengths not obvious from resume. How to surface these.
                    Look for: cross-domain expertise, untitled leadership, rare combinations,
                    skills from unlisted experiences. 2-4 paragraphs.
                    Example: "Bridge between deep technical expertise and product thinking—highlight
                    examples where technical decisions drove user impact. Self-directed learner with
                    demonstrated follow-through (sabbatical learning, OSS contributions)."
                    """
            ),
            "pitfalls_to_avoid": JSONSchema(
                type: .string,
                description: """
                    Potential concerns, vulnerabilities, or red flags and how to address/mitigate them.
                    Include specific, actionable recommendations. 2-4 paragraphs.
                    Example: "6-month gap may raise questions—proactively label as 'sabbatical' with
                    1-liner about OSS work. Avoid sounding negative about previous employer when
                    discussing departure reasons."
                    """
            ),
            "notes": JSONSchema(
                type: .string,
                description: """
                    Private interviewer observations, impressions, strategic recommendations.
                    Not for export without consent. Include deal-breakers, cultural fit indicators,
                    communication style observations.
                    Example: "Candidate is thoughtful and self-aware. Values substance over polish.
                    Deal-breakers: full-time office, large bureaucratic orgs, purely managerial track."
                    """
            )
        ]

        return JSONSchema(
            type: .object,
            description: """
                Submit the finalized candidate dossier capturing qualitative context behind the job search.

                The dossier complements structured facts (experience, education, skills) with:
                - Motivations, constraints, and preferences
                - Strategic positioning insights
                - Job fit assessment criteria

                The tool auto-generates dossier_id and timestamps. Only job_search_context is required;
                include other fields based on what was gathered during the interview.

                IMPORTANT: Keep prose concise and factual. Avoid medical/health details unless
                the candidate volunteered them. Write in professional, neutral tone.
                """,
            properties: properties,
            required: ["job_search_context"],
            additionalProperties: false
        )
    }()

    private let eventBus: EventCoordinator
    private let dataStore: InterviewDataStore

    var name: String { OnboardingToolName.submitCandidateDossier.rawValue }
    var description: String {
        """
        Submit the finalized candidate dossier. Only job_search_context is required.
        Auto-generates dossier_id and timestamps. Include strengths_to_emphasize and
        pitfalls_to_avoid for strategic positioning guidance.
        """
    }
    var parameters: JSONSchema { Self.schema }

    init(eventBus: EventCoordinator, dataStore: InterviewDataStore) {
        self.eventBus = eventBus
        self.dataStore = dataStore
    }

    func execute(_ params: JSON) async throws -> ToolResult {
        // Validate required field
        guard let jobSearchContext = params["job_search_context"].string, !jobSearchContext.isEmpty else {
            throw ToolError.invalidParameters(
                "job_search_context is required. Include: why looking, what seeking, priorities, " +
                "ideal role attributes, and compensation expectations if shared."
            )
        }

        // Build dossier with auto-generated fields
        let dossierId = "doss_\(UUID().uuidString.prefix(8).lowercased())"
        let now = ISO8601DateFormatter().string(from: Date())

        var dossier = JSON()
        dossier["dossier_id"].string = dossierId
        dossier["created_at"].string = now
        dossier["updated_at"].string = now

        // Required field
        dossier["job_search_context"].string = jobSearchContext

        // Optional fields - only include if provided
        if let value = params["work_arrangement_preferences"].string, !value.isEmpty {
            dossier["work_arrangement_preferences"].string = value
        }
        if let value = params["availability"].string, !value.isEmpty {
            dossier["availability"].string = value
        }
        if let value = params["unique_circumstances"].string, !value.isEmpty {
            dossier["unique_circumstances"].string = value
        }
        if let value = params["strengths_to_emphasize"].string, !value.isEmpty {
            dossier["strengths_to_emphasize"].string = value
        }
        if let value = params["pitfalls_to_avoid"].string, !value.isEmpty {
            dossier["pitfalls_to_avoid"].string = value
        }
        if let value = params["notes"].string, !value.isEmpty {
            dossier["notes"].string = value
        }

        // Persist to data store
        do {
            let identifier = try await dataStore.persist(dataType: "candidate_dossier", payload: dossier)

            // Emit event for downstream handling
            await eventBus.publish(.candidateDossierPersisted(dossier: dossier))
            Logger.info("📋 Candidate dossier persisted: \(dossierId)", category: .ai)

            // Build response
            var response = JSON()
            response["status"].string = "completed"
            response["dossier_id"].string = dossierId
            response["persisted_id"].string = identifier

            // List which fields were included
            var includedFields: [String] = ["job_search_context"]
            if dossier["work_arrangement_preferences"].exists() { includedFields.append("work_arrangement_preferences") }
            if dossier["availability"].exists() { includedFields.append("availability") }
            if dossier["unique_circumstances"].exists() { includedFields.append("unique_circumstances") }
            if dossier["strengths_to_emphasize"].exists() { includedFields.append("strengths_to_emphasize") }
            if dossier["pitfalls_to_avoid"].exists() { includedFields.append("pitfalls_to_avoid") }
            if dossier["notes"].exists() { includedFields.append("notes") }

            response["fields_included"].arrayObject = includedFields

            return .immediate(response)
        } catch {
            return .error(.executionFailed("Failed to persist dossier: \(error.localizedDescription)"))
        }
    }
}
