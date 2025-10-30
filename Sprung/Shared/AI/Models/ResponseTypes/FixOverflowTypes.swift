//
//  FixOverflowTypes.swift
//  Sprung
//
//  Created by Team on 5/13/25.
//

import Foundation
import PDFKit
import AppKit
import SwiftUI

/// Represents a single revised skill or expertise item from the LLM.
/// Each skill node contains both title (name) and description (value)
struct RevisedSkillNode: Codable, Equatable {
    var id: String
    var newTitle: String?  // New title if changed
    var newDescription: String?  // New description if changed
    enum CodingKeys: String, CodingKey {
        case id
        case newTitle = "new_title"
        case newDescription = "new_description"
    }
}

/// Represents a merge operation where two skill entries are combined
/// Each skill is a single node with both title (name) and description (value)
struct MergeOperation: Codable, Equatable {
    var skillToKeepId: String  // ID of the skill node to keep
    var skillToDeleteId: String  // ID of the skill node to delete
    var mergedTitle: String  // The combined title
    var mergedDescription: String  // The combined description
    var mergeReason: String

    enum CodingKeys: String, CodingKey {
        case skillToKeepId = "skill_to_keep_id"
        case skillToDeleteId = "skill_to_delete_id"
        case mergedTitle = "merged_title"
        case mergedDescription = "merged_description"
        case mergeReason = "merge_reason"
    }
}

/// Container for the array of revised skills from the "fixFits" LLM call.
struct FixFitsResponseContainer: Codable, Equatable {
    var revisedSkillsAndExpertise: [RevisedSkillNode]
    var mergeOperation: MergeOperation?

    enum CodingKeys: String, CodingKey {
        case revisedSkillsAndExpertise = "revised_skills_and_expertise"
        case mergeOperation = "merge_operation"
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
