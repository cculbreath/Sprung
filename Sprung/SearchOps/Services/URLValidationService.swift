//
//  URLValidationService.swift
//  Sprung
//
//  Service for validating job source URLs.
//  Uses HEAD requests to minimize bandwidth while checking URL validity.
//

import Foundation

actor URLValidationService {
    private let session: URLSession
    private let timeoutInterval: TimeInterval

    init(timeoutInterval: TimeInterval = 10.0) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeoutInterval
        config.timeoutIntervalForResource = timeoutInterval
        self.session = URLSession(configuration: config)
        self.timeoutInterval = timeoutInterval
    }

    /// Validate a single URL
    func validate(urlString: String) async -> URLValidationResult {
        guard let url = URL(string: urlString) else {
            return URLValidationResult(
                url: urlString,
                isValid: false,
                statusCode: nil,
                error: "Invalid URL format"
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")

        do {
            let (_, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return URLValidationResult(
                    url: urlString,
                    isValid: false,
                    statusCode: nil,
                    error: "Invalid response type"
                )
            }

            let isValid = (200...399).contains(httpResponse.statusCode)
            return URLValidationResult(
                url: urlString,
                isValid: isValid,
                statusCode: httpResponse.statusCode,
                error: isValid ? nil : "HTTP \(httpResponse.statusCode)"
            )
        } catch let error as URLError {
            let errorMessage: String
            switch error.code {
            case .notConnectedToInternet:
                errorMessage = "No internet connection"
            case .timedOut:
                errorMessage = "Request timed out"
            case .cannotFindHost:
                errorMessage = "Host not found"
            case .cannotConnectToHost:
                errorMessage = "Cannot connect to host"
            case .secureConnectionFailed:
                errorMessage = "SSL/TLS error"
            default:
                errorMessage = error.localizedDescription
            }
            return URLValidationResult(
                url: urlString,
                isValid: false,
                statusCode: nil,
                error: errorMessage
            )
        } catch {
            return URLValidationResult(
                url: urlString,
                isValid: false,
                statusCode: nil,
                error: error.localizedDescription
            )
        }
    }

    /// Validate multiple URLs concurrently
    func validateBatch(_ urlStrings: [String], maxConcurrent: Int = 5) async -> [URLValidationResult] {
        await withTaskGroup(of: URLValidationResult.self) { group in
            var results: [URLValidationResult] = []
            var pending = urlStrings[...]

            // Start initial batch
            for _ in 0..<min(maxConcurrent, pending.count) {
                if let url = pending.popFirst() {
                    group.addTask {
                        await self.validate(urlString: url)
                    }
                }
            }

            // Process results and add more tasks
            for await result in group {
                results.append(result)

                if let url = pending.popFirst() {
                    group.addTask {
                        await self.validate(urlString: url)
                    }
                }
            }

            return results
        }
    }
}

struct URLValidationResult {
    let url: String
    let isValid: Bool
    let statusCode: Int?
    let error: String?

    var isNetworkError: Bool {
        statusCode == nil && error != nil
    }

    var isServerError: Bool {
        guard let code = statusCode else { return false }
        return code >= 500
    }

    var isClientError: Bool {
        guard let code = statusCode else { return false }
        return code >= 400 && code < 500
    }
}
