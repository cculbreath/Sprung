//
//  GoogleAIService.swift
//  Sprung
//
//  Direct integration with Google's Generative AI API for PDF extraction.
//  Uses the Files API for large file uploads, bypassing OpenRouter limitations.
//

import Foundation

/// Service for interacting with Google's Generative AI API directly
actor GoogleAIService {

    // MARK: - Types

    /// Token usage from a Gemini API response
    struct GeminiTokenUsage {
        let promptTokenCount: Int
        let candidatesTokenCount: Int
        let totalTokenCount: Int
    }

    struct GeminiModel: Identifiable, Hashable {
        let id: String
        let displayName: String
        let description: String
        let inputTokenLimit: Int
        let outputTokenLimit: Int
        let supportsPDFs: Bool

        var name: String { id }
    }

    struct UploadedFile {
        let name: String
        let uri: String
        let mimeType: String
        let sizeBytes: Int64
        let state: String
    }

    enum GoogleAIError: LocalizedError {
        case noAPIKey
        case uploadFailed(String)
        case generateFailed(String)
        case fileProcessing(String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "Google API key not configured. Add it in Settings."
            case .uploadFailed(let msg):
                return "File upload failed: \(msg)"
            case .generateFailed(let msg):
                return "Content generation failed: \(msg)"
            case .fileProcessing(let state):
                return "File still processing: \(state)"
            case .invalidResponse:
                return "Invalid response from Google API"
            }
        }
    }

    // MARK: - Properties

    private let baseURL = "https://generativelanguage.googleapis.com"
    private let session: URLSession

    // MARK: - Initialization

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300 // 5 minutes for large uploads
        config.timeoutIntervalForResource = 600 // 10 minutes total
        self.session = URLSession(configuration: config)
    }

    // MARK: - API Key

    private func getAPIKey() throws -> String {
        guard let key = APIKeyManager.get(.gemini),
              !key.isEmpty else {
            throw GoogleAIError.noAPIKey
        }
        return key
    }

    // MARK: - Models API

    /// Fetch available Gemini models that support generateContent
    func fetchAvailableModels() async throws -> [GeminiModel] {
        let apiKey = try getAPIKey()
        let url = URL(string: "\(baseURL)/v1beta/models?key=\(apiKey)")!

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GoogleAIError.invalidResponse
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let modelsArray = json?["models"] as? [[String: Any]] else {
            return []
        }

        return modelsArray.compactMap { modelData -> GeminiModel? in
            guard let name = modelData["name"] as? String,
                  let displayName = modelData["displayName"] as? String,
                  let methods = modelData["supportedGenerationMethods"] as? [String],
                  methods.contains("generateContent") else {
                return nil
            }

            // Extract model ID from "models/gemini-2.0-flash" format
            let modelId = name.replacingOccurrences(of: "models/", with: "")

            // Filter for gemini models that likely support file input
            guard modelId.hasPrefix("gemini-") else { return nil }

            return GeminiModel(
                id: modelId,
                displayName: displayName,
                description: modelData["description"] as? String ?? "",
                inputTokenLimit: modelData["inputTokenLimit"] as? Int ?? 0,
                outputTokenLimit: modelData["outputTokenLimit"] as? Int ?? 0,
                supportsPDFs: true // All gemini models support file input
            )
        }
        .sorted { $0.displayName < $1.displayName }
    }

    // MARK: - Files API

    /// Upload a file to Google's Files API using resumable upload protocol
    func uploadFile(data: Data, mimeType: String, displayName: String) async throws -> UploadedFile {
        let apiKey = try getAPIKey()
        let uploadStart = Date()
        let sizeMB = Double(data.count) / 1_000_000

        // Step 1: Initiate resumable upload
        let initiateURL = URL(string: "\(baseURL)/upload/v1beta/files")!
        var initiateRequest = URLRequest(url: initiateURL)
        initiateRequest.httpMethod = "POST"
        initiateRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        initiateRequest.setValue("resumable", forHTTPHeaderField: "X-Goog-Upload-Protocol")
        initiateRequest.setValue("start", forHTTPHeaderField: "X-Goog-Upload-Command")
        initiateRequest.setValue("\(data.count)", forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length")
        initiateRequest.setValue(mimeType, forHTTPHeaderField: "X-Goog-Upload-Header-Content-Type")
        initiateRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let initiateBody: [String: Any] = ["file": ["display_name": displayName]]
        initiateRequest.httpBody = try JSONSerialization.data(withJSONObject: initiateBody)

        Logger.info("📤 Initiating file upload: \(displayName) (\(String(format: "%.1f", sizeMB)) MB)", category: .ai)

        let (_, initiateResponse) = try await session.data(for: initiateRequest)
        let initiateMs = Int(Date().timeIntervalSince(uploadStart) * 1000)
        Logger.debug("📤 Upload session initiated in \(initiateMs)ms", category: .ai)

        guard let httpResponse = initiateResponse as? HTTPURLResponse,
              let uploadURLString = httpResponse.value(forHTTPHeaderField: "X-Goog-Upload-URL"),
              let uploadURL = URL(string: uploadURLString) else {
            throw GoogleAIError.uploadFailed("Failed to get upload URL")
        }

        // Step 2: Upload file bytes using upload() for better large file performance
        let dataUploadStart = Date()
        var uploadRequest = URLRequest(url: uploadURL)
        uploadRequest.httpMethod = "POST"
        uploadRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        uploadRequest.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        uploadRequest.setValue("0", forHTTPHeaderField: "X-Goog-Upload-Offset")
        uploadRequest.setValue("upload, finalize", forHTTPHeaderField: "X-Goog-Upload-Command")

        let (uploadData, uploadResponse) = try await session.upload(for: uploadRequest, from: data)
        let uploadMs = Int(Date().timeIntervalSince(dataUploadStart) * 1000)
        let speedMBps = sizeMB / (Double(uploadMs) / 1000)
        Logger.info("📤 File data uploaded in \(uploadMs)ms (\(String(format: "%.1f", speedMBps)) MB/s)", category: .ai)

        guard let uploadHttpResponse = uploadResponse as? HTTPURLResponse,
              uploadHttpResponse.statusCode == 200 else {
            let errorMsg = String(data: uploadData, encoding: .utf8) ?? "Unknown error"
            throw GoogleAIError.uploadFailed(errorMsg)
        }

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: uploadData) as? [String: Any],
              let fileInfo = json["file"] as? [String: Any],
              let name = fileInfo["name"] as? String,
              let uri = fileInfo["uri"] as? String else {
            throw GoogleAIError.invalidResponse
        }

        let uploadedFile = UploadedFile(
            name: name,
            uri: uri,
            mimeType: fileInfo["mimeType"] as? String ?? mimeType,
            sizeBytes: (fileInfo["sizeBytes"] as? String).flatMap { Int64($0) } ?? Int64(data.count),
            state: fileInfo["state"] as? String ?? "ACTIVE"
        )

        Logger.info("✅ File uploaded: \(uploadedFile.name) -> \(uploadedFile.uri)", category: .ai)

        return uploadedFile
    }

    /// Wait for file to finish processing (state becomes ACTIVE)
    func waitForFileProcessing(fileName: String, maxWaitSeconds: Int = 60) async throws -> UploadedFile {
        let apiKey = try getAPIKey()
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < Double(maxWaitSeconds) {
            let url = URL(string: "\(baseURL)/v1beta/\(fileName)?key=\(apiKey)")!
            let (data, _) = try await session.data(from: url)

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let state = json["state"] as? String else {
                throw GoogleAIError.invalidResponse
            }

            if state == "ACTIVE" {
                return UploadedFile(
                    name: fileName,
                    uri: json["uri"] as? String ?? "",
                    mimeType: json["mimeType"] as? String ?? "",
                    sizeBytes: (json["sizeBytes"] as? String).flatMap { Int64($0) } ?? 0,
                    state: state
                )
            }

            if state == "FAILED" {
                throw GoogleAIError.fileProcessing("File processing failed")
            }

            // Wait before checking again
            try await Task.sleep(for: .seconds(2))
        }

        throw GoogleAIError.fileProcessing("Timeout waiting for file processing")
    }

    /// Delete a file from Google's Files API
    func deleteFile(fileName: String) async throws {
        let apiKey = try getAPIKey()
        let url = URL(string: "\(baseURL)/v1beta/\(fileName)?key=\(apiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            Logger.warning("⚠️ Failed to delete file: \(fileName)", category: .ai)
            return
        }

        Logger.info("🗑️ File deleted: \(fileName)", category: .ai)
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
            throw GoogleAIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            Logger.error("❌ Generate content failed: \(errorMsg)", category: .ai)
            throw GoogleAIError.generateFailed(errorMsg)
        }

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw GoogleAIError.invalidResponse
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

    // MARK: - Summarization API

    /// Generate a structured summary from extracted document text.
    /// Uses Gemini Flash-Lite for cost efficiency (~$0.005/doc).
    /// Returns structured JSON with summary, document type, time periods, skills, etc.
    /// Model can be configured in Settings > Onboarding Interview > Doc Summary Model.
    func generateSummary(
        content: String,
        filename: String,
        modelId: String? = nil
    ) async throws -> DocumentSummary {
        // Use setting-based model or fallback
        let effectiveModelId = modelId ?? UserDefaults.standard.string(forKey: "onboardingDocSummaryModelId") ?? "gemini-2.0-flash-lite"
        let apiKey = try getAPIKey()
        let url = URL(string: "\(baseURL)/v1beta/models/\(effectiveModelId):generateContent?key=\(apiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let summaryPrompt = DocumentExtractionPrompts.summaryPrompt(filename: filename, content: content)

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
                "maxOutputTokens": 4096
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        Logger.info("📝 Generating summary with \(effectiveModelId) for: \(filename)", category: .ai)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleAIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            Logger.error("❌ Summary generation failed: \(errorMsg)", category: .ai)
            throw GoogleAIError.generateFailed(errorMsg)
        }

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw GoogleAIError.invalidResponse
        }

        // Parse the JSON response
        let summary = try parseSummaryResponse(text)
        Logger.info("✅ Summary generated for \(filename) (\(summary.summary.count) chars)", category: .ai)

        return summary
    }

    /// Parse the summary JSON response
    private func parseSummaryResponse(_ text: String) throws -> DocumentSummary {
        // Try to extract JSON from the response (might be wrapped in markdown)
        var jsonString = text

        // Handle markdown code blocks
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

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw GoogleAIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(DocumentSummary.self, from: jsonData)
    }

    // MARK: - High-Level API

    /// Extract text from a PDF file using Google's Files API
    /// This is the main entry point for PDF extraction
    func extractTextFromPDF(
        pdfData: Data,
        filename: String,
        modelId: String,
        prompt: String? = nil,
        maxOutputTokens: Int? = nil
    ) async throws -> (title: String?, content: String, tokenUsage: GeminiTokenUsage?) {
        let extractionPrompt = prompt ?? DocumentExtractionPrompts.defaultExtractionPrompt
        let effectiveMaxOutputTokens = maxOutputTokens ?? 32768
        let maxChars = 250_000

        // Upload file
        let uploadedFile = try await uploadFile(
            data: pdfData,
            mimeType: "application/pdf",
            displayName: filename
        )

        // Wait for processing if needed
        var activeFile = uploadedFile
        if uploadedFile.state != "ACTIVE" {
            activeFile = try await waitForFileProcessing(fileName: uploadedFile.name)
        }

        defer {
            // Clean up uploaded file
            Task {
                try? await self.deleteFile(fileName: activeFile.name)
            }
        }

        // Generate content
        let (result, tokenUsage) = try await extractPDFContent(
            fileURI: activeFile.uri,
            mimeType: "application/pdf",
            modelId: modelId,
            prompt: extractionPrompt,
            maxOutputTokens: effectiveMaxOutputTokens
        )

        // Try to parse as JSON for title extraction
        if let jsonData = result.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            let title = json["title"] as? String
            let content = json["content"] as? String ?? result
            let capped = capExtractionContent(content, maxChars: maxChars)
            return (title, capped.content, tokenUsage)
        }

        // If not valid JSON, try to extract from markdown code block
        if result.contains("```json") {
            let pattern = "```json\\s*([\\s\\S]*?)```"
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
               let jsonRange = Range(match.range(at: 1), in: result) {
                let jsonString = String(result[jsonRange])
                if let jsonData = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    let title = json["title"] as? String
                    let content = json["content"] as? String ?? result
                    let capped = capExtractionContent(content, maxChars: maxChars)
                    return (title, capped.content, tokenUsage)
                }
            }
        }

        let capped = capExtractionContent(result, maxChars: maxChars)
        return (nil, capped.content, tokenUsage)
    }

    private func capExtractionContent(_ content: String, maxChars: Int) -> (content: String, originalChars: Int, wasTruncated: Bool) {
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

    // MARK: - Generic Structured JSON Generation

    /// Generate structured JSON output from a prompt using Gemini's native structured output mode.
    /// When a schema is provided, uses `responseMimeType: "application/json"` and `responseJsonSchema`
    /// to guarantee schema-conforming JSON output.
    ///
    /// - Parameters:
    ///   - prompt: The prompt text describing what to extract/generate
    ///   - modelId: Gemini model ID (defaults to flash-lite)
    ///   - temperature: Generation temperature (default 0.2 for consistent JSON)
    ///   - jsonSchema: Optional JSON Schema dictionary. When provided, enables native structured output.
    /// - Returns: Raw JSON string response guaranteed to match the schema
    func generateStructuredJSON(
        prompt: String,
        modelId: String? = nil,
        temperature: Double = 0.2,
        jsonSchema: [String: Any]? = nil
    ) async throws -> String {
        let effectiveModelId = modelId ?? UserDefaults.standard.string(forKey: "onboardingDocSummaryModelId") ?? "gemini-2.0-flash-lite"
        let apiKey = try getAPIKey()
        let url = URL(string: "\(baseURL)/v1beta/models/\(effectiveModelId):generateContent?key=\(apiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build generation config
        var generationConfig: [String: Any] = [
            "temperature": temperature,
            "maxOutputTokens": 8192
        ]

        // If schema provided, use native structured output mode
        if let schema = jsonSchema {
            generationConfig["responseMimeType"] = "application/json"
            generationConfig["responseSchema"] = schema
            Logger.info("📝 Using Gemini native structured output with schema", category: .ai)
        }

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

        Logger.info("📝 Generating structured JSON with \(effectiveModelId)", category: .ai)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleAIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            Logger.error("❌ Structured JSON generation failed: \(errorMsg)", category: .ai)
            throw GoogleAIError.generateFailed(errorMsg)
        }

        // Parse response to extract text
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw GoogleAIError.invalidResponse
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

    /// Generate structured JSON from a PDF using Gemini's native structured output mode.
    /// Uploads the PDF via Files API, processes with schema enforcement, and returns valid JSON.
    /// - Parameters:
    ///   - pdfData: The raw PDF data
    ///   - filename: Display name for the file
    ///   - prompt: The prompt describing what to extract
    ///   - jsonSchema: JSON Schema dictionary for structured output
    ///   - modelId: Gemini model ID (defaults to flash)
    ///   - temperature: Generation temperature (default 0.2)
    /// - Returns: Tuple of (JSON string, token usage)
    func generateStructuredJSONFromPDF(
        pdfData: Data,
        filename: String,
        prompt: String,
        jsonSchema: [String: Any],
        modelId: String? = nil,
        temperature: Double = 0.2
    ) async throws -> (jsonString: String, tokenUsage: GeminiTokenUsage?) {
        let effectiveModelId = modelId ?? UserDefaults.standard.string(forKey: "onboardingDocSummaryModelId") ?? "gemini-2.0-flash"
        let apiKey = try getAPIKey()

        // Step 1: Upload PDF to Files API
        Logger.info("📤 Uploading PDF for structured analysis: \(filename)", category: .ai)
        let uploadedFile = try await uploadFile(data: pdfData, mimeType: "application/pdf", displayName: filename)

        // Step 2: Wait for file to be ready if needed
        var fileURI = uploadedFile.uri
        if uploadedFile.state != "ACTIVE" {
            Logger.info("⏳ Waiting for file processing...", category: .ai)
            let readyFile = try await waitForFileProcessing(fileName: uploadedFile.name)
            fileURI = readyFile.uri
        }

        defer {
            // Clean up uploaded file after processing
            Task {
                try? await self.deleteFile(fileName: uploadedFile.name)
            }
        }

        // Step 3: Generate content with structured output
        let url = URL(string: "\(baseURL)/v1beta/models/\(effectiveModelId):generateContent?key=\(apiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["file_data": ["mime_type": "application/pdf", "file_uri": fileURI]],
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": temperature,
                "maxOutputTokens": 16384,
                "responseMimeType": "application/json",
                "responseSchema": jsonSchema
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        Logger.info("📝 Generating structured JSON from PDF with \(effectiveModelId)", category: .ai)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleAIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            Logger.error("❌ Structured PDF analysis failed: \(errorMsg)", category: .ai)
            throw GoogleAIError.generateFailed(errorMsg)
        }

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw GoogleAIError.invalidResponse
        }

        // Parse token usage
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
            Logger.info("📊 Token usage: prompt=\(promptTokens), output=\(candidatesTokens), total=\(totalTokens)", category: .ai)
        }

        // Sanitize: Gemini sometimes returns U+23CE (⏎ RETURN SYMBOL) instead of actual newlines
        var jsonString = text.replacingOccurrences(of: "\u{23CE}", with: "\n")
        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        Logger.info("✅ Structured JSON from PDF generated (\(jsonString.count) chars)", category: .ai)

        return (jsonString, tokenUsage)
    }
}
