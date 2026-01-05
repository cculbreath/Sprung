//
//  LLMErrorHandler.swift
//  Sprung
//
//  Handles error display and user alerts for LLM operations.
//  Extracted from LLMMessenger for single responsibility.
//

import AppKit
import Foundation
import SwiftOpenAI
import SwiftyJSON

/// Handles error display and user alerts for LLM operations
struct LLMErrorHandler {

    /// Build a user-friendly error message from an error
    func buildUserFriendlyMessage(from error: Error) -> String {
        let errorDescription = error.localizedDescription

        if errorDescription.contains("network") || errorDescription.contains("connection") {
            return "I'm having trouble connecting to the AI service. Please check your network connection and try again."
        } else if errorDescription.contains("401") || errorDescription.contains("403") {
            return "There's an authentication issue with the AI service. Please check your API key and try again."
        } else if errorDescription.contains("429") {
            return "The AI service is currently rate-limited. Please wait a moment and try again."
        } else if errorDescription.contains("500") || errorDescription.contains("503") {
            return "The AI service is temporarily unavailable. Please try again in a few moments."
        } else {
            return "I encountered an error while processing your request: \(errorDescription). Please try again, or contact support if this persists."
        }
    }

    /// Check if error is an insufficient credits error
    func isInsufficientCreditsError(_ error: Error) -> Bool {
        if let llmError = error as? LLMError {
            if case .insufficientCredits = llmError {
                return true
            }
        }

        let errorDescription = error.localizedDescription
        return errorDescription.contains("402") || errorDescription.lowercased().contains("insufficient credits")
    }

    /// Extract credit info from insufficient credits error
    func extractCreditInfo(from error: Error) -> (requested: Int, available: Int)? {
        if let llmError = error as? LLMError {
            if case .insufficientCredits(let requested, let available) = llmError {
                return (requested, available)
            }
        }
        return nil
    }

    /// Show a popup alert for insufficient OpenRouter credits
    @MainActor
    func showInsufficientCreditsAlert(requested: Int, available: Int) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Insufficient OpenRouter Credits"

        if requested > 0 && available > 0 {
            alert.informativeText = """
            This request requires more credits than available.

            Requested: \(requested.formatted()) tokens
            Available: \(available.formatted()) tokens

            Please add credits at OpenRouter to continue using the AI features.
            """
        } else {
            alert.informativeText = """
            Your OpenRouter account has insufficient credits to complete this request.

            Please add credits at OpenRouter to continue using the AI features.
            """
        }

        alert.addButton(withTitle: "Add Credits")
        alert.addButton(withTitle: "OK")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "https://openrouter.ai/settings/credits") {
                NSWorkspace.shared.open(url)
            }
        }

        Logger.warning("💳 Insufficient credits alert shown to user (requested: \(requested), available: \(available))", category: .ai)
    }

    /// Show alert for conversation sync error when auto-recovery fails
    @MainActor
    func showConversationSyncErrorAlert(callId: String?) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Conversation Recovery Failed"
        alert.informativeText = """
        The AI conversation could not be recovered automatically.

        Your interview data (profile, knowledge cards, timeline) is safely saved.

        You may need to restart the interview. Your collected data will be preserved.
        """

        if let callId = callId {
            alert.informativeText += "\n\nTechnical: call_id: \(callId)"
        }

        alert.addButton(withTitle: "OK")
        _ = alert.runModal()

        Logger.error("🔧 Conversation sync error alert shown - auto-recovery failed (callId: \(callId ?? "unknown"))", category: .ai)
    }

    /// Log detailed error information for Anthropic API errors
    func logAnthropicError(_ error: Error, context: String) {
        Logger.error("❌ Anthropic API error in \(context)", category: .ai)

        if let apiError = error as? APIError {
            switch apiError {
            case .responseUnsuccessful(let description, let statusCode, let responseBody):
                Logger.error("   Status: \(statusCode)", category: .ai)
                Logger.error("   Description: \(description)", category: .ai)
                if let body = responseBody, !body.isEmpty {
                    Logger.error("   Response body: \(body)", category: .ai)
                } else {
                    Logger.error("   Response body: (empty)", category: .ai)
                }
            case .requestFailed(let description):
                Logger.error("   Request failed: \(description)", category: .ai)
            case .jsonDecodingFailure(let description):
                Logger.error("   JSON decoding failure: \(description)", category: .ai)
            case .bothDecodingStrategiesFailed:
                Logger.error("   Both decoding strategies failed", category: .ai)
            case .invalidData:
                Logger.error("   Invalid data", category: .ai)
            case .dataCouldNotBeReadMissingData(let description):
                Logger.error("   Missing data: \(description)", category: .ai)
            case .timeOutError:
                Logger.error("   Timeout", category: .ai)
            }
        } else {
            Logger.error("   Error type: \(type(of: error))", category: .ai)
            Logger.error("   Full error: \(error)", category: .ai)
        }
    }
}
