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
        /// Extraction blocked due to non-STOP finish reason (e.g., RECITATION, MAX_TOKENS)
        case extractionBlocked(finishReason: String)

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
            case .extractionBlocked(let finishReason):
                return "Extraction blocked by Gemini: \(finishReason)"
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

    // MARK: - Image Analysis

    /// Analyze images using Gemini's vision capabilities with inline base64 data.
    /// Images are sent directly in the request body (no file upload needed).
    ///
    /// - Parameters:
    ///   - images: Array of image data (JPEG, PNG, WebP, HEIC, HEIF supported)
    ///   - prompt: The analysis prompt
    ///   - modelId: Gemini model ID (uses PDF extraction model setting if nil)
    ///   - temperature: Generation temperature (default 0.1 for consistent analysis)
    ///   - maxOutputTokens: Maximum output tokens (default 8192)
    /// - Returns: Text response from the model
    func analyzeImages(
        images: [Data],
        prompt: String,
        modelId: String? = nil,
        temperature: Double = 0.1,
        maxOutputTokens: Int = 8192
    ) async throws -> String {
        let effectiveModelId = modelId ?? UserDefaults.standard.string(forKey: "onboardingPDFExtractionModelId") ?? DefaultModels.gemini
        let apiKey = try getAPIKey()
        let url = URL(string: "\(baseURL)/v1beta/models/\(effectiveModelId):generateContent?key=\(apiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build parts array: images first, then text prompt (per Gemini best practices)
        var parts: [[String: Any]] = []

        for imageData in images {
            let base64String = imageData.base64EncodedString()
            // Detect MIME type from image data
            let mimeType = detectImageMimeType(imageData) ?? "image/jpeg"
            parts.append([
                "inline_data": [
                    "mime_type": mimeType,
                    "data": base64String
                ]
            ])
        }

        // Text prompt comes after images
        parts.append(["text": prompt])

        let requestBody: [String: Any] = [
            "contents": [
                ["parts": parts]
            ],
            "generationConfig": [
                "temperature": temperature,
                "maxOutputTokens": maxOutputTokens
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        Logger.info("🖼️ Analyzing \(images.count) image(s) with \(effectiveModelId)...", category: .ai)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleAIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            Logger.error("❌ Image analysis failed: \(errorMsg)", category: .ai)
            throw GoogleAIError.generateFailed(errorMsg)
        }

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let responseParts = content["parts"] as? [[String: Any]],
              let firstPart = responseParts.first,
              let text = firstPart["text"] as? String else {
            throw GoogleAIError.invalidResponse
        }

        Logger.info("✅ Image analysis complete (\(text.count) chars)", category: .ai)

        return text
    }

    /// Analyze images using Gemini's vision capabilities with structured JSON output.
    /// Uses native structured output mode with schema for guaranteed valid JSON.
    ///
    /// - Parameters:
    ///   - images: Array of image data (JPEG, PNG, WebP, HEIC, HEIF supported)
    ///   - prompt: The analysis prompt
    ///   - jsonSchema: JSON Schema dictionary for structured output
    ///   - modelId: Gemini model ID (uses PDF extraction model setting if nil)
    ///   - temperature: Generation temperature (default 0.1 for consistent analysis)
    /// - Returns: JSON string response guaranteed to match the schema
    func analyzeImagesStructured(
        images: [Data],
        prompt: String,
        jsonSchema: [String: Any],
        modelId: String? = nil,
        temperature: Double = 0.1
    ) async throws -> String {
        let effectiveModelId = modelId ?? UserDefaults.standard.string(forKey: "onboardingPDFExtractionModelId") ?? DefaultModels.gemini
        let apiKey = try getAPIKey()
        let url = URL(string: "\(baseURL)/v1beta/models/\(effectiveModelId):generateContent?key=\(apiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build parts array: images first, then text prompt
        var parts: [[String: Any]] = []

        for imageData in images {
            let base64String = imageData.base64EncodedString()
            let mimeType = detectImageMimeType(imageData) ?? "image/jpeg"
            parts.append([
                "inline_data": [
                    "mime_type": mimeType,
                    "data": base64String
                ]
            ])
        }

        parts.append(["text": prompt])

        let requestBody: [String: Any] = [
            "contents": [
                ["parts": parts]
            ],
            "generationConfig": [
                "temperature": temperature,
                "maxOutputTokens": 16384,
                "responseMimeType": "application/json",
                "responseSchema": jsonSchema
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        // Debug: log the generationConfig to verify schema is included
        if let genConfig = requestBody["generationConfig"] as? [String: Any] {
            let hasSchema = genConfig["responseSchema"] != nil
            Logger.info("🖼️ Analyzing \(images.count) image(s) with \(effectiveModelId) (structured output, hasSchema=\(hasSchema))...", category: .ai)
        } else {
            Logger.info("🖼️ Analyzing \(images.count) image(s) with \(effectiveModelId) (structured output)...", category: .ai)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleAIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            Logger.error("❌ Structured image analysis failed: \(errorMsg)", category: .ai)
            throw GoogleAIError.generateFailed(errorMsg)
        }

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let responseParts = content["parts"] as? [[String: Any]],
              let firstPart = responseParts.first,
              let text = firstPart["text"] as? String else {
            throw GoogleAIError.invalidResponse
        }

        Logger.info("✅ Structured image analysis complete (\(text.count) chars)", category: .ai)

        return text
    }

    /// Detect image MIME type from data header bytes
    private func detectImageMimeType(_ data: Data) -> String? {
        guard data.count >= 12 else { return nil }

        let bytes = [UInt8](data.prefix(12))

        // JPEG: starts with FF D8 FF
        if bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
            return "image/jpeg"
        }

        // PNG: starts with 89 50 4E 47
        if bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
            return "image/png"
        }

        // WebP: starts with RIFF....WEBP
        if bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
           bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50 {
            return "image/webp"
        }

        // HEIC/HEIF: check for ftyp box with heic/heif/mif1 brand
        if bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70 {
            return "image/heic"
        }

        return nil
    }

    // MARK: - Summarization API

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
            throw GoogleAIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            Logger.error("❌ Summary generation failed: \(errorMsg)", category: .ai)
            throw GoogleAIError.generateFailed(errorMsg)
        }

        // Parse response - with structured output, text is already valid JSON
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw GoogleAIError.invalidResponse
        }

        // Decode directly - structured output guarantees valid JSON matching schema
        guard let jsonData = text.data(using: .utf8) else {
            throw GoogleAIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            let summary = try decoder.decode(DocumentSummary.self, from: jsonData)
            Logger.info("✅ Summary generated for \(filename) (\(summary.summary.count) chars)", category: .ai)
            return summary
        } catch {
            Logger.error("❌ Failed to decode summary JSON: \(error.localizedDescription)", category: .ai)
            Logger.error("📝 Raw JSON: \(text.prefix(500))...", category: .ai)
            throw GoogleAIError.generateFailed("Failed to decode summary: \(error.localizedDescription)")
        }
    }

    // MARK: - High-Level API

    /// Generate text from a PDF using Gemini vision.
    /// Uploads the PDF via Files API, sends a prompt, and returns the extracted/generated text.
    /// Used for vision-based text extraction when PDFKit fails.
    /// - Parameters:
    ///   - pdfData: The PDF file data
    ///   - filename: Display name for logging
    ///   - prompt: The extraction/generation prompt
    ///   - modelId: Gemini model to use
    ///   - maxOutputTokens: Maximum output tokens
    /// - Returns: Tuple of (text, tokenUsage)
    func generateFromPDF(
        pdfData: Data,
        filename: String,
        prompt: String,
        modelId: String? = nil,
        maxOutputTokens: Int = 65536
    ) async throws -> (text: String, tokenUsage: GeminiTokenUsage?) {
        // Use configured model or default
        let effectiveModelId = modelId ?? UserDefaults.standard.string(forKey: "onboardingPDFExtractionModelId") ?? DefaultModels.gemini

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
        let (text, tokenUsage) = try await extractPDFContent(
            fileURI: activeFile.uri,
            mimeType: "application/pdf",
            modelId: effectiveModelId,
            prompt: prompt,
            maxOutputTokens: maxOutputTokens
        )

        Logger.info("📄 Vision extraction complete for \(filename) (\(text.count) chars)", category: .ai)

        return (text, tokenUsage)
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

        // For Gemini 2.5+ models, disable thinking to prevent output truncation
        // Thinking tokens count against the output budget, causing JSON to be cut off mid-string
        let needsThinkingDisabled = effectiveModelId.contains("2.5") ||
                                    effectiveModelId.contains("exp") ||
                                    effectiveModelId.hasPrefix("gemini-3")
        if needsThinkingDisabled {
            generationConfig["thinkingConfig"] = ["thinkingBudget": 0]
            Logger.info("🧠 Disabled thinking for \(effectiveModelId) to prevent truncation", category: .ai)
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
            throw GoogleAIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            Logger.error("❌ Structured JSON generation failed: \(errorMsg)", category: .ai)
            throw GoogleAIError.generateFailed(errorMsg)
        }

        // Parse response to extract text
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Logger.error("❌ Structured JSON: Failed to parse response as JSON", category: .ai)
            throw GoogleAIError.invalidResponse
        }

        guard let candidates = json["candidates"] as? [[String: Any]], !candidates.isEmpty else {
            // Log the full response to understand why there are no candidates
            let responseStr = String(data: data, encoding: .utf8) ?? "unable to decode"
            Logger.error("❌ Structured JSON: No candidates in response. Full response: \(responseStr.prefix(500))", category: .ai)
            throw GoogleAIError.invalidResponse
        }

        let firstCandidate = candidates[0]
        guard let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            Logger.error("❌ Structured JSON: Missing content/parts/text in candidate. Candidate keys: \(firstCandidate.keys)", category: .ai)
            throw GoogleAIError.invalidResponse
        }

        // Check finish reason - throw error for non-STOP to trigger fallback
        if let finishReason = firstCandidate["finishReason"] as? String, finishReason != "STOP" {
            Logger.warning("⚠️ Structured output failed: finishReason=\(finishReason)", category: .ai)
            throw GoogleAIError.extractionBlocked(finishReason: finishReason)
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
}
