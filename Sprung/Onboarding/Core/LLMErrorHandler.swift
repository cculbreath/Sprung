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

    /// Check if an error is an exhausted-balance / insufficient-credits error.
    ///
    /// Covers both the OpenRouter-style 402 (mapped to `LLMError.insufficientCredits`,
    /// or carrying "402"/"insufficient credits") AND Anthropic's raw HTTP 400 whose
    /// body reads "Your credit balance is too low … Please go to Plans & Billing …".
    /// Onboarding talks to Anthropic directly via `AnthropicMessagesService`, so that
    /// 400 never passes through `LLMRequestExecutor` and never becomes an `LLMError`.
    func isInsufficientBalanceError(_ error: Error) -> Bool {
        if let llmError = error as? LLMError, case .insufficientCredits = llmError {
            return true
        }
        if let apiError = error as? APIError,
           case .responseUnsuccessful(_, let statusCode, let responseBody) = apiError {
            if statusCode == 402 { return true }
            if let body = responseBody, Self.descriptionIndicatesInsufficientBalance(body) {
                return true
            }
        }
        return Self.descriptionIndicatesInsufficientBalance(error.localizedDescription)
    }

    /// String predicate shared by the `Error` overload and the extraction-pass
    /// failure-label check (which only has the stringified failure in hand).
    static func descriptionIndicatesInsufficientBalance(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("402")
            || lowered.contains("insufficient")
            || lowered.contains("credit balance")
            || lowered.contains("plans & billing")
    }

    /// Check if an error is a request-timeout — a large PDF chunk whose
    /// time-to-first-byte exceeded `URLSession.timeoutIntervalForRequest`, or a
    /// pass that timed out mid-stream. Disjoint from the budget predicate: a
    /// timeout is recovered by waiting/retrying, not by topping up.
    ///
    /// Onboarding streams to Anthropic directly, so a timeout surfaces either as a
    /// `URLError.timedOut` or the fork's `APIError.timeOutError` — never an
    /// `LLMError` (that path is the OpenRouter executor, which onboarding bypasses).
    func isTimeoutError(_ error: Error) -> Bool {
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return true
        }
        if let apiError = error as? APIError, case .timeOutError = apiError {
            return true
        }
        return Self.descriptionIndicatesTimeout(error.localizedDescription)
    }

    /// String predicate shared by the `Error` overload and the extraction-pass
    /// failure-label check. Kept DISJOINT from the budget predicate so a timed-out
    /// pass never routes to the top-up modal and vice versa.
    ///
    /// Covers `URLError.timedOut` ("the request timed out") and the fork's
    /// `APIError.timeOutError`, whose `localizedDescription` is "Time Out Error."
    /// (so a pass-failure label built from it is still recognized).
    static func descriptionIndicatesTimeout(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("timed out")
            || lowered.contains("timeout")
            || lowered.contains("time out")
    }

    /// True ONLY for transient conditions worth an automatic retry — a dropped or
    /// unreachable connection, a timeout, a rate-limit, or a 5xx/overloaded server.
    /// Everything else (malformed/schema responses, decode failures, 400/402/403
    /// content errors, model-config errors) is NON-transient: an extraction pass
    /// must NOT blanket-retry those — a retry re-fails identically and just re-burns
    /// tokens, so the pass should surface the failure and stop.
    ///
    /// Note: a connection dropped MID-STREAM can surface as a decode error
    /// ("unexpected end of file"), not a `URLError` — that is deliberately NOT
    /// treated as transient here. Recovery for it is resume, not a pass retry.
    func isTransientNetworkError(_ error: Error) -> Bool {
        if isTimeoutError(error) { return true }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost,
                 .cannotFindHost, .dnsLookupFailed, .resourceUnavailable,
                 .secureConnectionFailed, .cannotLoadFromNetwork:
                return true
            default:
                return false
            }
        }
        if let apiError = error as? APIError,
           case .responseUnsuccessful(_, let statusCode, _) = apiError {
            // 408 request-timeout, 429 rate-limit, 529 overloaded, any 5xx server error.
            return statusCode == 408 || statusCode == 429 || statusCode == 529
                || (500...599).contains(statusCode)
        }
        return Self.descriptionIndicatesTransientNetwork(error.localizedDescription)
    }

    /// String predicate mirroring `isTransientNetworkError` for callers that only
    /// hold a stringified failure. Matches the common URLError drop/offline phrasings.
    static func descriptionIndicatesTransientNetwork(_ text: String) -> Bool {
        let lowered = text.lowercased()
        if descriptionIndicatesTimeout(lowered) { return true }
        return lowered.contains("network connection was lost")
            || lowered.contains("connection was lost")
            || lowered.contains("not connected to the internet")
            || lowered.contains("cannot connect to host")
            || lowered.contains("network connection")
            || lowered.contains("appears to be offline")
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
