//
//  FixOverflowTypes.swift
//  PhysCloudResume
//
//  Created by Team on 5/13/25.
//

import Foundation
import PDFKit
import AppKit
import SwiftUI

/// Represents a single revised skill or expertise item from the LLM.
/// Mirrors ProposedRevisionNode but is specific to this feature's LLM call.
struct RevisedSkillNode: Codable, Equatable {
    var id: String
    var newValue: String
    var originalValue: String // Echoed back by LLM for context
    var treePath: String // Echoed back by LLM
    var isTitleNode: Bool // Echoed back by LLM

    enum CodingKeys: String, CodingKey {
        case id
        case newValue
        case originalValue
        case treePath
        case isTitleNode
    }
}

/// Container for the array of revised skills from the "fixFits" LLM call.
struct FixFitsResponseContainer: Codable, Equatable {
    var revisedSkillsAndExpertise: [RevisedSkillNode]

    enum CodingKeys: String, CodingKey {
        case revisedSkillsAndExpertise = "revised_skills_and_expertise"
    }
}

/// Response struct for the "contentsFit" LLM call.
struct ContentsFitResponse: Codable, Equatable {
    var contentsFit: Bool
    var overflowLineCount: Int

    enum CodingKeys: String, CodingKey {
        case contentsFit
        case overflowLineCount = "overflow_line_count"
    }
}

/// Container class for schema strings used in Fix Overflow feature
struct OverflowSchemas {
    /// Schema for 'fixFits' LLM request
    static let fixFitsSchemaString = """
    {
      "type": "object",
      "properties": {
        "revised_skills_and_expertise": {
          "type": "array",
          "description": "An array of objects, each representing a skill or expertise item with its original ID and revised content.",
          "items": {
            "type": "object",
            "properties": {
              "id": { 
                "type": "string", 
                "description": "The original ID of the TreeNode for the skill." 
              },
              "newValue": { 
                "type": "string", 
                "description": "The revised content for the skill/expertise item. If no change, this should be the same as originalValue." 
              },
              "originalValue": {
                 "type": "string",
                 "description": "The original content of the skill/expertise item (echoed back)."
               },
              "treePath": {
                "type": "string",
                "description": "The original treePath of the skill TreeNode (echoed back)."
              },
              "isTitleNode": {
                "type": "boolean",
                "description": "Indicates if this skill entry is a title/heading (echoed back)."
              }
            },
            "required": ["id", "newValue", "originalValue", "treePath", "isTitleNode"],
            "additionalProperties": false
          }
        }
      },
      "required": ["revised_skills_and_expertise"],
      "additionalProperties": false
    }
    """

    /// Schema for 'contentsFit' LLM request
    static let contentsFitSchemaString = """
    {
      "type": "object",
      "properties": {
        "contentsFit": { 
          "type": "boolean",
          "description": "True if the content fits within its designated box without overflowing or overlapping other elements, false otherwise."
        },
        "overflow_line_count": {
          "type": "integer",
          "description": "Estimated number of text lines that are overflowing or overlapping the content below. 0 if contentsFit is true, or if text overlaps bounding boxes but no actual text lines overflow."
        }
      },
      "required": ["contentsFit", "overflow_line_count"],
      "additionalProperties": false
    }
    """
}
