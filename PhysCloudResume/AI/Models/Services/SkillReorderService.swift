//
//  SkillReorderService.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 6/4/25.
//

import Foundation

/// Service for skill reordering using the unified LLM architecture
/// Replaces ReorderSkillsProvider with cleaner LLMService integration
@MainActor
class SkillReorderService {
    
    // MARK: - Dependencies
    private let llmService: LLMService
    
    // MARK: - Configuration
    private let systemPrompt = """
    You are an expert resume optimizer specializing in skills prioritization. Your task is to analyze a list of skills and expertise items and reorder them based on their relevance to a specific job description. Place the most relevant and impressive skills at the top of the list.

    IMPORTANT: Your response must be a valid JSON object conforming to the JSON schema provided. The id field for each skill must contain the exact UUID string from the input. Do not modify the UUID format in any way.

    IMPORTANT: Output ONLY the JSON object with the "reordered_skills_and_expertise" array. Do not include any additional commentary, explanation, or text outside the JSON.
    """
    
    init(llmService: LLMService) {
        self.llmService = llmService
    }
    
    // MARK: - Public Interface
    
    /// Fetch skill reordering recommendations using LLMService
    /// - Parameters:
    ///   - resume: The resume containing skills to reorder
    ///   - jobDescription: The job description to match against
    ///   - modelId: The model to use for skill reordering
    /// - Returns: Array of reordered skill nodes
    func fetchReorderedSkills(
        resume: Resume,
        jobDescription: String,
        modelId: String
    ) async throws -> [ReorderedSkillNode] {
        
        // Validate inputs
        guard !jobDescription.isEmpty else {
            throw SkillReorderError.noJobDescription
        }
        
        // Validate model capabilities
        try llmService.validateModel(modelId: modelId, for: [])
        
        // Extract skills JSON using existing TreeNodeExtractor
        guard let skillsJsonString = TreeNodeExtractor.shared.extractSkillsForReordering(resume: resume) else {
            throw SkillReorderError.skillExtractionFailed
        }
        
        // Build the reordering prompt
        let prompt = buildPrompt(skillsJsonString: skillsJsonString, jobDescription: jobDescription)
        
        // Debug logging if enabled
        if UserDefaults.standard.bool(forKey: "saveDebugPrompts") {
            saveDebugPrompt(content: prompt, fileName: "skillReorderPrompt.txt")
        }
        
        Logger.debug("🎯 Requesting skill reordering with model: \(modelId)")
        
        // Execute structured request
        let response = try await llmService.executeStructured(
            prompt: "\(systemPrompt)\n\n\(prompt)",
            modelId: modelId,
            responseType: ReorderSkillsResponse.self
        )
        
        // Validate response
        guard response.validate() else {
            throw SkillReorderError.invalidResponse("Failed validation")
        }
        
        // Convert to ReorderedSkillNode format expected by existing code
        let reorderedNodes = response.reorderedSkillsAndExpertise.map { simpleSkill in
            // Look up the original skill to get tree path and title node info
            let originalSkill = findOriginalSkill(with: simpleSkill.id, in: resume)
            return ReorderedSkillNode(
                id: simpleSkill.id,
                originalValue: simpleSkill.originalValue,
                newPosition: simpleSkill.newPosition,
                reasonForReordering: simpleSkill.reasonForReordering,
                isTitleNode: originalSkill?.isTitleNode ?? false,
                treePath: originalSkill?.treePath ?? ""
            )
        }
        
        Logger.debug("✅ Skill reordering successful: \(reorderedNodes.count) skills reordered")
        return reorderedNodes
    }
    
    // MARK: - Private Helpers
    
    /// Build the skill reordering prompt
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
    
    /// Find the original skill data for the given ID
    private func findOriginalSkill(with id: String, in resume: Resume) -> (isTitleNode: Bool, treePath: String)? {
        // Look up the skill in the resume's tree structure to get the original tree path and title info
        guard let node = resume.nodes.first(where: { $0.id == id }) else {
            return nil
        }
        
        // Determine if this is a title node by checking if it has children
        let isTitleNode = node.children?.isEmpty == false
        
        // Generate a simple tree path - for now just use the node's name
        // In a more sophisticated implementation, you'd walk up the tree to build a full path
        let treePath = node.name
        
        return (isTitleNode: isTitleNode, treePath: treePath)
    }
    
    /// Save debug prompt to file if debug mode is enabled
    private func saveDebugPrompt(content: String, fileName: String) {
        let fileManager = FileManager.default
        let homeDirectoryURL = fileManager.homeDirectoryForCurrentUser
        let downloadsURL = homeDirectoryURL.appendingPathComponent("Downloads")
        let fileURL = downloadsURL.appendingPathComponent(fileName)
        
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            Logger.debug("💾 Saved debug file: \(fileName)")
        } catch {
            Logger.warning("⚠️ Failed to save debug file \(fileName): \(error.localizedDescription)")
        }
    }
}

// MARK: - Supporting Types

/// Errors specific to skill reorder service
enum SkillReorderError: LocalizedError {
    case noJobDescription
    case skillExtractionFailed
    case invalidResponse(String)
    
    var errorDescription: String? {
        switch self {
        case .noJobDescription:
            return "No job description available"
        case .skillExtractionFailed:
            return "Failed to extract skills from resume"
        case .invalidResponse(let details):
            return "Invalid reorder response: \(details)"
        }
    }
}

// MARK: - Note: Using existing types from ReorderSkillsProvider
// - ReorderSkillsResponse (with reorderedSkillsAndExpertise property)
// - ReorderedSkillNode (the final output type)
// - TreeNodeExtractor.shared.extractSkillsForReordering()