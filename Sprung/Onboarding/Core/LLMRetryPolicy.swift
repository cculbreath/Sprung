//
//  LLMRetryPolicy.swift
//  Sprung
//
//  Handles retry logic for LLM operations.
//  Extracted from LLMMessenger for single responsibility.
//

import Foundation
import SwiftOpenAI

/// Handles retry decisions and delays for LLM operations
struct LLMRetryPolicy {
    let maxRetries: Int

    init(maxRetries: Int = 3) {
        self.maxRetries = maxRetries
    }

    /// Check if an error is retriable
    func isRetriable(_ error: Error) -> Bool {
        if let apiError = error as? APIError {
            switch apiError {
            case .responseUnsuccessful(_, let statusCode, _):
                return statusCode == 503 || statusCode == 502 || statusCode == 504 || statusCode >= 500
            case .jsonDecodingFailure, .bothDecodingStrategiesFailed:
                return true
            case .timeOutError:
                return true
            case .requestFailed, .invalidData, .dataCouldNotBeReadMissingData:
                return false
            }
        }

        let errorDescription = error.localizedDescription.lowercased()
        if errorDescription.contains("network") ||
           errorDescription.contains("connection") ||
           errorDescription.contains("timeout") ||
           errorDescription.contains("lost connection") {
            return true
        }

        if error is CancellationError {
            return false
        }

        return false
    }

    /// Calculate delay for retry attempt (exponential backoff)
    func retryDelay(for attempt: Int) -> Double {
        return Double(attempt) * 2.0 // 2s, 4s, 6s
    }

    /// Check if should retry based on attempt count
    func shouldRetry(attempt: Int) -> Bool {
        return attempt < maxRetries
    }
}
