//
//  GoogleContentGenerator.swift
//  Sprung
//
//  Handles Google Gemini content generation operations.
//  Extracted from GoogleAIService for single responsibility.
//

import Foundation

/// Service for generating content using Google's Gemini models
actor GoogleContentGenerator {

    // MARK: - Types

    /// Token usage from a Gemini API response
    struct GeminiTokenUsage {
        let promptTokenCount: Int
        let candidatesTokenCount: Int
        let totalTokenCount: Int
    }

    enum ContentGeneratorError: LocalizedError {
        case noAPIKey
        case generateFailed(String)
        case invalidResponse
        /// Extraction blocked due to non-STOP finish reason (e.g., RECITATION, MAX_TOKENS)
        case extractionBlocked(finishReason: String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "Google API key not configured. Add it in Settings."
            case .generateFailed(let msg):
                return "Content generation failed: \(msg)"
            case .invalidResponse:
                return "Invalid response from Google API"
            case .extractionBlocked(let finishReason):
                return "Extraction blocked by Gemini: \(finishReason)"
            }
        }
    }

    // MARK: - Properties

    private let baseURL = "https://generativelanguage.googleapis.com"
    private let session: URLSession

    // MARK: - Initialization

    init(session: URLSession? = nil) {
        if let session = session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 600  // 10 min for heavy thinking models
            config.timeoutIntervalForResource = 900
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - API Key

    private func getAPIKey() throws -> String {
        guard let key = APIKeyManager.get(.gemini),
              !key.isEmpty else {
            throw ContentGeneratorError.noAPIKey
        }
        return key
    }

    // MARK: - Generate Content

    /// Extract content from a PDF using the uploaded file reference
    func extractPDFContent(
        fileURI: String,
        mimeType: String,
        modelId: String,
        prompt: String,
        maxOutputTokens: Int
    ) async throws -> (content: String, tokenUsage: GeminiTokenUsage?) {
        let apiKey = try getAPIKey()
        let url = URL(string: "\(baseURL)/v1beta/models/\(modelId):generateContent?key=\(apiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["file_data": ["mime_type": mimeType, "file_uri": fileURI]],
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "maxOutputTokens": maxOutputTokens
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        Logger.info("🤖 Generating content with \(modelId)...", category: .ai)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ContentGeneratorError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            Logger.error("❌ Generate content failed: \(errorMsg)", category: .ai)
            throw ContentGeneratorError.generateFailed(errorMsg)
        }

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw ContentGeneratorError.invalidResponse
        }

        // Parse token usage from usageMetadata
        var tokenUsage: GeminiTokenUsage?
        if let usageMetadata = json["usageMetadata"] as? [String: Any] {
            let promptTokens = usageMetadata["promptTokenCount"] as? Int ?? 0
            let candidatesTokens = usageMetadata["candidatesTokenCount"] as? Int ?? 0
            let totalTokens = usageMetadata["totalTokenCount"] as? Int ?? 0
            tokenUsage = GeminiTokenUsage(
                promptTokenCount: promptTokens,
                candidatesTokenCount: candidatesTokens,
                totalTokenCount: totalTokens
            )
            Logger.info("📊 Token usage: prompt=\(promptTokens), candidates=\(candidatesTokens), total=\(totalTokens)", category: .ai)
        }

        Logger.info("✅ Content generated successfully (\(text.count) chars)", category: .ai)

        return (text, tokenUsage)
    }

    // MARK: - Utilities

    /// Cap extraction content with head/tail truncation
    func capExtractionContent(_ content: String, maxChars: Int) -> (content: String, originalChars: Int, wasTruncated: Bool) {
        let originalChars = content.count
        guard originalChars > maxChars else {
            return (content, originalChars, false)
        }

        Logger.warning(
            "⚠️ PDF extraction content exceeds cap; truncating tool output",
            category: .ai,
            metadata: [
                "original_chars": "\(originalChars)",
                "max_chars": "\(maxChars)"
            ]
        )

        let headChars = Int(Double(maxChars) * 0.6)
        let tailChars = max(0, maxChars - headChars - 200)

        let head = String(content.prefix(headChars))
        let tail = tailChars > 0 ? String(content.suffix(tailChars)) : ""
        let marker = "\n\n[... TRUNCATED: original_chars=\(originalChars), max_chars=\(maxChars) ...]\n\n"
        return (head + marker + tail, originalChars, true)
    }
}
