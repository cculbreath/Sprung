//
//  MetadataExtractionService.swift
//  Sprung
//
//  Extracts card metadata (type, title, organization, dates, location) from
//  document summaries using a simple LLM call.
//
//  Used before KC agent generation to provide better context and metadata
//  for the knowledge card.
//

import Foundation
import SwiftyJSON

/// Service for extracting knowledge card metadata from document summaries.
actor MetadataExtractionService {
    // MARK: - Dependencies

    private weak var llmFacade: LLMFacade?

    // MARK: - Configuration

    private let modelId: String

    // MARK: - Structured Response Type

    private struct MetadataResponse: Codable, Sendable {
        let card_type: String
        let title: String
        let organization: String?
        let time_period: String?
        let location: String?
    }

    // MARK: - Initialization

    init(llmFacade: LLMFacade?, modelId: String? = nil) {
        self.llmFacade = llmFacade
        // Use provided modelId, or fall back to user setting; empty means not configured
        let configured = modelId ?? UserDefaults.standard.string(forKey: "onboardingKCAgentModelId")
        self.modelId = (configured?.isEmpty == false) ? configured! : ""
    }

    // MARK: - Public API

    /// Extract metadata from artifact summaries
    /// - Parameter artifacts: Array of artifact JSON objects with summaries
    /// - Returns: CardMetadata extracted from the documents
    func extract(from artifacts: [JSON]) async throws -> CardMetadata {
        guard !artifacts.isEmpty else {
            throw MetadataExtractionError.noArtifacts
        }

        guard let facade = llmFacade else {
            // Fallback to defaults if no LLM available
            let filename = artifacts.first?["filename"].stringValue ?? "Document"
            return CardMetadata.defaults(fromFilename: filename)
        }

        guard !modelId.isEmpty else {
            throw ModelConfigurationError.modelNotConfigured(
                settingKey: "onboardingKCAgentModelId",
                operationName: "Metadata Extraction"
            )
        }

        // Build summary of all artifacts for the prompt
        let summaryText = artifacts.enumerated().map { index, artifact in
            let filename = artifact["filename"].stringValue
            let summary = artifact["summary"].stringValue
            let briefDesc = artifact["brief_description"].stringValue
            let docType = artifact["summary_metadata"]["document_type"].stringValue

            var text = "Document \(index + 1): \(filename)"
            if !docType.isEmpty {
                text += " (Type: \(docType))"
            }
            if !briefDesc.isEmpty {
                text += "\nBrief: \(briefDesc)"
            }
            if !summary.isEmpty {
                // Truncate long summaries
                let truncated = summary.count > 2000 ? String(summary.prefix(2000)) + "..." : summary
                text += "\nSummary: \(truncated)"
            }
            return text
        }.joined(separator: "\n\n")

        let prompt = buildPrompt(summaryText: summaryText)

        do {
            let response = try await MainActor.run {
                Task {
                    try await facade.executeStructured(
                        prompt: prompt,
                        modelId: modelId,
                        as: MetadataResponse.self,
                        temperature: 0.2
                    )
                }
            }.value

            return CardMetadata(
                cardType: normalizeCardType(response.card_type),
                title: response.title.isEmpty ? CardMetadata.defaults(fromFilename: artifacts.first?["filename"].stringValue ?? "Document").title : response.title,
                organization: response.organization?.isEmpty == true ? nil : response.organization,
                timePeriod: response.time_period?.isEmpty == true ? nil : response.time_period,
                location: response.location?.isEmpty == true ? nil : response.location
            )
        } catch {
            Logger.warning("⚠️ MetadataExtractionService: LLM extraction failed, using defaults: \(error.localizedDescription)", category: .ai)
            let filename = artifacts.first?["filename"].stringValue ?? "Document"
            return CardMetadata.defaults(fromFilename: filename)
        }
    }

    // MARK: - Private Helpers

    private func buildPrompt(summaryText: String) -> String {
        """
        Analyze the following document summaries and extract metadata for a knowledge card.

        Documents:
        \(summaryText)

        Based on the document content, determine:

        1. **card_type**: The most appropriate category. Choose ONE:
           - "job" - Work experience, employment history, job-related documents
           - "skill" - Technical skills, certifications, capabilities
           - "education" - Academic credentials, degrees, courses, training
           - "project" - Personal projects, portfolio work, side projects, technical work

        2. **title**: A concise, descriptive title for the knowledge card (e.g., "Senior Engineer at Acme Corp" or "Machine Learning Portfolio")

        3. **organization**: The company, university, or organization name (if applicable)

        4. **time_period**: Date range in format "YYYY-MM to YYYY-MM" or "YYYY-MM to Present" (if applicable)

        5. **location**: City, State/Country or "Remote" (if applicable)

        Return your analysis as JSON. If a field is not determinable from the documents, set it to null.
        """
    }

    private func normalizeCardType(_ type: String) -> String {
        let lowercased = type.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch lowercased {
        case "job", "work", "employment", "experience":
            return "job"
        case "skill", "skills", "certification", "certifications":
            return "skill"
        case "education", "academic", "degree", "course", "training":
            return "education"
        case "project", "portfolio", "personal":
            return "project"
        default:
            return "project" // Default fallback
        }
    }
}

// MARK: - Errors

enum MetadataExtractionError: LocalizedError {
    case noArtifacts
    case llmError(String)

    var errorDescription: String? {
        switch self {
        case .noArtifacts:
            return "No artifacts provided for metadata extraction"
        case .llmError(let message):
            return "LLM metadata extraction failed: \(message)"
        }
    }
}
