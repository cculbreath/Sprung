//
//  DiscoveryResponseParser.swift
//  Sprung
//
//  Parses LLM JSON responses into typed result structures.
//

import Foundation

struct DiscoveryResponseParser {

    // MARK: - Public Parsing Methods

    func parseTasks(_ response: String) throws -> DailyTasksResult {
        try decodeFromResponse(response, as: DailyTasksResult.self)
    }

    func parseSources(_ response: String) throws -> JobSourcesResult {
        try decodeFromResponse(response, as: JobSourcesResult.self)
    }

    func parseEvents(_ response: String) throws -> NetworkingEventsResult {
        try decodeFromResponse(response, as: NetworkingEventsResult.self)
    }

    func parsePrep(_ response: String) throws -> EventPrepResult {
        try decodeFromResponse(response, as: EventPrepResult.self)
    }

    func parseDebriefOutcomes(_ response: String) throws -> DebriefOutcomesResult {
        try decodeFromResponse(response, as: DebriefOutcomesResult.self)
    }

    func parseJobSelections(_ response: String) throws -> JobSelectionsResult {
        try decodeFromResponse(response, as: JobSelectionsResult.self)
    }

    // MARK: - JSON Extraction & Decoding

    private func decodeFromResponse<T: Decodable>(_ response: String, as type: T.Type) throws -> T {
        guard let jsonString = extractJSON(from: response),
              let data = jsonString.data(using: .utf8) else {
            throw DiscoveryAgentError.invalidResponse
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            Logger.error("Failed to decode \(type): \(error)", category: .ai)
            throw DiscoveryAgentError.invalidResponse
        }
    }

    private func extractJSON(from response: String) -> String? {
        // Try to find JSON in code blocks first
        if let jsonMatch = response.range(of: "```json\\s*(.+?)```", options: .regularExpression) {
            var extracted = String(response[jsonMatch])
            extracted = extracted.replacingOccurrences(of: "```json", with: "")
            extracted = extracted.replacingOccurrences(of: "```", with: "")
            return extracted.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Try to find raw JSON (starts with { or [)
        if let jsonStart = response.firstIndex(of: "{"),
           let jsonEnd = response.lastIndex(of: "}") {
            return String(response[jsonStart...jsonEnd])
        }

        if let jsonStart = response.firstIndex(of: "["),
           let jsonEnd = response.lastIndex(of: "]") {
            return String(response[jsonStart...jsonEnd])
        }

        return nil
    }
}
