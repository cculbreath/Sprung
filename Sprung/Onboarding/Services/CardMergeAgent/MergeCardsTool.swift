//
//  MergeCardsTool.swift
//  Sprung
//
//  Tool schema for spawning background merge sub-agents.
//  Delegates execution to BackgroundMergeAgent.
//

import Foundation

/// Tool schema for card merge operations
/// Delegates execution to BackgroundMergeAgent
struct MergeCardsTool: AgentTool {
    static let name = "merge_cards"
    static let description = """
        Spawn a background agent to merge 2 or more cards into one.
        The background agent will read the cards, synthesize a merged narrative,
        write the new card, and delete the source cards.
        Returns immediately so you can continue analyzing other cards.
        Use this when you've identified duplicates and want to merge them efficiently.
        """

    static let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "cardFiles": [
                "type": "array",
                "items": ["type": "string"],
                "minItems": 2,
                "description": "Paths to card files to merge (e.g., ['cards/uuid1.json', 'cards/uuid2.json'])"
            ],
            "mergeReason": [
                "type": "string",
                "description": "Brief explanation of why these cards should be merged (e.g., 'Same project with different names')"
            ]
        ],
        "required": ["cardFiles", "mergeReason"],
        "additionalProperties": false
    ]

    struct Parameters: Codable {
        let cardFiles: [String]
        let mergeReason: String
    }
}
