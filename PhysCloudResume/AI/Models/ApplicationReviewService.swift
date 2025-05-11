//
//  ApplicationReviewService.swift
//  PhysCloudResume
//
//  Created by OpenAI Assistant on 5/11/25.
//

import Foundation
import PDFKit
import SwiftUI

/// Service responsible for sending application packet reviews (cover letter + resume)
class ApplicationReviewService: @unchecked Sendable {
    private var openAIClient: OpenAIClientProtocol?
    private var currentRequestID: UUID?

    // MARK: - Init

    @MainActor
    func initialize() {
        let apiKey = UserDefaults.standard.string(forKey: "openAiApiKey") ?? "none"
        guard apiKey != "none" else { return }
        openAIClient = OpenAIClientFactory.createClient(apiKey: apiKey)
    }

    // MARK: - PDF → Base-64 image (reuse from ResumeReviewService)

    func convertPDFToBase64Image(pdfData: Data) -> String? {
        guard let pdfDocument = PDFDocument(data: pdfData),
              let pdfPage = pdfDocument.page(at: 0)
        else { return nil }

        let pageRect = pdfPage.bounds(for: .mediaBox)
        let renderer = NSImage(size: pageRect.size)
        renderer.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSColor.white.set()
        NSRect(origin: .zero, size: pageRect.size).fill()
        pdfPage.draw(with: .mediaBox, to: NSGraphicsContext.current!.cgContext)
        renderer.unlockFocus()

        guard let tiff = renderer.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { return nil }

        return png.base64EncodedString()
    }

    // MARK: - Prompt building

    func buildPrompt(
        reviewType: ApplicationReviewType,
        jobApp: JobApp,
        resume: Resume,
        coverLetter: CoverLetter?,
        includeImage: Bool,
        customOptions: CustomApplicationReviewOptions? = nil
    ) -> String {
        var prompt = reviewType.promptTemplate()

        // Handle custom build if necessary
        if reviewType == .custom, let opt = customOptions {
            prompt = buildCustomPrompt(options: opt)
        }

        prompt = prompt.replacingOccurrences(of: "{jobPosition}", with: jobApp.jobPosition)
        prompt = prompt.replacingOccurrences(of: "{companyName}", with: jobApp.companyName)
        prompt = prompt.replacingOccurrences(of: "{jobDescription}", with: jobApp.jobDescription)

        // Cover letter text replacement.
        let coverText = coverLetter?.content ?? ""
        prompt = prompt.replacingOccurrences(of: "{coverLetterText}", with: coverText)

        // Resume text
        prompt = prompt.replacingOccurrences(of: "{resumeText}", with: resume.textRes == "" ? resume.model?.renderedResumeText ?? "" : resume.textRes)

        // Background docs placeholder
        let bgDocs = resume.enabledSources.map { "\($0.name):\n\($0.content)\n\n" }.joined()
        prompt = prompt.replacingOccurrences(of: "{backgroundDocs}", with: bgDocs)

        // Include image sentence
        prompt = prompt.replacingOccurrences(of: "{includeImage}", with: includeImage ? "I've also attached an image so you can assess its overall professionalism and design." : "")

        return prompt
    }

    private func buildCustomPrompt(options: CustomApplicationReviewOptions) -> String {
        var segments: [String] = []

        if options.includeCoverLetter {
            segments.append("""
            Cover Letter
            ------------
            {coverLetterText}
            """)
        }

        if options.includeResumeText {
            segments.append("""
            Resume
            ------
            {resumeText}
            """)
        }

        if options.includeResumeImage {
            segments.append("{includeImage}")
        }

        if options.includeBackgroundDocs {
            segments.append("""
            Background Docs
            ---------------
            {backgroundDocs}
            """)
        }

        segments.append(options.customPrompt)
        return segments.joined(separator: "\n\n")
    }

    // MARK: - LLM Request (non-image handled by client, image via raw call)

