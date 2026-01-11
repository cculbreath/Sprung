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
                "temperature": 0.1,
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

    // MARK: - Summarization

    /// Generate a structured summary from extracted document text.
    /// Uses Gemini Flash-Lite for cost efficiency (~$0.005/doc).
    /// Returns structured JSON with summary, document type, time periods, skills, etc.
    /// Model can be configured in Settings > Onboarding Interview > Doc Summary Model.
    /// Now uses Gemini's native structured output mode for guaranteed valid JSON.
    func generateSummary(
        content: String,
        filename: String,
        modelId: String? = nil
    ) async throws -> DocumentSummary {
        // Use setting-based model or fallback
        let effectiveModelId = modelId ?? UserDefaults.standard.string(forKey: "onboardingDocSummaryModelId") ?? DefaultModels.geminiLite
        let apiKey = try getAPIKey()
        let url = URL(string: "\(baseURL)/v1beta/models/\(effectiveModelId):generateContent?key=\(apiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let summaryPrompt = DocumentExtractionPrompts.summaryPrompt(filename: filename, content: content)

        // Use Gemini's native structured output mode with schema
        // Use high token limit to avoid truncation on large documents
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": summaryPrompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.2,
                "maxOutputTokens": 65536,
                "responseMimeType": "application/json",
                "responseSchema": DocumentExtractionPrompts.summaryJsonSchema
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        Logger.info("📝 Generating summary with \(effectiveModelId) (structured output) for: \(filename)", category: .ai)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ContentGeneratorError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            Logger.error("❌ Summary generation failed: \(errorMsg)", category: .ai)
            throw ContentGeneratorError.generateFailed(errorMsg)
        }

        // Parse response - with structured output, text is already valid JSON
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw ContentGeneratorError.invalidResponse
        }

        // Decode directly - structured output guarantees valid JSON matching schema
        guard let jsonData = text.data(using: .utf8) else {
            throw ContentGeneratorError.invalidResponse
        }

        let decoder = JSONDecoder()

        do {
            let summary = try decoder.decode(DocumentSummary.self, from: jsonData)
            Logger.info("✅ Summary generated for \(filename) (\(summary.summary.count) chars)", category: .ai)
            return summary
        } catch {
            Logger.error("❌ Failed to decode summary JSON: \(error.localizedDescription)", category: .ai)
            Logger.error("📝 Raw JSON: \(text.prefix(500))...", category: .ai)
            throw ContentGeneratorError.generateFailed("Failed to decode summary: \(error.localizedDescription)")
        }
    }

    // MARK: - Generic Structured JSON Generation

    /// Generate structured JSON output from a prompt using Gemini's native structured output mode.
    /// When a schema is provided, uses `responseMimeType: "application/json"` and `responseSchema`
    /// to guarantee schema-conforming JSON output.
    ///
    /// - Parameters:
    ///   - prompt: The prompt text describing what to extract/generate
    ///   - modelId: Gemini model ID (defaults to flash-lite)
    ///   - temperature: Generation temperature (default 0.2 for consistent JSON)
    ///   - maxOutputTokens: Maximum output tokens (default 65536 for large structured outputs)
    ///   - jsonSchema: Optional JSON Schema dictionary. When provided, enables native structured output.
    /// - Returns: Raw JSON string response guaranteed to match the schema
    func generateStructuredJSON(
        prompt: String,
        modelId: String? = nil,
        temperature: Double = 0.2,
        maxOutputTokens: Int = 65536,
        jsonSchema: [String: Any]? = nil
    ) async throws -> String {
        let effectiveModelId = modelId ?? UserDefaults.standard.string(forKey: "onboardingDocSummaryModelId") ?? DefaultModels.geminiLite
        let apiKey = try getAPIKey()
        let url = URL(string: "\(baseURL)/v1beta/models/\(effectiveModelId):generateContent?key=\(apiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build generation config
        var generationConfig: [String: Any] = [
            "temperature": temperature,
            "maxOutputTokens": maxOutputTokens
        ]

        // If schema provided, use native structured output mode
        if let schema = jsonSchema {
            generationConfig["responseMimeType"] = "application/json"
            generationConfig["responseSchema"] = schema
            Logger.info("📝 Using Gemini native structured output with schema (maxTokens: \(maxOutputTokens))", category: .ai)
        }

        // Models with "thinking" in the name REQUIRE thinking mode - must set a budget > 0
        if effectiveModelId.contains("thinking") {
            generationConfig["thinkingConfig"] = ["thinkingBudget": 8192]
            Logger.info("🧠 Using thinking mode for \(effectiveModelId) with budget 8192", category: .ai)
        }
        // Other models: accept server-side defaults

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": generationConfig
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        Logger.info("📝 Generating structured JSON with \(effectiveModelId) (starting network request...)", category: .ai)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
            Logger.info("📝 Gemini response received (\(data.count) bytes)", category: .ai)
        } catch {
            Logger.error("❌ Gemini network request failed: \(error.localizedDescription)", category: .ai)
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ContentGeneratorError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            Logger.error("❌ Structured JSON generation failed: \(errorMsg)", category: .ai)
            throw ContentGeneratorError.generateFailed(errorMsg)
        }

        // Parse response to extract text
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Logger.error("❌ Structured JSON: Failed to parse response as JSON", category: .ai)
            throw ContentGeneratorError.invalidResponse
        }

        guard let candidates = json["candidates"] as? [[String: Any]], !candidates.isEmpty else {
            // Log the full response to understand why there are no candidates
            let responseStr = String(data: data, encoding: .utf8) ?? "unable to decode"
            Logger.error("❌ Structured JSON: No candidates in response. Full response: \(responseStr.prefix(500))", category: .ai)
            throw ContentGeneratorError.invalidResponse
        }

        let firstCandidate = candidates[0]
        guard let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            Logger.error("❌ Structured JSON: Missing content/parts/text in candidate. Candidate keys: \(firstCandidate.keys)", category: .ai)
            throw ContentGeneratorError.invalidResponse
        }

        // Check finish reason - throw error for non-STOP to trigger fallback
        if let finishReason = firstCandidate["finishReason"] as? String, finishReason != "STOP" {
            Logger.warning("⚠️ Structured output failed: finishReason=\(finishReason)", category: .ai)
            throw ContentGeneratorError.extractionBlocked(finishReason: finishReason)
        }

        // Log token usage for debugging
        if let usageMetadata = json["usageMetadata"] as? [String: Any] {
            let promptTokens = usageMetadata["promptTokenCount"] as? Int ?? 0
            let candidatesTokens = usageMetadata["candidatesTokenCount"] as? Int ?? 0
            let totalTokens = usageMetadata["totalTokenCount"] as? Int ?? 0
            Logger.info("📊 Token usage: prompt=\(promptTokens), output=\(candidatesTokens), total=\(totalTokens)", category: .ai)
        }

        // When using structured output mode, response is already pure JSON
        // For legacy mode, extract from markdown if needed
        var jsonString = text
        if jsonSchema == nil {
            if text.contains("```json") {
                let pattern = "```json\\s*([\\s\\S]*?)```"
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                   let jsonRange = Range(match.range(at: 1), in: text) {
                    jsonString = String(text[jsonRange])
                }
            } else if text.contains("```") {
                let pattern = "```\\s*([\\s\\S]*?)```"
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                   let jsonRange = Range(match.range(at: 1), in: text) {
                    jsonString = String(text[jsonRange])
                }
            }
        }

        // Sanitize: Gemini sometimes returns U+23CE (⏎ RETURN SYMBOL) instead of actual newlines
        // This decorative character isn't valid JSON whitespace and causes decode failures
        jsonString = jsonString.replacingOccurrences(of: "\u{23CE}", with: "\n")

        Logger.info("✅ Structured JSON generated (\(jsonString.count) chars)", category: .ai)
        return jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
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
