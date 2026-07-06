//
//  AnthropicTransientRetryPolicy.swift
//  Sprung
//
//  Classification + backoff for transient-failure retry on the direct Anthropic
//  request path (the facade chokepoints in `LLMFacadeSpecializedAPIs`). The
//  OpenRouter path has had this resilience for a long time via
//  `LLMRequestExecutor.withRetry`/`classifyRequestError`; this is the Anthropic
//  counterpart, kept as a pure value type so classification and backoff shape
//  are unit-testable without constructing any facade.
//
//  ONLY transient failures are retryable:
//  - URLError connect-level drops (timed out, connection lost, cannot connect,
//    DNS failures, offline)
//  - HTTP 5xx (which includes Anthropic's 529 overloaded_error)
//  - HTTP 429 rate limiting (retried with the same exponential backoff)
//  - the fork's `APIError.timeOutError`
//
//  Everything else is terminal and must propagate UNCHANGED on the first
//  failure — in particular Anthropic's raw HTTP 400 "credit balance is too low",
//  which `BudgetPauseGate`/`LLMErrorHandler.isInsufficientBalanceError` own
//  downstream, all other 4xx (validation/auth), decode failures (a mid-stream
//  drop surfacing as truncated JSON is recovered by resume, not blanket retry),
//  and cancellation.
//

import Foundation
import SwiftOpenAI

/// Retry classification and backoff for direct Anthropic requests.
struct AnthropicTransientRetryPolicy: Sendable {
    /// Total attempts (first try + retries). Small cap: this is a transient-blip
    /// recovery mechanism, not a wall-clock persistence mechanism.
    let maxAttempts: Int
    /// Backoff base for the delay before the second attempt; doubles per retry.
    let baseDelay: TimeInterval

    init(maxAttempts: Int = 3, baseDelay: TimeInterval = 1.0) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelay = max(0, baseDelay)
    }

    /// Classify an error: returns a short human-readable label (for the retry
    /// warning log) when the failure is transient and worth retrying, or nil
    /// when it is terminal and must propagate unchanged.
    static func transientLabel(for error: Error) -> String? {
        if error is CancellationError { return nil }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: return "URLError.timedOut"
            case .networkConnectionLost: return "URLError.networkConnectionLost"
            case .cannotConnectToHost: return "URLError.cannotConnectToHost"
            case .cannotFindHost: return "URLError.cannotFindHost"
            case .dnsLookupFailed: return "URLError.dnsLookupFailed"
            case .notConnectedToInternet: return "URLError.notConnectedToInternet"
            default: return nil
            }
        }

        if let apiError = error as? APIError {
            switch apiError {
            case .responseUnsuccessful(_, let statusCode, _):
                if statusCode == 429 { return "HTTP 429 rate limited" }
                if statusCode == 529 { return "HTTP 529 overloaded" }
                if (500...599).contains(statusCode) { return "HTTP \(statusCode) server error" }
                // All other statuses — including the insufficient-balance 400
                // that BudgetPauseGate intercepts downstream — are terminal.
                return nil
            case .timeOutError:
                return "request timeout"
            case .requestFailed, .invalidData, .jsonDecodingFailure,
                 .dataCouldNotBeReadMissingData, .bothDecodingStrategiesFailed:
                return nil
            }
        }

        return nil
    }

    /// Delay before the given attempt number (2-based: the delay slept after
    /// attempt `attempt - 1` failed). Exponential doubling with ±20% jitter so
    /// concurrent passes don't retry in lockstep: ~base, ~2·base, ~4·base, …
    func delay(beforeAttempt attempt: Int) -> TimeInterval {
        guard attempt >= 2 else { return 0 }
        let exponential = baseDelay * pow(2.0, Double(attempt - 2))
        return exponential * Double.random(in: 0.8...1.2)
    }
}
