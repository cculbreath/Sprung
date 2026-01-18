//
//  GoogleAIService.swift
//  Sprung
//
//  Thin facade over Google's Generative AI API.
//  Delegates to specialized components for file operations, content generation, and image analysis.
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

        init(promptTokenCount: Int, candidatesTokenCount: Int, totalTokenCount: Int) {
            self.promptTokenCount = promptTokenCount
            self.candidatesTokenCount = candidatesTokenCount
            self.totalTokenCount = totalTokenCount
        }

        init(from usage: GoogleContentGenerator.GeminiTokenUsage) {
            self.promptTokenCount = usage.promptTokenCount
            self.candidatesTokenCount = usage.candidatesTokenCount
            self.totalTokenCount = usage.totalTokenCount
        }
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

    // MARK: - Dependencies

    private let filesClient: GoogleFilesAPIClient
    private let contentGenerator: GoogleContentGenerator
    private let imageAnalyzer: GoogleImageAnalyzer
    private let baseURL = "https://generativelanguage.googleapis.com"
    private let session: URLSession

    // MARK: - Initialization

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
        let session = URLSession(configuration: config)
        self.session = session
        self.filesClient = GoogleFilesAPIClient(session: session)
        self.contentGenerator = GoogleContentGenerator(session: session)
        self.imageAnalyzer = GoogleImageAnalyzer(session: session)
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

    // MARK: - Image Analysis (Delegated)

    /// Analyze images using Gemini's vision capabilities with inline base64 data.
    func analyzeImages(
        images: [Data],
        prompt: String,
        modelId: String? = nil,
        temperature: Double = 0.1,
        maxOutputTokens: Int = 8192
    ) async throws -> String {
        do {
            return try await imageAnalyzer.analyzeImages(
                images: images,
                prompt: prompt,
                modelId: modelId,
                temperature: temperature,
                maxOutputTokens: maxOutputTokens
            )
        } catch let error as GoogleImageAnalyzer.ImageAnalysisError {
            throw mapImageError(error)
        }
    }

    /// Analyze images using Gemini's vision capabilities with structured JSON output.
    func analyzeImagesStructured(
        images: [Data],
        prompt: String,
        jsonSchema: [String: Any],
        modelId: String? = nil,
        temperature: Double = 0.1
    ) async throws -> String {
        do {
            return try await imageAnalyzer.analyzeImagesStructured(
                images: images,
                prompt: prompt,
                jsonSchema: jsonSchema,
                modelId: modelId,
                temperature: temperature
            )
        } catch let error as GoogleImageAnalyzer.ImageAnalysisError {
            throw mapImageError(error)
        }
    }

    // MARK: - Content Generation (Delegated)

    /// Generate a structured summary from extracted document text.
    func generateSummary(
        content: String,
        filename: String,
        modelId: String? = nil
    ) async throws -> DocumentSummary {
        do {
            return try await contentGenerator.generateSummary(
                content: content,
                filename: filename,
                modelId: modelId
            )
        } catch let error as GoogleContentGenerator.ContentGeneratorError {
            throw mapContentError(error)
        }
    }

    /// Generate structured JSON output from a prompt.
    /// - Parameters:
    ///   - thinkingLevel: Controls reasoning for Gemini 3+ models. Options: "minimal", "low", "medium", "high".
    ///                    Use "low" for simple transformations to reduce token usage from thinking.
    func generateStructuredJSON(
        prompt: String,
        modelId: String? = nil,
        temperature: Double = 0.2,
        maxOutputTokens: Int = 65536,
        jsonSchema: [String: Any]? = nil,
        thinkingLevel: String? = nil
    ) async throws -> String {
        do {
            return try await contentGenerator.generateStructuredJSON(
                prompt: prompt,
                modelId: modelId,
                temperature: temperature,
                maxOutputTokens: maxOutputTokens,
                jsonSchema: jsonSchema,
                thinkingLevel: thinkingLevel
            )
        } catch let error as GoogleContentGenerator.ContentGeneratorError {
            throw mapContentError(error)
        }
    }

    // MARK: - High-Level API

    /// Generate text from a PDF using Gemini vision.
    /// Uploads the PDF via Files API, sends a prompt, and returns the extracted/generated text.
    func generateFromPDF(
        pdfData: Data,
        filename: String,
        prompt: String,
        modelId: String? = nil,
        maxOutputTokens: Int = 65536
    ) async throws -> (text: String, tokenUsage: GeminiTokenUsage?) {
        // Use provided model or require configuration
        let effectiveModelId: String
        if let providedModelId = modelId, !providedModelId.isEmpty {
            effectiveModelId = providedModelId
        } else {
            guard let configuredModelId = UserDefaults.standard.string(forKey: "onboardingPDFExtractionModelId"), !configuredModelId.isEmpty else {
                throw ModelConfigurationError.modelNotConfigured(
                    settingKey: "onboardingPDFExtractionModelId",
                    operationName: "Google AI Content Generation"
                )
            }
            effectiveModelId = configuredModelId
        }

        // Upload file
        let uploadedFile: GoogleFilesAPIClient.UploadedFile
        do {
            uploadedFile = try await filesClient.uploadFile(
                data: pdfData,
                mimeType: "application/pdf",
                displayName: filename
            )
        } catch let error as GoogleFilesAPIClient.FilesAPIError {
            throw mapFilesError(error)
        }

        // Wait for processing if needed
        var activeFile = uploadedFile
        if uploadedFile.state != "ACTIVE" {
            do {
                activeFile = try await filesClient.waitForFileProcessing(fileName: uploadedFile.name)
            } catch let error as GoogleFilesAPIClient.FilesAPIError {
                throw mapFilesError(error)
            }
        }

        defer {
            // Clean up uploaded file
            Task {
                try? await self.filesClient.deleteFile(fileName: activeFile.name)
            }
        }

        // Generate content
        let result: (content: String, tokenUsage: GoogleContentGenerator.GeminiTokenUsage?)
        do {
            result = try await contentGenerator.extractPDFContent(
                fileURI: activeFile.uri,
                mimeType: "application/pdf",
                modelId: effectiveModelId,
                prompt: prompt,
                maxOutputTokens: maxOutputTokens
            )
        } catch let error as GoogleContentGenerator.ContentGeneratorError {
            throw mapContentError(error)
        }

        Logger.info("📄 Vision extraction complete for \(filename) (\(result.content.count) chars)", category: .ai)

        let tokenUsage = result.tokenUsage.map { GeminiTokenUsage(from: $0) }
        return (result.content, tokenUsage)
    }

    // MARK: - Error Mapping

    private func mapFilesError(_ error: GoogleFilesAPIClient.FilesAPIError) -> GoogleAIError {
        switch error {
        case .noAPIKey:
            return .noAPIKey
        case .uploadFailed(let msg):
            return .uploadFailed(msg)
        case .fileProcessing(let state):
            return .fileProcessing(state)
        case .invalidResponse:
            return .invalidResponse
        }
    }

    private func mapContentError(_ error: GoogleContentGenerator.ContentGeneratorError) -> GoogleAIError {
        switch error {
        case .noAPIKey:
            return .noAPIKey
        case .generateFailed(let msg):
            return .generateFailed(msg)
        case .invalidResponse:
            return .invalidResponse
        case .extractionBlocked(let finishReason):
            return .extractionBlocked(finishReason: finishReason)
        }
    }

    private func mapImageError(_ error: GoogleImageAnalyzer.ImageAnalysisError) -> GoogleAIError {
        switch error {
        case .noAPIKey:
            return .noAPIKey
        case .generateFailed(let msg):
            return .generateFailed(msg)
        case .invalidResponse:
            return .invalidResponse
        }
    }
}
