//
//  CardMergePrompts.swift
//  Sprung
//
//  Prompt builder for cross-document card merging.
//

import Foundation
import SwiftyJSON

/// Builds prompts for cross-document card merging
enum CardMergePrompts {

    /// Build the merge prompt for multiple document inventories
    /// - Parameters:
    ///   - inventories: Array of DocumentInventory from all documents
    ///   - timeline: Optional skeleton timeline for employment context
    /// - Returns: Formatted prompt string
    static func mergePrompt(
        inventories: [DocumentInventory],
        timeline: JSON?
    ) -> String {
        // Encode inventories to JSON string
        let inventoriesJSON: String
        if let data = try? JSONEncoder().encode(inventories),
           let jsonString = String(data: data, encoding: .utf8) {
            inventoriesJSON = jsonString
        } else {
            inventoriesJSON = "[]"
        }

        // Convert timeline to string
        let timelineJSON: String
        if let timeline = timeline {
            timelineJSON = timeline.rawString() ?? "{}"
        } else {
            timelineJSON = "{}"
        }

        return PromptLibrary.substitute(
            template: PromptLibrary.crossDocumentMergeTemplate,
            replacements: [
                "INVENTORIES_JSON": inventoriesJSON,
                "TIMELINE_JSON": timelineJSON
            ]
        )
    }
}
