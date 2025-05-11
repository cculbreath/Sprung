// PhysCloudResume/AI/Models/ResumeReviewService.swift

import AppKit
import Foundation
import PDFKit
import SwiftUI // For @MainActor

// MARK: - Response Structs for Fix Overflow Feature

/// Represents a single revised skill or expertise item from the LLM.
/// Mirrors ProposedRevisionNode but is specific to this feature's LLM call.
struct RevisedSkillNode: Codable, Equatable {
    var id: String
    var newValue: String
    var originalValue: String // Echoed back by LLM for context
    var treePath: String // Echoed back by LLM
    var isTitleNode: Bool // Echoed back by LLM

    enum CodingKeys: String, CodingKey {
        case id
        case newValue
        case originalValue
        case treePath
        case isTitleNode
    }
}

/// Container for the array of revised skills from the "fixFits" LLM call.
struct FixFitsResponseContainer: Codable, Equatable {
    var revisedSkillsAndExpertise: [RevisedSkillNode]

    enum CodingKeys: String, CodingKey {
        case revisedSkillsAndExpertise = "revised_skills_and_expertise"
    }
}

/// Response struct for the "contentsFit" LLM call.
struct ContentsFitResponse: Codable, Equatable {
    var contentsFit: Bool

    enum CodingKeys: String, CodingKey {
        case contentsFit
    }
}

/// Service for handling resume review operations with LLM
class ResumeReviewService: @unchecked Sendable {
    private var openAIClient: OpenAIClientProtocol? // Retained for other review types
    private var currentRequestID: UUID?
    private let apiQueue = DispatchQueue(label: "com.physcloudresume.apirequest", qos: .userInitiated)

    @MainActor
    func initialize() {
        // Retrieve API key stored in UserDefaults / AppStorage.
        let apiKey = UserDefaults.standard.string(forKey: "openAiApiKey") ?? "none"
        guard apiKey != "none" else { return }
        // For non-fixOverflow types, we might still use the MacPaw client if it supports them without images.
        // For fixOverflow, we'll use direct HTTP.
        openAIClient = OpenAIClientFactory.createClient(apiKey: apiKey)
    }

    // MARK: - PDF to Image Conversion (Existing)

