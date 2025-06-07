//
//  ResumeExportService.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/16/25.
//

import Foundation

//  ResumeExportService.swift
//  Extracted network export logic out of the Resume model so that the core
//  data objects are no longer coupled to URLSession.

struct ApiResumeExportService {
    private let endpoint = URL(string: "https://resume.physicscloud.net/build-resume-file")!
    private let apiKey = "b0b307e1-6eb4-41d9-8c1f-278c254351d3" // TODO: move to secure storage

    func export(jsonURL: URL, for resume: Resume) async throws {
        guard let style = resume.model?.style else { throw ExportError.missingStyle }

        let fileData = try Data(contentsOf: jsonURL)
        
        // Debug logging
        if let jsonString = String(data: fileData, encoding: .utf8) {
            Logger.debug("Sending JSON to API (first 500 chars): \(String(jsonString.prefix(500)))")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ string: String) { body.append(string.data(using: .utf8)!) }

        // style
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"style\"\r\n\r\n")
        append("\(style)\r\n")

        // file
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"resumeFile\"; filename=\"\(jsonURL.lastPathComponent)\"\r\n")
        append("Content-Type: application/json\r\n\r\n")
        body.append(fileData)
        append("\r\n")
        append("--\(boundary)--\r\n")

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check for HTTP errors first
        if let httpResponse = response as? HTTPURLResponse {
            Logger.debug("API Response Status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode != 200 {
                if let responseString = String(data: data, encoding: .utf8) {
                    Logger.debug("API Error Response: \(responseString)")
                }
                throw ExportError.serverError(statusCode: httpResponse.statusCode)
            }
        }
        
        // Debug logging for successful responses
        if let responseString = String(data: data, encoding: .utf8) {
            Logger.debug("API Response Body: \(responseString)")
        }
        
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let pdfUrl = json["pdfUrl"] as? String
        else {
            throw ExportError.invalidResponse
        }

        if let text = json["resumeText"] as? String {
            resume.textRes = text
        }

        try await downloadPDF(from: pdfUrl, into: resume)
    }

    /// Downloads the exported PDF and stores it in the given resume model.
    ///
    /// ⚠️  All writes to `Resume` models **must** occur on the main actor to
    ///     avoid SwiftData/SwiftUI runtime warnings and to ensure UI updates
    ///     are propagated correctly.  Without hopping back to the main actor
    ///     the view displaying the PDF (`ResumePDFView`) would never be
    ///     invalidated after calling `applyChanges()` from `ReviewView`
    ///     because the property change happened on a background thread.
    @MainActor
    private func downloadPDF(from urlString: String, into resume: Resume) async throws {
        guard let url = URL(string: urlString) else { throw ExportError.invalidResponse }

        // Network transfer runs on the current actor (background by default)
        // but the assignment to `resume.pdfData` happens after an explicit
        // hop to the main actor enforced by the `@MainActor` attribute.
        let (data, _) = try await URLSession.shared.data(from: url)
        resume.pdfData = data
    }

    enum ExportError: LocalizedError {
        case missingStyle
        case invalidResponse
        case serverError(statusCode: Int)
        
        var errorDescription: String? {
            switch self {
            case .missingStyle:
                return "Resume style is not configured"
            case .invalidResponse:
                return "Invalid response from server"
            case .serverError(let statusCode):
                return "Server error: HTTP \(statusCode)"
            }
        }
    }
}
