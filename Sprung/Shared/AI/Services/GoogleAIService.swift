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
        prompt: String
    ) async throws -> String {
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
                "maxOutputTokens": 65536
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

        Logger.info("✅ Content generated successfully (\(text.count) chars)", category: .ai)

        return text
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

        let summaryPrompt = """
            Analyze this document and provide a structured summary for job application context.
            Document filename: \(filename)

            --- DOCUMENT CONTENT ---
            \(content.prefix(100000))
            --- END DOCUMENT ---

            Output as JSON with this exact structure:
            {
              "document_type": "resume|performance_review|project_doc|job_description|letter_of_recommendation|certificate|transcript|portfolio|other",
              "summary": "~500 word narrative summary covering: what the document contains, key information relevant to job applications, notable details that stand out",
              "time_period": "YYYY-YYYY" or null if not applicable,
              "companies": ["Company A", "Company B"],
              "roles": ["Role 1", "Role 2"],
              "skills": ["Swift", "Python", "Leadership"],
              "achievements": ["Led team of 5", "Shipped 3 products"],
              "relevance_hints": "Brief note about what types of knowledge cards this doc could support"
            }

            Be thorough in the summary - it will be the only context the main LLM coordinator sees.
            Include specific details, metrics, and quotes where available.
            """

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
        prompt: String? = nil
    ) async throws -> (title: String?, content: String) {
        let extractionPrompt = prompt ?? """
            Extract and transcribe the content of this professional document to support resume and cover letter drafting.

            CRITICAL INSTRUCTION: The output MUST be a highly detailed, structured transcription that errs heavily on the side of inclusion, not abridgement. This output will serve as the sole source for downstream tasks; no material information should be omitted or summarized aggressively. Original writing should preserve the author's voice and be a verbatim transcription by default.

            Output format: Provide a thorough, structured transcription in markdown.

            Content handling rules:
            - Every page of the original document should be referenced in the transcript. If you reference a range of pages, keep the span of the reference small, and use sparingly.
            - **Verbatim Transcription Mandate:** Any major narrative essay, standalone statement, or comprehensive project description MUST be transcribed **VERBATIM**, preserving all original paragraph structure, subheadings, and formatting.
            - Quantitative information may be consolidated into summarizing values as long as job-application relevant quantities are well preserved and fully represented.
            - Diagrams, figures, and visual content: Describe what is shown AND what it demonstrates about the applicant's work or capabilities.

            Respond with a JSON object containing:
            - "title": A concise, descriptive title for this document
            - "content": The comprehensive transcription in markdown format (aim for thoroughness over brevity)

            Example: {"title": "John Smith Resume", "content": "# Summary\\n\\nContent here..."}
            """

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
        let result = try await extractPDFContent(
            fileURI: activeFile.uri,
            mimeType: "application/pdf",
            modelId: modelId,
            prompt: extractionPrompt
        )

        // Try to parse as JSON for title extraction
        if let jsonData = result.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            let title = json["title"] as? String
            let content = json["content"] as? String ?? result
            return (title, content)
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
                    return (title, content)
                }
            }
        }

        return (nil, result)
    }
}
