import Foundation
import SwiftOpenAI

// MARK: - Revision Stream Failure Classifier

/// Pure, dependency-free classifiers for revision-agent streaming failures.
///
/// Splits stream errors into *fatal* (configuration/auth/request problems that
/// retrying cannot heal) vs *transient* (rate limits, overload, server errors,
/// network drops), classifies in-stream Anthropic `error` events by their error
/// type, and detects JSON tool inputs truncated by a `max_tokens` stop. Holds no
/// instance state so the agent's retry/back-off logic stays independently testable.
enum RevisionStreamFailureClassifier {
    /// Fatal = configuration/auth/request problems that retrying cannot heal.
    /// Transient = rate limits, overload, server errors, network drops.
    static func classifyStreamFailure(_ error: Error) -> (isFatal: Bool, message: String) {
        if let apiError = error as? APIError {
            if case .responseUnsuccessful(_, let statusCode, _) = apiError {
                let transientCodes: Set<Int> = [408, 429, 500, 502, 503, 504, 529]
                return (isFatal: !transientCodes.contains(statusCode), message: apiError.displayDescription)
            }
            return (isFatal: false, message: apiError.displayDescription)
        }
        if let llmError = error as? LLMError {
            switch llmError {
            case .clientError, .unauthorized, .invalidModelId:
                return (isFatal: true, message: llmError.localizedDescription)
            case .decodingFailed, .unexpectedResponseFormat, .rateLimited, .timeout, .insufficientCredits:
                return (isFatal: false, message: llmError.localizedDescription)
            }
        }
        return (isFatal: false, message: error.localizedDescription)
    }

    /// Classify an in-stream `error` event by its Anthropic error type.
    static func isFatalStreamErrorEvent(_ message: String) -> Bool {
        let fatalTypes = [
            "authentication_error",
            "permission_error",
            "invalid_request_error",
            "not_found_error",
            "request_too_large"
        ]
        return fatalTypes.contains { message.contains($0) }
    }

    /// True when `raw` parses as a complete JSON value — used to detect tool
    /// inputs truncated by a max_tokens stop.
    static func isCompleteJSONObject(_ raw: String) -> Bool {
        guard let data = raw.data(using: .utf8), !data.isEmpty else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }
}
