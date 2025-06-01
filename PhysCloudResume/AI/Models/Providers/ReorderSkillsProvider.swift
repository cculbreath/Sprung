//
//  ReorderSkillsProvider.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 5/22/25.
//

import Foundation
import SwiftUI

@Observable class ReorderSkillsProvider {
    // MARK: - Properties

    // The system prompt for skill reordering
    let systemPrompt = """
    You are an expert resume optimizer specializing in skills prioritization. Your task is to analyze a list of skills and expertise items and reorder them based on their relevance to a specific job description. Place the most relevant and impressive skills at the top of the list.

    IMPORTANT: Your response must be a valid JSON object conforming to the JSON schema provided. The id field for each skill must contain the exact UUID string from the input. Do not modify the UUID format in any way.

    IMPORTANT: Output ONLY the JSON object with the "reordered_skills_and_expertise" array. Do not include any additional commentary, explanation, or text outside the JSON.
    """

    // The base LLM provider with OpenRouter client
    private let baseLLMProvider: BaseLLMProvider
    
    // Model to use for skill reordering
    private let modelId: String
    
    var resume: Resume
    var jobDescription: String

    // MARK: - Initialization

    /// Initialize with app state and specific model
    /// - Parameters:
    ///   - appState: The application state
    ///   - resume: The resume containing skills to reorder
    ///   - jobDescription: The job description to match against
    ///   - modelId: The OpenRouter model ID to use
    init(appState: AppState, resume: Resume, jobDescription: String, modelId: String) {
        self.baseLLMProvider = BaseLLMProvider(appState: appState)
        self.modelId = modelId
        self.resume = resume
        self.jobDescription = jobDescription
        
        // Log which model we're using
        Logger.debug("🚀 ReorderSkillsProvider initialized with OpenRouter model: \(modelId)")
    }

