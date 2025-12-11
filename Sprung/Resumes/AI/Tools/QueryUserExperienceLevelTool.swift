//
//  QueryUserExperienceLevelTool.swift
//  Sprung
//
//  Tool for querying user about their experience level with specific skills.
//  Used when the LLM encounters skills adjacent to the user's background.
//
import Foundation
import SwiftyJSON

/// Tool that queries the user about their experience level with specific skills.
/// The LLM uses this when it encounters skills in the job description that are
/// adjacent to the user's background but not explicitly mentioned in their resume.
struct QueryUserExperienceLevelTool: ResumeTool {
    static let name = "query_user_experience_level"

    static let description = """
        Query the user about their experience level with specific skills. \
        Use this tool when you suspect the applicant has a skill that strongly aligns with \
        job requirements, but direct evidence is not in the background documents. \
        Examples: \
        (1) A physicist likely has familiarity with electricity and magnetism even if their docs only mention particle physics. \
        (2) A React developer may have React Native experience even if not explicitly listed. \
        (3) Someone with extensive Python experience might know specific frameworks the job requires. \
        The user will select their proficiency level (none, novice, competent, advanced, expert) \
        and optionally add comments for context.
        """

    static let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "skills": [
                "type": "array",
                "description": "Array of skill keywords to query the user about. Each skill should be a technology, framework, or methodology mentioned in the job description that relates to but isn't explicitly listed in the user's resume.",
                "items": [
                    "type": "object",
                    "properties": [
                        "keyword": [
                            "type": "string",
                            "description": "The skill keyword to query (e.g., 'Kubernetes', 'React Native', 'GraphQL')"
                        ]
                    ],
                    "required": ["keyword"]
                ]
            ]
        ],
        "required": ["skills"],
        "additionalProperties": false
    ]

    func execute(_ params: JSON, context: ResumeToolContext) async throws -> ResumeToolResult {
        // Parse the skills array from parameters
        guard let skillsArray = params["skills"].array else {
            return .error("Missing or invalid 'skills' parameter")
        }

        let skills: [SkillQuery] = skillsArray.compactMap { skillJson in
            guard let keyword = skillJson["keyword"].string, !keyword.isEmpty else {
                return nil
            }
            return SkillQuery(keyword: keyword)
        }

        if skills.isEmpty {
            return .error("No valid skills provided to query")
        }

        Logger.info("🎯 [QueryUserExperienceLevelTool] Requesting user input for \(skills.count) skills: \(skills.map(\.keyword).joined(separator: ", "))", category: .ai)

        // Return pending action - the view model will present UI and collect response
        return .pendingUserAction(.skillExperiencePicker(skills: skills))
    }
}

// MARK: - Result Formatting

extension QueryUserExperienceLevelTool {
    /// Format the user's responses as JSON for the LLM
    static func formatResults(_ results: [SkillExperienceResult]) -> String {
        let response = SkillExperienceResponse(results: results)
        if let data = try? JSONEncoder().encode(response),
           let jsonString = String(data: data, encoding: .utf8) {
            return jsonString
        }
        return """
        {"error": "Failed to encode results"}
        """
    }

    /// Format a cancellation response for the LLM
    static func formatCancellation() -> String {
        return """
        {"error": "User skipped this query", "message": "User chose not to provide experience levels for these skills. Proceed with your best judgment based on available information."}
        """
    }
}

/// Response structure for encoding results
private struct SkillExperienceResponse: Codable {
    let results: [SkillExperienceResult]
}
