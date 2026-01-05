//
//  ToolRecoveryManager.swift
//  Sprung
//
//  Handles tool output recovery when conversation state becomes desynchronized.
//  Extracted from LLMMessenger for single responsibility.
//

import Foundation
import SwiftyJSON

/// Handles tool output recovery when conversation state becomes desynchronized
struct ToolRecoveryManager {

    /// Extract call_id from "No tool output found for function call <call_id>" error
    func extractCallIdFromError(_ errorDescription: String) -> String? {
        // Pattern: "No tool output found for function call call_XXXX"
        guard let range = errorDescription.range(of: "function call ") else { return nil }
        let afterPrefix = errorDescription[range.upperBound...]
        // Find end of call_id (next quote, period, or end)
        if let endRange = afterPrefix.rangeOfCharacter(from: CharacterSet(charactersIn: "\".,} ")) {
            return String(afterPrefix[..<endRange.lowerBound])
        }
        return String(afterPrefix)
    }

    /// Check if error is a "No tool output found" error
    func isToolOutputMissingError(_ error: Error) -> Bool {
        let errorDescription = String(describing: error)
        return errorDescription.contains("No tool output found for function call")
    }

    /// Build a synthetic tool output for recovery
    /// Note: "status" field is extracted by ConversationContextAssembler and sent to API
    /// Valid API statuses are: "in_progress", "completed", "incomplete"
    func buildSyntheticToolOutput() -> JSON {
        var toolOutput = JSON()
        toolOutput["status"].string = "incomplete"  // API-level status indicating tool didn't complete normally
        toolOutput["error"].string = "Tool execution was interrupted due to a sync issue. The system has recovered."
        toolOutput["recovered"].bool = true
        return toolOutput
    }
}