    /// Writes debug content to a file in the Downloads folder if enabled
    /// - Parameters:
    ///   - content: The content to write
    ///   - fileName: The name of the file to write
    private func saveMessageToDebugFile(content: String, fileName: String) {
        guard UserDefaults.standard.bool(forKey: "saveDebugPrompts") else {
            return
        }
        let fileManager = FileManager.default
        let homeDirectoryURL = fileManager.homeDirectoryForCurrentUser
        let downloadsURL = homeDirectoryURL.appendingPathComponent("Downloads")
        let fileURL = downloadsURL.appendingPathComponent(fileName)
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            Logger.debug("Saved debug file: \(fileName)")
        } catch {
            Logger.warning("Failed to save debug file \(fileName): \(error.localizedDescription)")
        }
    }

    // MARK: - API Call

    /// Fetches skill reordering recommendations using the abstraction layer
    /// - Returns: An array of reordered skill recommendations
    func fetchReorderedSkills() async throws -> [ReorderedSkillNode] {
        // Get the simplified skills JSON with just names, IDs and order
        let simplifiedSkillsJson = TreeNodeExtractor.shared.extractSkillsForReordering(resume: resume) ?? "[]"
        
        let prompt = buildPrompt(skillsJsonString: simplifiedSkillsJson, jobDescription: jobDescription)
        if UserDefaults.standard.bool(forKey: "saveDebugPrompts") {
            saveMessageToDebugFile(content: prompt, fileName: "reorderSkillsPrompt.txt")
        }

        let messages: [AppLLMMessage] = [
            AppLLMMessage(role: .system, text: systemPrompt),
            AppLLMMessage(role: .user, text: prompt)
        ]

        Logger.info("🎯 Executing skill reordering with OpenRouter model: \(modelId)")

        let query = AppLLMQuery(
            messages: messages,
            modelIdentifier: modelId,
            responseType: ReorderSkillsResponse.self
        )

        // Attempt to get the structured response
        do {
            let response = try await baseLLMProvider.executeQuery(query)
            let decoder = JSONDecoder()
            
            switch response {
            case .structured(let data):
                // Try to decode the structured data
                do {
                    let reorderResponse = try decoder.decode(ReorderSkillsResponse.self, from: data)
                    if !reorderResponse.validate() {
                        throw NSError(domain: "ReorderSkillsProvider", code: 6,
                                     userInfo: [NSLocalizedDescriptionKey: "Invalid reorder response: failed validation"])
                    }
                    
                    // Convert to the format expected by the existing code
                    let reorderedNodes = reorderResponse.reorderedSkillsAndExpertise.map { simpleSkill in
                        // Look up the original skill to get tree path and title node info
                        let originalSkill = findOriginalSkill(with: simpleSkill.id)
                        return ReorderedSkillNode(
                            id: simpleSkill.id,
                            originalValue: simpleSkill.originalValue,
                            newPosition: simpleSkill.newPosition,
                            reasonForReordering: simpleSkill.reasonForReordering,
                            isTitleNode: originalSkill?.isTitleNode ?? false,
                            treePath: originalSkill?.treePath ?? ""
                        )
                    }
                    
                    return reorderedNodes
                } catch {
                    // Log the raw data for debugging
                    let rawString = String(data: data, encoding: .utf8) ?? "Unable to convert to string"
                    Logger.error("Failed to decode structured data: \(error.localizedDescription)")
                    Logger.error("Raw data: \(rawString)")
                    
                    // Attempt to extract JSON from possibly malformed response
                    if let extractedJson = extractJSONFromString(rawString),
                       let extractedData = extractedJson.data(using: .utf8),
                       let reorderResponse = try? decoder.decode(ReorderSkillsResponse.self, from: extractedData),
                       reorderResponse.validate() {
                        
                        Logger.info("Successfully extracted valid JSON from malformed response")
                        let reorderedNodes = reorderResponse.reorderedSkillsAndExpertise.map { simpleSkill in
                            let originalSkill = findOriginalSkill(with: simpleSkill.id)
                            return ReorderedSkillNode(
                                id: simpleSkill.id,
                                originalValue: simpleSkill.originalValue,
                                newPosition: simpleSkill.newPosition,
                                reasonForReordering: simpleSkill.reasonForReordering,
                                isTitleNode: originalSkill?.isTitleNode ?? false,
                                treePath: originalSkill?.treePath ?? ""
                            )
                        }
                        return reorderedNodes
                    }
                    
                    // If all recovery attempts fail, rethrow the error
                    throw error
                }
                
            case .text(let text):
                // Try to decode text as JSON
                Logger.info("Received text response, attempting to parse as JSON")
                
                if let data = text.data(using: .utf8) {
                    do {
                        let reorderResponse = try decoder.decode(ReorderSkillsResponse.self, from: data)
                        if !reorderResponse.validate() {
                            throw NSError(domain: "ReorderSkillsProvider", code: 6,
                                         userInfo: [NSLocalizedDescriptionKey: "Invalid reorder response: failed validation"])
                        }
                        
                        let reorderedNodes = reorderResponse.reorderedSkillsAndExpertise.map { simpleSkill in
                            let originalSkill = findOriginalSkill(with: simpleSkill.id)
                            return ReorderedSkillNode(
                                id: simpleSkill.id,
                                originalValue: simpleSkill.originalValue,
                                newPosition: simpleSkill.newPosition,
                                reasonForReordering: simpleSkill.reasonForReordering,
                                isTitleNode: originalSkill?.isTitleNode ?? false,
                                treePath: originalSkill?.treePath ?? ""
                            )
                        }
                        return reorderedNodes
                    } catch {
                        // Try to extract JSON from possibly malformed text response
                        if let extractedJson = extractJSONFromString(text),
                           let extractedData = extractedJson.data(using: .utf8),
                           let reorderResponse = try? decoder.decode(ReorderSkillsResponse.self, from: extractedData),
                           reorderResponse.validate() {
                            
                            Logger.info("Successfully extracted valid JSON from text response")
                            let reorderedNodes = reorderResponse.reorderedSkillsAndExpertise.map { simpleSkill in
                                let originalSkill = findOriginalSkill(with: simpleSkill.id)
                                return ReorderedSkillNode(
                                    id: simpleSkill.id,
                                    originalValue: simpleSkill.originalValue,
                                    newPosition: simpleSkill.newPosition,
                                    reasonForReordering: simpleSkill.reasonForReordering,
                                    isTitleNode: originalSkill?.isTitleNode ?? false,
                                    treePath: originalSkill?.treePath ?? ""
                                )
                            }
                            return reorderedNodes
                        }
                        
                        // If all recovery attempts fail, throw a descriptive error
                        throw NSError(domain: "ReorderSkillsProvider", code: 7,
                                     userInfo: [NSLocalizedDescriptionKey: "Failed to parse text response as JSON: \(error.localizedDescription)"])
                    }
                } else {
                    throw AppLLMError.unexpectedResponseFormat
                }
            }
        } catch {
            Logger.error("Skill reordering error: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Finds the original skill data for the given ID
    /// - Parameter id: The skill ID to find
    /// - Returns: The original skill data if found
    private func findOriginalSkill(with id: String) -> (isTitleNode: Bool, treePath: String)? {
        // Look up the skill in the resume's tree structure to get the original tree path and title info
        guard let nodes = resume.nodes.first(where: { $0.id == id }) else {
            return nil
        }
        
        // Determine if this is a title node by checking if it has children
        let isTitleNode = nodes.children?.isEmpty == false
        
        // Generate a simple tree path - for now just use the node's name
        // In a more sophisticated implementation, you'd walk up the tree to build a full path
        let treePath = nodes.name
        
        return (isTitleNode: isTitleNode, treePath: treePath)
    }
    
    /// Extracts a JSON object from a potentially malformed string
    /// - Parameter text: The text that may contain JSON
    /// - Returns: A valid JSON string or nil if extraction fails
    private func extractJSONFromString(_ text: String) -> String? {
        // Find the first { and the last } to extract the JSON object
        guard let startIndex = text.firstIndex(of: "{"),
              let endIndex = text.lastIndex(of: "}"),
              startIndex < endIndex else {
            return nil
        }
        
        // Extract the JSON substring
        let jsonSubstring = text[startIndex...endIndex]
        let jsonString = String(jsonSubstring)
        
        // Validate that it's valid JSON
        guard let data = jsonString.data(using: .utf8),
              let _ = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        
        return jsonString
    }

    private func buildPrompt(skillsJsonString: String, jobDescription: String) -> String {
        let prompt = """
        TASK:
        Analyze the provided skills and expertise items along with the job description. Reorder the skills to place the most relevant and impressive skills at the top of the list based on their relevance to the job requirements.

        CURRENT SKILLS AND EXPERTISE (in JSON format - contains just name, id, and current order):
        \(skillsJsonString)

        JOB DESCRIPTION:
        \(jobDescription)

        RESPONSE REQUIREMENTS:
        - You MUST respond with a valid JSON object containing exactly one field: "reordered_skills_and_expertise"
        - This field must contain an array of skill objects
        - Each skill object must have exactly these fields:
          * "id": The exact UUID string from the input (do not modify)
          * "originalValue": The original skill name from the input
          * "newPosition": The recommended new position (0-based index, starting from 0)
          * "reasonForReordering": Brief explanation of why this position is appropriate
        - Order the skills from most relevant (position 0) to least relevant
        - Do not add or remove any skills, only reorder them
        - Do not include any text, comments, or explanations outside the JSON object
        - Your entire response must be a valid JSON structure

        Example response format:
        {
          "reordered_skills_and_expertise": [
            {
              "id": "00000000-0000-0000-0000-000000000000",
              "originalValue": "Skill Name",
              "newPosition": 0,
              "reasonForReordering": "This skill directly matches the primary requirement..."
            }
          ]
        }
        """

        return prompt
    }
}