    @MainActor
    func sendReviewRequest(
        reviewType: ApplicationReviewType,
        jobApp: JobApp,
        resume: Resume,
        coverLetter: CoverLetter?,
        customOptions: CustomApplicationReviewOptions? = nil,
        onProgress: @escaping (String) -> Void,
        onComplete: @escaping (Result<String, Error>) -> Void
    ) {
        if openAIClient == nil { initialize() }
        guard let client = openAIClient else {
            onComplete(.failure(NSError(domain: "AppReview", code: 900, userInfo: [NSLocalizedDescriptionKey: "Client not initialised"])))
            return
        }

        // Decide about image
        let supportsImages = checkIfModelSupportsImages()
        var imageBase64: String?
        if supportsImages,
           reviewType != .custom || (customOptions?.includeResumeImage ?? false),
           let pdfData = resume.pdfData
        {
            imageBase64 = convertPDFToBase64Image(pdfData: pdfData)
        }

        let includeImage = imageBase64 != nil

        let prompt = buildPrompt(
            reviewType: reviewType,
            jobApp: jobApp,
            resume: resume,
            coverLetter: coverLetter,
            includeImage: includeImage,
            customOptions: customOptions
        )

        // If we must attach an image, fall back to raw API call similar to ResumeReviewService
        if includeImage, let base64 = imageBase64 {
            sendImageReviewRequest(promptText: prompt, base64Image: base64, onProgress: onProgress, onComplete: onComplete)
            return
        }

        // Build messages and stream via client
        let requestID = UUID(); currentRequestID = requestID
        let messages: [ChatMessage] = [
            ChatMessage(role: .system, content: "You are an expert recruiter reviewing job application packets."),
            ChatMessage(role: .user, content: prompt),
        ]

        client.sendChatCompletionStreaming(
            messages: messages,
            model: AIModels.gpt4o,
            temperature: 0.7,
            onChunk: { [weak self] result in
                guard let self = self, self.currentRequestID == requestID else { return }
                switch result {
                case let .success(resp): onProgress(resp.content)
                case let .failure(err): onComplete(.failure(err))
                }
            },
            onComplete: { [weak self] error in
                guard let self = self, self.currentRequestID == requestID else { return }
                if let e = error { onComplete(.failure(e)) } else { onComplete(.success("Done")) }
            }
        )
    }

    // Raw image-request (non-streaming)
    private func sendImageReviewRequest(
        promptText: String,
        base64Image: String,
        onProgress: @escaping (String) -> Void,
        onComplete: @escaping (Result<String, Error>) -> Void
    ) {
        let requestID = UUID(); currentRequestID = requestID
        guard let client = openAIClient else { return }
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(client.apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let imgURL = "data:image/png;base64,\(base64Image)"
        let body: [String: Any] = [
            "model": AIModels.gpt4o,
            "messages": [
                ["role": "system", "content": "You are an expert recruiter reviewing job application packets."],
                ["role": "user", "content": [["type": "text", "text": promptText], ["type": "image_url", "image_url": ["url": imgURL]]]],
            ],
            "stream": false,
            "temperature": 0.7,
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard self != nil else { return }
            if let err = error { onComplete(.failure(err)); return }
            guard let data = data else { onComplete(.failure(NSError(domain: "", code: -1))); return }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let msg = choices.first?["message"] as? [String: Any],
               let content = msg["content"] as? String
            {
                DispatchQueue.main.async { onProgress(content); onComplete(.success("Done")) }
            } else {
                DispatchQueue.main.async { onComplete(.failure(NSError(domain: "", code: -2))) }
            }
        }
        task.resume()
    }

    // Cancel
    func cancelRequest() { currentRequestID = nil }

    private func checkIfModelSupportsImages() -> Bool {
        let model = OpenAIModelFetcher.getPreferredModelString().lowercased()
        return ["gpt-4o", "gpt-4.1", "gpt-image", "o4", "cua"].contains { model.contains($0) }
    }
}
