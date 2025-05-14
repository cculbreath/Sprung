//
//  ReorderSkillsTypes.swift
//  PhysCloudResume
//
//  Created by Team on 5/14/25.
//

import Foundation

/// Represents a skill node with reordering information from the LLM
struct ReorderedSkillNode: Codable, Equatable {
    var id: String
    var originalValue: String // Echoed back by LLM for context
    var newPosition: Int // New position in the ordered list (0-based index)
    var reasonForReordering: String // Brief explanation for the reordering
    var isTitleNode: Bool // Echoed back by LLM
    var treePath: String // Echoed back by LLM

    enum CodingKeys: String, CodingKey {
        case id
        case originalValue
        case newPosition
        case reasonForReordering
        case isTitleNode
        case treePath
    }
}

/// Container for the array of reordered skills from the LLM
struct ReorderSkillsResponseContainer: Codable, Equatable {
    var reorderedSkillsAndExpertise: [ReorderedSkillNode]

    enum CodingKeys: String, CodingKey {
        case reorderedSkillsAndExpertise = "reordered_skills_and_expertise"
    }
}

/// JSON schema for the reordering skills LLM request
extension OverflowSchemas {
    static let reorderSkillsSchemaString = """
    {
      "type": "object",
      "properties": {
        "reordered_skills_and_expertise": {
          "type": "array",
          "description": "An array of objects, each representing a skill or expertise item in the optimal new order.",
          "items": {
            "type": "object",
            "properties": {
              "id": { 
                "type": "string", 
                "description": "The original ID of the TreeNode for the skill." 
              },
              "originalValue": {
                 "type": "string",
                 "description": "The original content of the skill/expertise item."
               },
              "newPosition": { 
                "type": "integer", 
                "description": "The recommended new position (0-based index) for this skill/expertise item." 
              },
              "reasonForReordering": { 
                "type": "string", 
                "description": "Brief explanation of why this item should be at this position." 
              },
              "isTitleNode": {
                "type": "boolean",
                "description": "Indicates if this skill entry is a title/heading."
              },
              "treePath": {
                "type": "string",
                "description": "The original treePath of the skill TreeNode."
              }
            },
            "required": ["id", "originalValue", "newPosition", "reasonForReordering", "isTitleNode", "treePath"],
            "additionalProperties": false
          }
        }
      },
      "required": ["reordered_skills_and_expertise"],
      "additionalProperties": false
    }
    """
}