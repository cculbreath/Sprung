//
//  ResumeReviewService.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 5/11/25.
//

import AppKit
import Foundation
import PDFKit
import SwiftUI

/// Service for handling resume review operations with LLM
class ResumeReviewService: @unchecked Sendable {
    private var openAIClient: OpenAIClientProtocol?
    private var currentRequestID: UUID?

    @MainActor
    func initialize() {
        // Retrieve API key stored in UserDefaults / AppStorage.
        let apiKey = UserDefaults.standard.string(forKey: "openAiApiKey") ?? "none"
        guard apiKey != "none" else { return }
        openAIClient = OpenAIClientFactory.createClient(apiKey: apiKey)
    }

    // MARK: - PDF to Image Conversion

    /// Converts a PDF to a base64 encoded image
    /// - Parameter pdfData: PDF data to convert
    /// - Returns: Base64 encoded image string or nil if conversion failed
    func convertPDFToBase64Image(pdfData: Data) -> String? {
        guard let pdfDocument = PDFDocument(data: pdfData),
              let pdfPage = pdfDocument.page(at: 0)
        else {
            return nil
        }

        // Create a bitmap representation of the PDF page
        let pageRect = pdfPage.bounds(for: .mediaBox)
        let renderer = NSImage(size: pageRect.size)

        renderer.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high

        // Fill with white background
        NSColor.white.set()
        NSRect(origin: .zero, size: pageRect.size).fill()

        // Draw the PDF page
        pdfPage.draw(with: .mediaBox, to: NSGraphicsContext.current!.cgContext)
        renderer.unlockFocus()

        // Convert to PNG data
        guard let tiffData = renderer.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:])
        else {
            return nil
        }

        // Convert to base64
        return pngData.base64EncodedString()
    }

    // MARK: - Prompt Building

    /// Builds a prompt for the review operation
    /// - Parameters:
    ///   - reviewType: Type of review to perform
    ///   - resume: Resume to review
    ///   - includeImage: Whether the prompt should mention an attached image
    ///   - customOptions: Custom options for the review (used when reviewType is .custom)
    /// - Returns: The constructed prompt string
    func buildPrompt(
        reviewType: ResumeReviewType,
        resume: Resume,
        includeImage: Bool,
        customOptions: CustomReviewOptions? = nil
    ) -> String {
        // Check if we have a model to extract text
        guard let model = resume.model else {
            return "Error: No resume model available for review."
        }

        // Check if we have a job app
        guard let jobApp = resume.jobApp else {
            return "Error: No job application associated with this resume."
        }

        var prompt = reviewType.promptTemplate()

        // If this is a custom review, build the prompt from the custom options
        if reviewType == .custom, let options = customOptions {
            prompt = buildCustomPrompt(options: options)
        }

        // Replace variables in the prompt
        prompt = prompt.replacingOccurrences(of: "{jobPosition}", with: jobApp.jobPosition)
        prompt = prompt.replacingOccurrences(of: "{companyName}", with: jobApp.companyName)
        prompt = prompt.replacingOccurrences(of: "{jobDescription}", with: jobApp.jobDescription)
        prompt = prompt.replacingOccurrences(of: "{resumeText}", with: model.renderedResumeText)

        // Add background docs if available
        let backgroundDocs = resume.enabledSources.map { $0.name + ":\n" + $0.content + "\n\n" }.joined()
        prompt = prompt.replacingOccurrences(of: "{backgroundDocs}", with: backgroundDocs)

        // Handle the image placeholder
        if includeImage {
            prompt = prompt.replacingOccurrences(of: "{includeImage}", with: "I've also attached an image so you can assess its overall professionalism and design.")
        } else {
            prompt = prompt.replacingOccurrences(of: "{includeImage}", with: "")
        }

        return prompt
    }

    /// Builds a custom prompt based on user options
    /// - Parameter options: Custom review options
    /// - Returns: The custom prompt string
    private func buildCustomPrompt(options: CustomReviewOptions) -> String {
        var sections: [String] = []

        // Add job listing if requested
        if options.includeJobListing {
            sections.append("""
            I am applying for this job opening: 
            {jobPosition}, {companyName}. 
            Job Description:
            {jobDescription}
            """)
        }

        // Add resume text if requested
        if options.includeResumeText {
            sections.append("""
            Here is a draft of my current resume:
            {resumeText}
            """)
        }

        // Add image placeholder if requested (will be replaced later)
        if options.includeResumeImage {
            sections.append("{includeImage}")
        }

        // Add custom prompt text
        sections.append(options.customPrompt)

        return sections.joined(separator: "\n\n")
    }

    // MARK: - LLM Request

    /// Sends a review request to the LLM
    /// - Parameters:
    ///   - reviewType: Type of review to perform
    ///   - resume: Resume to review
    ///   - customOptions: Custom options for the review (used when reviewType is .custom)
    ///   - onProgress: Callback for streaming progress
    ///   - onComplete: Callback when the review is complete
    @MainActor
    func sendReviewRequest(
        reviewType: ResumeReviewType,
        resume: Resume,
        customOptions: CustomReviewOptions? = nil,
        onProgress: @escaping (String) -> Void,
        onComplete: @escaping (Result<String, Error>) -> Void
    ) {
        // Initialize client if needed
        if openAIClient == nil {
            initialize()
        }

        guard let client = openAIClient else {
            onComplete(.failure(NSError(
                domain: "ResumeReviewService",
                code: 1000,
                userInfo: [NSLocalizedDescriptionKey: "OpenAI client not initialized"]
            )))
            return
        }

        // Determine image support and attempt conversion early so the prompt accurately reflects attachments
        let supportsImages = checkIfModelSupportsImages()
        var base64Image: String?
        if supportsImages,
           reviewType != .custom || (customOptions?.includeResumeImage ?? false),
           let pdfData = resume.pdfData
        {
            base64Image = convertPDFToBase64Image(pdfData: pdfData)
        }

        let includeImage = base64Image != nil

        // Build the prompt AFTER determining whether an image will actually be attached
        let promptText = buildPrompt(
            reviewType: reviewType,
            resume: resume,
            includeImage: includeImage,
            customOptions: customOptions
        )

        var messages: [ChatMessage] = []

        // Add system message
        messages.append(ChatMessage(
            role: .system,
            content: "You are an expert AI resume reviewer with years of experience in the hiring industry. Your goal is to provide helpful, actionable, and structured feedback on resumes."
        ))

        // If we have an image, switch to the raw API helper
        if includeImage, let encodedImage = base64Image {
            sendImageReviewRequest(
                promptText: promptText,
                base64Image: encodedImage,
                onProgress: onProgress,
                onComplete: onComplete
            )
            return
        }

        // Without image, use regular chat completion
        messages.append(ChatMessage(role: .user, content: promptText))

        // Generate a unique ID for this request
        let requestID = UUID()
        currentRequestID = requestID

        // Use the latest LLM model (based on OpenAIModelExtension.swift)
        let model = AIModels.gpt4o

        // Send with streaming
        client.sendChatCompletionStreaming(
            messages: messages,
            model: model,
            temperature: 0.7,
            onChunk: { result in
                // Check if this is still the current request
                guard self.currentRequestID == requestID else { return }

                switch result {
                case let .success(response):
                    onProgress(response.content)
                case let .failure(error):
                    onComplete(.failure(error))
                }
            },
            onComplete: { error in
                // Check if this is still the current request
                guard self.currentRequestID == requestID else { return }

                if let error = error {
                    onComplete(.failure(error))
                } else {
                    onComplete(.success("Review complete"))
                }
            }
        )
    }

    /// Sends a review request with an image to the LLM using the Responses API
    /// - Parameters:
    ///   - promptText: The prompt text
    ///   - base64Image: Base64 encoded image data
    ///   - onProgress: Callback for streaming progress
    ///   - onComplete: Callback when the review is complete
    @MainActor
    private func sendImageReviewRequest(
        promptText: String,
        base64Image: String,
        onProgress: @escaping (String) -> Void,
        onComplete: @escaping (Result<String, Error>) -> Void
    ) {
        // Generate a unique ID for this request
        let requestID = UUID()
        currentRequestID = requestID

        // Create the URL for the OpenAI API
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            onComplete(.failure(NSError(
                domain: "ResumeReviewService",
                code: 1000,
                userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]
            )))
            return
        }

        // Make sure we have an API key
        guard let client = openAIClient else {
            onComplete(.failure(NSError(
                domain: "ResumeReviewService",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "OpenAI client not initialized"]
            )))
            return
        }

        onProgress("Analyzing resume with image...")

        // Create the request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(client.apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build the request payload with the image
        let imageUrl = "data:image/png;base64,\(base64Image)"

        // Create the messages array with proper content format for images
        let requestBody: [String: Any] = [
            "model": AIModels.gpt4o,
            "messages": [
                [
                    "role": "system",
                    "content": "You are an expert AI resume reviewer with years of experience in the hiring industry. Your goal is to provide helpful, actionable, and structured feedback on resumes.",
                ],
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": promptText,
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": imageUrl,
                            ],
                        ],
                    ],
                ],
            ],
            "stream": false,
            "temperature": 0.7,
        ]

        // Convert the payload to JSON
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody, options: [])
            request.httpBody = jsonData

            // Create a task for handling the response
            let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                // Check for errors
                guard let self = self else { return }

                if let error = error {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self, self.currentRequestID == requestID else { return }
                        onComplete(.failure(error))
                    }
                    return
                }

                // Check HTTP response
                guard let httpResponse = response as? HTTPURLResponse else {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self, self.currentRequestID == requestID else { return }
                        onComplete(.failure(NSError(
                            domain: "ResumeReviewService",
                            code: 1002,
                            userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"]
                        )))
                    }
                    return
                }

                // Check for error status codes
                guard (200 ... 299).contains(httpResponse.statusCode) else {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self, self.currentRequestID == requestID else { return }

                        var errorMessage = "HTTP Error: \(httpResponse.statusCode)"
                        if let data = data, let responseString = String(data: data, encoding: .utf8) {
                            errorMessage += " - \(responseString)"
                        }

                        onComplete(.failure(NSError(
                            domain: "ResumeReviewService",
                            code: httpResponse.statusCode,
                            userInfo: [NSLocalizedDescriptionKey: errorMessage]
                        )))
                    }
                    return
                }

                // Process the response data
                if let data = data, let responseString = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self, self.currentRequestID == requestID else { return }

                        // For streaming responses, we'd need to parse each chunk
                        // This is a simplified version that assumes a non-streaming response
                        if responseString.contains("content") {
                            do {
                                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                                   let choices = json["choices"] as? [[String: Any]],
                                   let choice = choices.first,
                                   let message = choice["message"] as? [String: Any],
                                   let content = message["content"] as? String
                                {
                                    onProgress(content)
                                }
                            } catch {
                                onProgress("Error parsing response: \(error.localizedDescription)")
                            }
                        }

                        onComplete(.success("Review complete"))
                    }
                } else {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self, self.currentRequestID == requestID else { return }
                        onComplete(.failure(NSError(
                            domain: "ResumeReviewService",
                            code: 1003,
                            userInfo: [NSLocalizedDescriptionKey: "No response data"]
                        )))
                    }
                }
            }

            // Start the task
            task.resume()

        } catch {
            onComplete(.failure(error))
        }
    }

    /// Cancels the current review request
    func cancelRequest() {
        currentRequestID = nil
    }

    // MARK: - Helpers

    /// Checks if the current model supports image inputs
    /// - Returns: True if the model supports images
    private func checkIfModelSupportsImages() -> Bool {
        let model = OpenAIModelFetcher.getPreferredModelString().lowercased()

        // A minimal whitelist of vision-capable models. Extend as new models are released.
        let visionModelsSubstrings = [
            "gpt-4o", // gpt-4o family (mini, large, etc.)
            "gpt-4.1", // gpt-4.1 vision-capable variants
            "gpt-image", // multimodal GPT Image 1
            "o4", // o4 vision models
            "cua", // computer-use-preview etc.
        ]

        return visionModelsSubstrings.contains { model.contains($0) }
    }
}