    /// Converts a PDF to a base64 encoded image
    /// - Parameter pdfData: PDF data to convert
    /// - Returns: Base64 encoded image string or nil if conversion failed
    func convertPDFToBase64Image(pdfData: Data) -> String? {
        guard let pdfDocument = PDFDocument(data: pdfData),
              let pdfPage = pdfDocument.page(at: 0) // Always use the first page
        else {
            return nil
        }

        let pageRect = pdfPage.bounds(for: .mediaBox)
        let renderer = NSImage(size: pageRect.size)

        renderer.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSColor.white.set() // Ensure a white background
        NSRect(origin: .zero, size: pageRect.size).fill()
        pdfPage.draw(with: .mediaBox, to: NSGraphicsContext.current!.cgContext)
        renderer.unlockFocus()

        guard let tiffData = renderer.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:])
        else {
            return nil
        }
        return pngData.base64EncodedString()
    }

    // MARK: - Prompt Building (Existing, with minor adjustments for clarity)

    func buildPrompt(
        reviewType: ResumeReviewType,
        resume: Resume,
        includeImage: Bool, // This flag now informs the prompt text
        customOptions: CustomReviewOptions? = nil
    ) -> String {
        if resume.model != nil {
            return "Error: No resume model available for review."
        }
        guard let jobApp = resume.jobApp else {
            return "Error: No job application associated with this resume."
        }

        var prompt = reviewType.promptTemplate()

        if reviewType == .custom, let options = customOptions {
            prompt = buildCustomPrompt(options: options)
        }

        prompt = prompt.replacingOccurrences(of: "{jobPosition}", with: jobApp.jobPosition)
        prompt = prompt.replacingOccurrences(of: "{companyName}", with: jobApp.companyName)
        prompt = prompt.replacingOccurrences(of: "{jobDescription}", with: jobApp.jobDescription)
        prompt = prompt.replacingOccurrences(of: "{resumeText}", with: resume.textRes)

        let backgroundDocs = resume.enabledSources.map { "\($0.name):\n\($0.content)\n\n" }.joined()
        prompt = prompt.replacingOccurrences(of: "{backgroundDocs}", with: backgroundDocs)

        let imagePlaceholder = includeImage ? "I've also attached an image for visual context." : ""
        prompt = prompt.replacingOccurrences(of: "{includeImage}", with: imagePlaceholder)

        return prompt
    }

    private func buildCustomPrompt(options: CustomReviewOptions) -> String {
        var sections: [String] = []
        if options.includeJobListing {
            sections.append("""
            I am applying for this job opening:
            {jobPosition}, {companyName}.
            Job Description:
            {jobDescription}
            """)
        }
        if options.includeResumeText {
            sections.append("""
            Here is a draft of my current resume:
            {resumeText}
            """)
        }
        if options.includeResumeImage { // This just affects the {includeImage} placeholder
            sections.append("{includeImage}")
        }
        sections.append(options.customPrompt)
        return sections.joined(separator: "\n\n")
    }

    // MARK: - Helper to Extract Skills and Expertise Nodes

    /// Extracts "Skills and Expertise" nodes into a JSON string format for the LLM.
    /// - Parameter resume: The resume to extract skills from.
    /// - Returns: A JSON string representing the skills and expertise, or nil if an error occurs.
    func extractSkillsForLLM(resume: Resume) -> String? {
        // First, ensure the resume has a rootNode.
        guard let actualRootNode = resume.rootNode else {
            print("Error: Resume has no rootNode.")
            return nil
        }

        // Attempt to find the "Skills and Expertise" section node.
        var skillsSectionNode: TreeNode? = actualRootNode.children?.first(where: {
            $0.name.lowercased() == "skills-and-expertise" || $0.name.lowercased() == "skills and expertise"
        })

        // If not found with primary names, try the fallback key.
        if skillsSectionNode == nil {
            skillsSectionNode = actualRootNode.children?.first(where: { $0.name == "skills-and-expertise" })
        }

        // If still not found after both attempts, print an error and return nil.
        guard let finalSkillsSectionNode = skillsSectionNode else {
            print("Error: 'Skills and Expertise' section node not found in the resume under rootNode.")
            return nil
        }

        return extractTreeNodesForLLM(parentNode: finalSkillsSectionNode)
    }

    private func extractTreeNodesForLLM(parentNode: TreeNode) -> String? {
        var nodesToProcess: [TreeNode] = []

        // We only want to process the direct children of the "Skills and Expertise" section node,
        // as these are the individual skills or skill categories.
        parentNode.children?.forEach { childNode in
            // If a child node itself has children (e.g. a category with bullet points),
            // we add the category node (title) and then its children (values).
            if childNode.hasChildren {
                if childNode.includeInEditor || !childNode.name.isEmpty { // Add the category title node
                    nodesToProcess.append(childNode)
                }
                childNode.children?.forEach { subChildNode in // Add its children (skill details)
                    if subChildNode.includeInEditor || !subChildNode.value.isEmpty {
                        nodesToProcess.append(subChildNode)
                    }
                }
            } else { // It's a direct skill item
                if childNode.includeInEditor || !childNode.name.isEmpty || !childNode.value.isEmpty {
                    nodesToProcess.append(childNode)
                }
            }
        }

        let exportableNodes: [[String: Any]] = nodesToProcess.compactMap { node in
            let textContent: String
            let isTitle: Bool = node.isTitleNode

            if isTitle {
                guard !node.name.isEmpty else { return nil }
                textContent = node.name
            } else {
                guard !node.value.isEmpty || !node.name.isEmpty else { return nil }
                textContent = !node.value.isEmpty ? node.value : node.name
            }

            return [
                "id": node.id,
                "originalValue": textContent,
                "isTitleNode": isTitle,
                "treePath": node.buildTreePath(),
            ]
        }

        guard !exportableNodes.isEmpty else {
            print("Warning: No exportable skill/expertise nodes found under the identified section.")
            return "[]"
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: exportableNodes, options: [.prettyPrinted])
            return String(data: jsonData, encoding: .utf8)
        } catch {
            print("Error serializing skills nodes to JSON: \(error)")
            return nil
        }
    }

    // MARK: - LLM Request (Existing, for non-fixOverflow types)

    @MainActor
    func sendReviewRequest(
        reviewType: ResumeReviewType,
        resume: Resume,
        customOptions: CustomReviewOptions? = nil,
        onProgress: @escaping (String) -> Void,
        onComplete: @escaping (Result<String, Error>) -> Void
    ) {
        if openAIClient == nil { initialize() }
        guard let client = openAIClient else {
            onComplete(.failure(NSError(domain: "ResumeReviewService", code: 1000, userInfo: [NSLocalizedDescriptionKey: "OpenAI client not initialized"])))
            return
        }

        let supportsImages = checkIfModelSupportsImages()
        var base64Image: String?
        if supportsImages,
           (reviewType != .custom && reviewType != .fixOverflow) || (customOptions?.includeResumeImage ?? false), // fixOverflow handles its own image
           let pdfData = resume.pdfData
        {
            base64Image = convertPDFToBase64Image(pdfData: pdfData)
        }
        let includeImageInPromptText = base64Image != nil

        let promptText = buildPrompt(
            reviewType: reviewType,
            resume: resume,
            includeImage: includeImageInPromptText,
            customOptions: customOptions
        )

        let requestID = UUID(); currentRequestID = requestID

        if includeImageInPromptText, let img = base64Image { // Image request via direct HTTP
            sendDirectOpenAIRequest(
                promptText: promptText,
                base64Image: img,
                previousResponseId: resume.previousResponseId, // Pass along
                schema: nil, // No specific schema for these general reviews yet
                requestID: requestID,
                onProgress: onProgress,
                onComplete: { result in
                    if case let .success(responseWrapper) = result {
                        resume.previousResponseId = responseWrapper.id // Store new response ID
                        onComplete(.success(responseWrapper.content))
                    } else if case let .failure(error) = result {
                        onComplete(.failure(error))
                    }
                }
            )
        } else { // Text-only request, can use existing client methods if they support Responses API or fallback
            Task {
                do {
                    let response = try await client.sendResponseRequestAsync(
                        message: promptText, // Assuming client handles system/user message structuring
                        model: OpenAIModelFetcher.getPreferredModelString(),
                        temperature: 0.7,
                        previousResponseId: resume.previousResponseId,
                        schema: nil // No specific schema for these general reviews
                    )
                    // Ensure request is still current
                    guard self.currentRequestID == requestID else { return }
                    resume.previousResponseId = response.id // Store new response ID
                    onProgress(response.content) // Send full content as one "chunk"
                    onComplete(.success("Review complete"))
                } catch {
                    guard self.currentRequestID == requestID else { return }
                    onComplete(.failure(error))
                }
            }
        }
    }

    // MARK: - Fix Overflow Specific LLM Calls

    /// Sends a request to the LLM to revise skills for fitting, expecting structured JSON output.
    @MainActor
    func sendFixFitsRequest(
        resume: Resume,
        skillsJsonString: String,
        base64Image: String,
        onComplete: @escaping (Result<FixFitsResponseContainer, Error>) -> Void
    ) {
        let prompt = """
        You are an expert resume editor. The 'Skills and Expertise' section in the attached resume image is overflowing. Please revise the content of this section to fit the available space without sacrificing its impact. Prioritize shortening entries that are only slightly too long (e.g., a few words on the last line). Ensure revised entries remain strong and relevant to the job application. Do not shorten entries more than necessary to resolve the overflow and avoid overlapping with elements below. The current skills and expertise content is provided as a JSON array of nodes:

        \(skillsJsonString)

        Respond *only* with a JSON object adhering to the schema provided in the API request's 'text.format.schema' parameter. Each node in your response must include the original 'id', 'originalValue', 'isTitleNode', and 'treePath' fields exactly as they were provided in the input. Provide your suggested change in the 'newValue' field. Set 'valueChanged' to true if you made a change, false otherwise.
        """

        let schemaName = "fix_skills_overflow_schema"
        let schema = ResumeReviewService.fixFitsSchemaString // Use the static schema string

        let requestID = UUID(); currentRequestID = requestID

        sendDirectOpenAIRequest(
            promptText: prompt,
            base64Image: base64Image,
            previousResponseId: resume.previousResponseId,
            schema: (name: schemaName, jsonString: schema),
            requestID: requestID
        ) { result in
            guard self.currentRequestID == requestID else { return } // Check if request is still current
            switch result {
            case let .success(responseWrapper):
                resume.previousResponseId = responseWrapper.id // Update previousResponseId
                do {
                    guard let responseData = responseWrapper.content.data(using: .utf8) else {
                        throw NSError(domain: "ResumeReviewService", code: 1004, userInfo: [NSLocalizedDescriptionKey: "Failed to convert LLM content to Data."])
                    }
                    let decodedResponse = try JSONDecoder().decode(FixFitsResponseContainer.self, from: responseData)
                    onComplete(.success(decodedResponse))
                } catch {
                    onComplete(.failure(error))
                }
            case let .failure(error):
                onComplete(.failure(error))
            }
        }
    }

    /// Sends a request to the LLM to check if content fits, expecting structured JSON output.
    @MainActor
    func sendContentsFitRequest(
        resume: Resume,
        base64Image: String,
        onComplete: @escaping (Result<ContentsFitResponse, Error>) -> Void
    ) {
        let prompt = """
        You are an expert document layout analyzer. Examine the attached resume image, specifically the 'Skills and Experience' box. Does the content within this box fit neatly without overflowing its boundaries or overlapping with any content below it? When there is no overflow, there should be a small, blank, text free region between the lower border of the Skills and Experience box and the top border of the Education box. Be sure that these boxes are not overlapping. Respond *only* with a JSON object adhering to the schema provided in the API request's 'text.format.schema' parameter.
        """
        let schemaName = "check_content_fit_schema"
        let schema = ResumeReviewService.contentsFitSchemaString // Use the static schema string

        let requestID = UUID(); currentRequestID = requestID

        sendDirectOpenAIRequest(
            promptText: prompt,
            base64Image: base64Image,
            previousResponseId: resume.previousResponseId,
            schema: (name: schemaName, jsonString: schema),
            requestID: requestID
        ) { result in
            guard self.currentRequestID == requestID else { return } // Check if request is still current
            switch result {
            case let .success(responseWrapper):
                resume.previousResponseId = responseWrapper.id // Update previousResponseId
                do {
                    guard let responseData = responseWrapper.content.data(using: .utf8) else {
                        throw NSError(domain: "ResumeReviewService", code: 1005, userInfo: [NSLocalizedDescriptionKey: "Failed to convert LLM content to Data for contentsFit."])
                    }
                    let decodedResponse = try JSONDecoder().decode(ContentsFitResponse.self, from: responseData)
                    onComplete(.success(decodedResponse))
                } catch {
                    onComplete(.failure(error))
                }
            case let .failure(error):
                onComplete(.failure(error))
            }
        }
    }

    // MARK: - Direct OpenAI HTTP Request Helper (for image + structured output)

    /// Generic helper to send requests to OpenAI's /v1/responses endpoint.
    /// Handles image data and structured JSON output.
    private func sendDirectOpenAIRequest(
        promptText: String,
        base64Image: String?,
        previousResponseId: String?,
        schema: (name: String, jsonString: String)?, // Optional schema tuple
        requestID: UUID, // To track if the request is still current
        onProgress _: ((String) -> Void)? = nil, // For non-fixOverflow streaming (optional)
        onComplete: @escaping (Result<ResponsesAPIResponse, Error>) -> Void
    ) {
        apiQueue.async { // Perform network request on a background queue
            guard let apiKey = UserDefaults.standard.string(forKey: "openAiApiKey"), apiKey != "none" else {
                DispatchQueue.main.async {
                    onComplete(.failure(NSError(domain: "ResumeReviewService", code: 1001, userInfo: [NSLocalizedDescriptionKey: "OpenAI API key not set."])))
                }
                return
            }

            guard let url = URL(string: "https://api.openai.com/v1/responses") else {
                DispatchQueue.main.async {
                    onComplete(.failure(NSError(domain: "ResumeReviewService", code: 1000, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL."])))
                }
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")

            // Build the content array correctly
            var userInputContent: [[String: Any]] = [["type": "input_text", "text": promptText]]
            if let img = base64Image {
                // Use correct structure for image data in responses API
                userInputContent.append([
                    "type": "input_image",
                    "image_url": "data:image/png;base64,\(img)",
                    "detail": "high", // Optional: consider making this configurable
                ])
            }

            var requestBodyDict: [String: Any] = [
                "model": OpenAIModelFetcher.getPreferredModelString(),
                "input": [
                    ["role": "system", "content": "You are an expert AI assistant."],
                    ["role": "user", "content": userInputContent],
                ],
                "temperature": 0.5,
            ]

            if let prevId = previousResponseId, !prevId.isEmpty {
                requestBodyDict["previous_response_id"] = prevId
            }

            if let schemaInfo = schema,
               let schemaData = schemaInfo.jsonString.data(using: .utf8),
               let schemaJson = try? JSONSerialization.jsonObject(with: schemaData, options: []) as? [String: Any]
            {
                requestBodyDict["text"] = [
                    "format": [
                        "type": "json_schema",
                        "name": schemaInfo.name,
                        "schema": schemaJson,
                        "strict": true,
                    ],
                ]
            }

            // Debug: Print the request body (with image data omitted or truncated)
            var sanitizedRequestBodyDict = requestBodyDict
            if let inputMessages = sanitizedRequestBodyDict["input"] as? [[String: Any]] {
                var sanitizedInputMessages = inputMessages
                for (i, message) in inputMessages.enumerated() {
                    if let contentArray = message["content"] as? [[String: Any]] {
                        var sanitizedContentArray = contentArray
                        for (j, contentItem) in contentArray.enumerated() {
                            if contentItem["type"] as? String == "input_image" {
                                var mutableContentItem = contentItem
                                mutableContentItem["image_url"] = "<base64_image_data_omitted>"
                                sanitizedContentArray[j] = mutableContentItem
                            }
                        }
                        var mutableMessage = message
                        mutableMessage["content"] = sanitizedContentArray
                        sanitizedInputMessages[i] = mutableMessage
                    }
                }
                sanitizedRequestBodyDict["input"] = sanitizedInputMessages
            }

            if let jsonData = try? JSONSerialization.data(withJSONObject: sanitizedRequestBodyDict, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8)
            {
                print("OpenAI Request Body for \(schema?.name ?? "General Review") (Image Omitted):\n\(jsonString)")
            }

            guard let httpBody = try? JSONSerialization.data(withJSONObject: requestBodyDict) else {
                DispatchQueue.main.async {
                    onComplete(.failure(NSError(domain: "ResumeReviewService", code: 1002, userInfo: [NSLocalizedDescriptionKey: "Failed to serialize request body."])))
                }
                return
            }
            request.httpBody = httpBody

            // Rest of the function remains the same...
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                // Ensure the callback is on the main thread
                DispatchQueue.main.async {
                    guard self.currentRequestID == requestID else {
                        print("Request \(requestID) was cancelled or superseded.")
                        return
                    }

                    if let error = error {
                        onComplete(.failure(error))
                        return
                    }
                    guard let httpResponse = response as? HTTPURLResponse else {
                        onComplete(.failure(NSError(domain: "ResumeReviewService", code: 1003, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response."])))
                        return
                    }

                    guard let responseData = data else {
                        onComplete(.failure(NSError(domain: "ResumeReviewService", code: 1006, userInfo: [NSLocalizedDescriptionKey: "No data in API response."])))
                        return
                    }

                    if let responseString = String(data: responseData, encoding: .utf8) {
                        print("OpenAI Raw Response for \(schema?.name ?? "General Review") (Status: \(httpResponse.statusCode)):\n\(responseString)")
                    }

                    if !(200 ... 299).contains(httpResponse.statusCode) {
                        var errorMessage = "API Error: \(httpResponse.statusCode)."
                        if let errorData = data, let errorDetails = String(data: errorData, encoding: .utf8) {
                            errorMessage += " Details: \(errorDetails)"
                        }
                        onComplete(.failure(NSError(domain: "ResumeReviewService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMessage])))
                        return
                    }

                    do {
                        let decodedWrapper = try JSONDecoder().decode(ResponsesAPIResponseWrapper.self, from: responseData)
                        onComplete(.success(decodedWrapper.toResponsesAPIResponse()))
                    } catch let decodingError {
                        print("Error decoding OpenAI Response: \(decodingError)")
                        onComplete(.failure(decodingError))
                    }
                }
            }
            task.resume()
        }
    }

    /// Cancels the current review request
    func cancelRequest() {
        currentRequestID = nil // This will cause ongoing callbacks to be ignored
    }

    // MARK: - Helpers

    private func checkIfModelSupportsImages() -> Bool {
        let model = OpenAIModelFetcher.getPreferredModelString().lowercased()
        let visionModelsSubstrings = ["gpt-4o", "gpt-4-turbo", "gpt-4-vision", "gpt-4.1", "gpt-image", "o4", "cua"]
        return visionModelsSubstrings.contains { model.contains($0) }
    }

    // MARK: - Schemas as static strings

    static let fixFitsSchemaString = """
    {
      "type": "object",
      "properties": {
        "revised_skills_and_expertise": {
          "type": "array",
          "description": "An array of objects, each representing a skill or expertise item with its original ID and revised content.",
          "items": {
            "type": "object",
            "properties": {
              "id": { 
                "type": "string", 
                "description": "The original ID of the TreeNode for the skill." 
              },
              "newValue": { 
                "type": "string", 
                "description": "The revised content for the skill/expertise item. If no change, this should be the same as originalValue." 
              },
              "originalValue": {
                 "type": "string",
                 "description": "The original content of the skill/expertise item (echoed back)."
               },
              "treePath": {
                "type": "string",
                "description": "The original treePath of the skill TreeNode (echoed back)."
              },
              "isTitleNode": {
                "type": "boolean",
                "description": "Indicates if this skill entry is a title/heading (echoed back)."
              }
            },
            "required": ["id", "newValue", "originalValue", "treePath", "isTitleNode"],
            "additionalProperties": false
          }
        }
      },
      "required": ["revised_skills_and_expertise"],
      "additionalProperties": false
    }
    """

    static let contentsFitSchemaString = """
    {
      "type": "object",
      "properties": {
        "contentsFit": { 
          "type": "boolean",
          "description": "True if the content fits within its designated box without overflowing or overlapping other elements, false otherwise."
        }
      },
      "required": ["contentsFit"],
      "additionalProperties": false
    }
    """
}
