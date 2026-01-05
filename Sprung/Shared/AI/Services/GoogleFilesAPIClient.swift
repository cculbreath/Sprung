//
//  GoogleFilesAPIClient.swift
//  Sprung
//
//  Handles Google Files API operations: upload, wait for processing, and delete.
//  Extracted from GoogleAIService for single responsibility.
//

import Foundation

/// Client for Google's Files API - handles file upload, processing, and deletion
actor GoogleFilesAPIClient {

    // MARK: - Types

    struct UploadedFile {
        let name: String
        let uri: String
        let mimeType: String
        let sizeBytes: Int64
        let state: String
    }

    enum FilesAPIError: LocalizedError {
        case noAPIKey
        case uploadFailed(String)
        case fileProcessing(String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "Google API key not configured. Add it in Settings."
            case .uploadFailed(let msg):
                return "File upload failed: \(msg)"
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

    init(session: URLSession? = nil) {
        if let session = session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 300 // 5 minutes for large uploads
            config.timeoutIntervalForResource = 600 // 10 minutes total
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - API Key

    private func getAPIKey() throws -> String {
        guard let key = APIKeyManager.get(.gemini),
              !key.isEmpty else {
            throw FilesAPIError.noAPIKey
        }
        return key
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
            throw FilesAPIError.uploadFailed("Failed to get upload URL")
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
            throw FilesAPIError.uploadFailed(errorMsg)
        }

        // Parse response
        guard let json = try JSONSerialization.jsonObject(with: uploadData) as? [String: Any],
              let fileInfo = json["file"] as? [String: Any],
              let name = fileInfo["name"] as? String,
              let uri = fileInfo["uri"] as? String else {
            throw FilesAPIError.invalidResponse
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
                throw FilesAPIError.invalidResponse
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
                throw FilesAPIError.fileProcessing("File processing failed")
            }

            // Wait before checking again
            try await Task.sleep(for: .seconds(2))
        }

        throw FilesAPIError.fileProcessing("Timeout waiting for file processing")
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
}
