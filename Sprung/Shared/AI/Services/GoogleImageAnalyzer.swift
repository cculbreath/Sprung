//
//  GoogleImageAnalyzer.swift
//  Sprung
//
//  Handles Google Gemini image analysis operations.
//  Extracted from GoogleAIService for single responsibility.
//

import Foundation

/// Service for analyzing images using Google's Gemini vision capabilities
actor GoogleImageAnalyzer {

    // MARK: - Types

    enum ImageAnalysisError: LocalizedError {
        case noAPIKey
        case generateFailed(String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "Google API key not configured. Add it in Settings."
            case .generateFailed(let msg):
                return "Image analysis failed: \(msg)"
            case .invalidResponse:
                return "Invalid response from Google API"
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
            config.timeoutIntervalForRequest = 300
            config.timeoutIntervalForResource = 600
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - API Key

    private func getAPIKey() throws -> String {
        guard let key = APIKeyManager.get(.gemini),
              !key.isEmpty else {
            throw ImageAnalysisError.noAPIKey
        }
        return key
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
            throw ImageAnalysisError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            Logger.error("❌ Image analysis failed: \(errorMsg)", category: .ai)
            throw ImageAnalysisError.generateFailed(errorMsg)
        }

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let responseParts = content["parts"] as? [[String: Any]],
              let firstPart = responseParts.first,
              let text = firstPart["text"] as? String else {
            throw ImageAnalysisError.invalidResponse
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
            throw ImageAnalysisError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            Logger.error("❌ Structured image analysis failed: \(errorMsg)", category: .ai)
            throw ImageAnalysisError.generateFailed(errorMsg)
        }

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let responseParts = content["parts"] as? [[String: Any]],
              let firstPart = responseParts.first,
              let text = firstPart["text"] as? String else {
            throw ImageAnalysisError.invalidResponse
        }

        Logger.info("✅ Structured image analysis complete (\(text.count) chars)", category: .ai)

        return text
    }

    // MARK: - Utilities

    /// Detect image MIME type from data header bytes
    func detectImageMimeType(_ data: Data) -> String? {
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
}
