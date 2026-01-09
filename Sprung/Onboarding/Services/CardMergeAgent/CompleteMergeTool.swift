//
//  CompleteMergeTool.swift
//  Sprung
//
//  Tool for signaling completion of the card merge operation.
//

import Foundation

// MARK: - Complete Merge Tool

struct CompleteMergeTool: AgentTool {
    static let name = "complete_merge"
    static let description = """
        Signal that the card merge operation is complete.
        Call this when you have finished identifying and merging all duplicate cards.
        Provide a log of all merge operations performed.
        """

    static let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "summary": [
                "type": "string",
                "description": "Brief summary of the merge operation (e.g., 'Merged 12 duplicate cards into 5')"
            ],
            "mergeLog": [
                "type": "array",
                "description": "Log of merge operations performed",
                "items": [
                    "type": "object",
                    "properties": [
                        "action": [
                            "type": "string",
                            "enum": ["merged", "kept"],
                            "description": "'merged' if cards were combined, 'kept' if card was unique"
                        ],
                        "sourceCardIds": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "UUIDs of the source cards that were merged or kept"
                        ],
                        "resultCardId": [
                            "type": "string",
                            "description": "UUID of the resulting card (same as source for 'kept', new UUID for 'merged')"
                        ],
                        "reasoning": [
                            "type": "string",
                            "description": "Brief explanation of why cards were merged (empty for 'kept')"
                        ]
                    ],
                    "required": ["action", "sourceCardIds", "resultCardId", "reasoning"]
                ]
            ]
        ],
        "required": ["summary", "mergeLog"],
        "additionalProperties": false
    ]

    struct MergeLogEntry: Codable {
        let action: String
        let sourceCardIds: [String]
        let resultCardId: String
        let reasoning: String
    }

    struct Parameters: Codable {
        let summary: String
        let mergeLog: [MergeLogEntry]
    }
}
