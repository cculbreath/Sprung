#!/bin/bash

# Script to apply updates for the "Fix Overflow" feature to PhysCloudResume project.
# WARNING: This script will overwrite existing files. Ensure you have a backup or use version control.

# Set the project directory. Assumes this script is run from the parent of PhysCloudResume.
PROJECT_DIR="./PhysCloudResume" # Use relative path

# Function to create directory if it doesn't exist and then write content to file
write_file_content() {
  local filepath="$1"
  local content_var_name="$2" # Pass the name of the variable holding the content
  local full_path="$PROJECT_DIR/$filepath"
  local dir_path
  local content # Declare content variable locally

  dir_path=$(dirname "$full_path")

  echo "Preparing to update $full_path..."

  if ! mkdir -p "$dir_path"; then
    echo "Error: Could not create directory $dir_path"
    exit 1
  fi
  echo "Directory $dir_path ensured."

  # Safer way to get content from the variable whose name is stored in content_var_name
  # This uses indirect expansion.
  printf -v content "%s" "${!content_var_name}"
  
  if [ -z "$content" ]; then
    echo "Error: Content for $content_var_name is empty. This might indicate an issue with the script itself or variable naming for $filepath."
    # Optionally, exit here or allow script to continue and create empty files
    # exit 1 
  fi

  echo "Updating $full_path..."
  # Use printf for safer content writing.
  printf '%s\n' "$content" > "$full_path"
  
  if [ $? -ne 0 ]; then
    echo "Error: Could not write to file $full_path"
    exit 1
  fi
  echo "Successfully updated $full_path"
  echo "-----------------------------------"
}

# --- File Contents ---

# Content for PhysCloudResume/AI/Models/ResumeReviewType.swift
read -r -d '' RESUME_REVIEW_TYPE_CONTENT << 'ENDOFSWIFT_RESUMEREVIEWTYPE'
// PhysCloudResume/AI/Models/ResumeReviewType.swift

import Foundation

/// Types of resume review operations available
enum ResumeReviewType: String, CaseIterable, Identifiable {
    case suggestChanges = "Suggest Resume Fields to Change"
    case assessQuality = "Assess Overall Resume Quality"
    case assessFit = "Assess Fit for Job Position"
    case fixOverflow = "Fix Skills & Expertise Overflow" // New case
    case custom = "Custom"

    var id: String { rawValue }

    /// Returns the prompt template for this review type
    /// Note: The prompt for fixOverflow will be handled more dynamically by ResumeReviewService
    /// due to its iterative nature and inclusion of image data.
    func promptTemplate() -> String {
        switch self {
        case .assessQuality:
            // Enhanced prompt – asks for a structured, actionable answer in markdown
            return """
            Context:
            ────────────────────────────────────────────
            • Applicant is applying for **{jobPosition}** at **{companyName}**.
            • Full job description is included below.
            • A draft of the applicant’s resume follows the job description.
            {includeImage}

            Job Description
            ----------------
            {jobDescription}

            Resume Draft
            -------------
            {resumeText}

            Task:
            You are an expert hiring manager and resume coach.
            1. Evaluate the overall quality and professionalism of the resume **for this particular role**.
            2. Provide exactly 3 key strengths (bullet list).
            3. Provide exactly 3 concrete, actionable improvements (bullet list).
            4. Give the resume an **overall score from 1-10** for readiness to submit.

            Output format (markdown):
            ### Overall Assessment (Score: <1-10>)

            **Strengths**
            • …
            • …
            • …

            **Areas to Improve**
            • …
            • …
            • …

            Keep the tone encouraging yet direct. Use concise, professional language.
            """

        case .assessFit:
            return """
            Context:
            ────────────────────────────────────────────
            • Applicant wishes to apply for **{jobPosition}** at **{companyName}**.
            • Job description and resume draft are provided.
            {includeImage}

            Job Description
            ----------------
            {jobDescription}

            Resume Draft
            -------------
            {resumeText}

            Task:
            1. Assess how well the candidate’s background matches the role requirements.
            2. List the **top 3 strengths** relevant to the job (bullet list).
            3. List the **top 3 gaps** or missing qualifications (bullet list).
            4. Give a **Fit Rating (1-10)** where 10 = perfect fit.
            5. State in one sentence whether it is worthwhile to apply.

            Output format (markdown):
            ### Fit Analysis (Rating: <1-10>)
            **Strengths**
            • …
            • …
            • …

            **Gaps / Weaknesses**
            • …
            • …
            • …

            **Recommendation**
            <One-sentence recommendation>
            """

        case .suggestChanges:
            return """
            Context:
            ────────────────────────────────────────────
            • Target role: **{jobPosition}** at **{companyName}**.
            • Job description is supplied below.
            • Current resume draft follows.
            • Additional background docs (if any) are appended at the end.

            Job Description
            ----------------
            {jobDescription}

            Resume Draft
            -------------
            {resumeText}

            Background Docs
            ---------------
            {backgroundDocs}

            Task:
            Identify resume sections (titles, bullet points, skill headings, summarized achievements, etc.) that should be **revised or strengthened** to maximise impact for this role.

            For each suggested change give:
            • The current text (quote succinctly)
            • The rationale for change (1-2 sentences)
            • A concise rewritten version (max 40 words)

            Output as a markdown table with columns: *Section*, *Why change?*, *Suggested Rewrite*.
            """
        case .fixOverflow:
            // This prompt is more complex and will be constructed within ResumeReviewService
            // as it involves image data and iterative calls.
            // A base instruction could be:
            return "The 'Skills and Expertise' section of the resume is overflowing. Please adjust the content to fit."
            
        case .custom:
            // Custom prompt will be built dynamically; return empty string here.
            return ""
        }
    }
}

/// Options to include in a custom resume review
struct CustomReviewOptions: Equatable {
    var includeJobListing: Bool = true
    var includeResumeText: Bool = true
    var includeResumeImage: Bool = true
    var customPrompt: String = ""
}
ENDOFSWIFT_RESUMEREVIEWTYPE

# Content for PhysCloudResume/App/Views/SettingsView.swift
read -r -d '' SETTINGS_VIEW_CONTENT << 'ENDOFSWIFT_SETTINGSVIEW'
// PhysCloudResume/App/Views/SettingsView.swift

import SwiftUI

struct SettingsView: View {
    // State variable needed by APIKeysSettingsView callback
    @State private var forceModelFetch = false
    
    // AppStorage for the new Fix Overflow setting
    @AppStorage("fixOverflowMaxIterations") private var fixOverflowMaxIterations: Int = 3


    var body: some View {
        // Use a ScrollView to handle potentially long content
        ScrollView(.vertical, showsIndicators: true) {
            // Main VStack containing all setting sections
            VStack(alignment: .leading, spacing: 20) { // Increased spacing between sections
                // API Keys Section
                APIKeysSettingsView {
                    // This closure is called when the OpenAI key is saved in APIKeysSettingsView
                    forceModelFetch.toggle() // Trigger state change to signal OpenAIModelSettingsView
                }

                // OpenAI Model Selection Section
                OpenAIModelSettingsView()
                    // Observe the state change to trigger a model fetch
                    .id(forceModelFetch) // Use .id to force recreation/update if needed

                // Resume Styles Section
                ResumeStylesSettingsView()

                // Text-to-Speech Settings Section
                TextToSpeechSettingsView()

                // Preferred API Selection Section
                PreferredAPISettingsView()
                
                // Fix Overflow Iterations Setting
                FixOverflowSettingsView(fixOverflowMaxIterations: $fixOverflowMaxIterations)

            }
            .padding() // Add padding around the entire content VStack
        }
        // Set the frame for the settings window
        .frame(minWidth: 450, idealWidth: 600, maxWidth: .infinity,
               minHeight: 550, idealHeight: 750, maxHeight: .infinity) // Adjusted ideal height
        .background(Color(NSColor.controlBackgroundColor)) // Use standard control background
        // Allow the sheet to be resized
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// New subview for Fix Overflow settings
struct FixOverflowSettingsView: View {
    @Binding var fixOverflowMaxIterations: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Resume Overflow Correction")
                .font(.headline)
                .padding(.bottom, 5)

            HStack {
                Text("Max Iterations for 'Fix Overflow':")
                Spacer()
                Stepper(value: $fixOverflowMaxIterations, in: 1...10) {
                    Text("\(fixOverflowMaxIterations)")
                }
                .frame(width: 150) // Adjust width as needed
            }
            .padding(.horizontal, 10)
            
            Text("Controls how many times the AI will attempt to fix overflowing text in the 'Skills & Expertise' section.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
        }
        .padding(10)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.7), lineWidth: 1)
        )
    }
}
ENDOFSWIFT_SETTINGSVIEW

# Content for PhysCloudResume/AI/Models/ResumeReviewService.swift
read -r -d '' RESUME_REVIEW_SERVICE_CONTENT << 'ENDOFSWIFT_RESUMEREVIEWSERVICE'
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
    var treePath: String      // Echoed back by LLM
    var isTitleNode: Bool     // Echoed back by LLM

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
        case contentsFit = "contentsFit"
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
        guard let model = resume.model else {
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
        prompt = prompt.replacingOccurrences(of: "{resumeText}", with: model.renderedResumeText)

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
        guard let rootNode = resume.rootNode,
              let skillsSectionNode = rootNode.children?.first(where: { $0.name.lowercased() == "skills-and-expertise" || $0.name.lowercased() == "skills and expertise" })
        else {
            // Try to find it by a common key if the name isn't exact
            guard let skillsSectionNodeFromKey = rootNode.children?.first(where: { $0.name == "skills-and-expertise"}) else {
                 print("Error: 'Skills and Expertise' section node not found in the resume.")
                 return nil
            }
            return extractTreeNodesForLLM(parentNode: skillsSectionNodeFromKey)
        }
        return extractTreeNodesForLLM(parentNode: skillsSectionNode)
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
                "treePath": node.buildTreePath() 
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
        var base64Image: String? = nil
        if supportsImages,
           (reviewType != .custom && reviewType != .fixOverflow) || (customOptions?.includeResumeImage ?? false), // fixOverflow handles its own image
           let pdfData = resume.pdfData {
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
                    if case .success(let responseWrapper) = result {
                        resume.previousResponseId = responseWrapper.id // Store new response ID
                        onComplete(.success(responseWrapper.content))
                    } else if case .failure(let error) = result {
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
            case .success(let responseWrapper):
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
            case .failure(let error):
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
        You are an expert document layout analyzer. Examine the attached resume image, specifically the 'Skills and Experience' box. Does the content within this box fit neatly without overflowing its boundaries or overlapping with any content below it? Respond *only* with a JSON object adhering to the schema provided in the API request's 'text.format.schema' parameter.
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
            case .success(let responseWrapper):
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
            case .failure(let error):
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
        onProgress: ((String) -> Void)? = nil, // For non-fixOverflow streaming (optional)
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

            var userInputContent: [[String: Any]] = [["type": "text", "text": promptText]]
            if let img = base64Image {
                userInputContent.append(["type": "image_url", "image_url": ["url": "data:image/png;base64,\(img)"]])
            }

            var requestBodyDict: [String: Any] = [
                "model": OpenAIModelFetcher.getPreferredModelString(),
                "input": [ // Changed from 'messages' to 'input' as per Responses API
                    ["role": "system", "content": "You are an expert AI assistant."], // Generic system message
                    ["role": "user", "content": userInputContent]
                ],
                "temperature": 0.5 // A reasonable default, adjust as needed
            ]

            if let prevId = previousResponseId, !prevId.isEmpty {
                requestBodyDict["previous_response_id"] = prevId
            }

            if let schemaInfo = schema,
               let schemaData = schemaInfo.jsonString.data(using: .utf8),
               let schemaJson = try? JSONSerialization.jsonObject(with: schemaData, options: []) as? [String: Any] {
                requestBodyDict["text"] = [
                    "format": [
                        "type": "json_schema",
                        "name": schemaInfo.name,
                        "schema": schemaJson,
                        "strict": true
                    ]
                ]
            }
            
            // Debug: Print the request body
            if let jsonData = try? JSONSerialization.data(withJSONObject: requestBodyDict, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                print("OpenAI Request Body for \(schema?.name ?? "General Review"):\n\(jsonString)")
            }


            guard let httpBody = try? JSONSerialization.data(withJSONObject: requestBodyDict) else {
                DispatchQueue.main.async {
                    onComplete(.failure(NSError(domain: "ResumeReviewService", code: 1002, userInfo: [NSLocalizedDescriptionKey: "Failed to serialize request body."])))
                }
                return
            }
            request.httpBody = httpBody

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                // Ensure the callback is on the main thread
                DispatchQueue.main.async {
                    guard self.currentRequestID == requestID else { // Check if request is still current
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
                    
                    // Debug: Print raw response
                    if let responseString = String(data: responseData, encoding: .utf8) {
                         print("OpenAI Raw Response for \(schema?.name ?? "General Review") (Status: \(httpResponse.statusCode)):\n\(responseString)")
                    }


                    if !(200...299).contains(httpResponse.statusCode) {
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
    
    // Schema for the "fixFits" LLM response (RevisionsContainer equivalent)
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
            "required": ["id", "newValue", "originalValue", "treePath", "isTitleNode"]
          }
        }
      },
      "required": ["revised_skills_and_expertise"]
    }
    """

    // Schema for the "contentsFit" LLM response
    static let contentsFitSchemaString = """
    {
      "type": "object",
      "properties": {
        "contentsFit": { 
          "type": "boolean",
          "description": "True if the content fits within its designated box without overflowing or overlapping other elements, false otherwise."
        }
      },
      "required": ["contentsFit"]
    }
    """
}

// Extension to TreeNode to build its path (you might place this in TreeNodeModel.swift)
// extension TreeNode { // This is now directly in TreeNodeModel.swift
//    func buildTreePath() -> String {
//        var pathComponents: [String] = []
//        var currentNode: TreeNode? = self
//        while let node = currentNode {
//            let nameToUse = node.name.isEmpty ? (node.value.isEmpty ? "Unnamed Node" : String(node.value.prefix(20))) : node.name
//            pathComponents.insert(nameToUse, at: 0)
//            currentNode = node.parent
//        }
//        return pathComponents.joined(separator: " > ")
//    }
//}
ENDOFSWIFT_RESUMEREVIEWSERVICE

# Content for PhysCloudResume/Resumes/Models/Resume.swift
read -r -d '' RESUME_MODEL_CONTENT << 'ENDOFSWIFT_RESUMEMODEL'
// PhysCloudResume/Resumes/Models/Resume.swift

import Foundation
import SwiftData

@Model
class Resume: Identifiable, Hashable {
    @Attribute(.unique) var id: UUID = UUID()

    /// Stores the OpenAI response ID for server-side conversation state
    var previousResponseId: String? = nil

    var needToTree: Bool = true
    var needToFont: Bool = true

    @Relationship(deleteRule: .cascade)
    var rootNode: TreeNode? // The top-level node
    var fontSizeNodes: [FontSizeNode] = []
    var includeFonts: Bool = false
    // Labels for keys previously imported; persisted as keyLabels map
    var keyLabels: [String: String] = [:]
    // Stored raw JSON data for imported editor keys; persisted as Data
    var importedEditorKeysData: Data? = nil
    /// Transient array of editor keys, backed by JSON in importedEditorKeysData
    var importedEditorKeys: [String] {
        get {
            guard let data = importedEditorKeysData else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            importedEditorKeysData = try? JSONEncoder().encode(newValue)
        }
    }

    func label(_ key: String) -> String {
        if let myLabel = keyLabels[key] {
            return myLabel
        } else {
            return key
        }
    }

    /// Computed list of all `TreeNode`s that belong to this resume.
    var nodes: [TreeNode] {
        guard let rootNode else { return [] }
        return Resume.collectNodes(from: rootNode)
    }

    private static func collectNodes(from node: TreeNode) -> [TreeNode] {
        var all: [TreeNode] = [node]
        for child in node.children ?? [] {
            all.append(contentsOf: collectNodes(from: child))
        }
        return all
    }

    var dateCreated: Date = Date()
    weak var jobApp: JobApp?

    @Relationship(deleteRule: .nullify, inverse: \ResRef.enabledResumes)
    var enabledSources: [ResRef]

    var model: ResModel? = nil
    var createdDateString: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "hh:mm a 'on' MM/dd/yy"
        return dateFormatter.string(from: dateCreated)
    }

    var textRes: String = ""
    var pdfData: Data?

    @Transient
    var isExporting: Bool = false
    var jsonTxt: String {
        if let myRoot = rootNode, let json = TreeToJson(rootNode: myRoot)?.buildJsonString() {
            return json
        } else { return "" }
    }

    func getUpdatableNodes() -> [[String: Any]] {
        if let node = rootNode {
            return TreeNode.traverseAndExportNodes(node: node)
        } else {
            return [[:]]
        }
    }

    var meta: String = "\"format\": \"FRESH@0.6.0\", \"version\": \"0.1.0\""

    init(
        jobApp: JobApp,
        enabledSources: [ResRef],
        model: ResModel
    ) {
        self.model = model
        self.jobApp = jobApp
        dateCreated = Date()
        self.enabledSources = enabledSources
    }

    @MainActor
    func generateQuery() async -> ResumeApiQuery {
        return ResumeApiQuery(resume: self)
    }

    func generateQuery() -> ResumeApiQuery {
        let emptyProfile = ApplicantProfile(
            name: "", address: "", city: "", state: "", zip: "",
            websites: "", email: "", phone: ""
        )
        let query = ResumeApiQuery(resume: self, applicantProfile: emptyProfile)
        Task { @MainActor in
            let realApplicant = Applicant()
            query.updateApplicant(realApplicant)
        }
        return query
    }

    func loadPDF(from fileURL: URL = FileHandler.pdfUrl(),
                 completion: (() -> Void)? = nil)
    {
        DispatchQueue.global(qos: .background).async { [weak self] in
            defer { DispatchQueue.main.async { completion?() } }
            do {
                let data = try Data(contentsOf: fileURL)
                DispatchQueue.main.async { self?.pdfData = data }
            } catch {
                print("Error loading PDF from \(fileURL): \(error)")
                DispatchQueue.main.async {}
            }
        }
    }

    @Transient private var exportWorkItem: DispatchWorkItem?

    func debounceExport(onStart: (() -> Void)? = nil,
                        onFinish: (() -> Void)? = nil)
    {
        exportWorkItem?.cancel()
        isExporting = true
        onStart?()

        exportWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if let jsonFile = FileHandler.saveJSONToFile(jsonString: jsonTxt) {
                Task { @MainActor in // Ensure export service call and property updates are on MainActor
                    do {
                        // This now calls the async version of export which updates pdfData and textRes
                        try await ApiResumeExportService().export(jsonURL: jsonFile, for: self)
                    } catch {
                        print("Error during debounced export: \(error)")
                    }
                    self.isExporting = false
                    onFinish?()
                }
            } else {
                print("Failed to save JSON to file for debounced export.")
                Task { @MainActor in // Ensure UI updates are on MainActor
                    self.isExporting = false
                    onFinish?()
                }
            }
        }
        if let workItem = exportWorkItem {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
        }
    }

    // MARK: - Async Rendering and Export (Modified for Fix Overflow)

    @MainActor // Ensure this function and its mutations run on the main actor
    func ensureFreshRenderedText() async throws {
        // Cancel any ongoing debounced export as we want a direct, awaitable one.
        exportWorkItem?.cancel()
        
        isExporting = true
        defer { isExporting = false }

        guard let jsonFile = FileHandler.saveJSONToFile(jsonString: self.jsonTxt) else {
            throw NSError(domain: "ResumeRender", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to save JSON to file for rendering."])
        }

        // Directly call the export service and await its completion.
        // The ApiResumeExportService().export function is already async
        // and should update self.pdfData and self.textRes upon completion.
        do {
            try await ApiResumeExportService().export(jsonURL: jsonFile, for: self)
            print("ensureFreshRenderedText: Successfully exported and updated resume data.")
        } catch {
            print("ensureFreshRenderedText: Failed to export resume - \(error.localizedDescription)")
            throw error // Re-throw the error to be caught by the caller
        }
    }

    // MARK: - Hashable
    static func == (lhs: Resume, rhs: Resume) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
ENDOFSWIFT_RESUMEMODEL

# Content for PhysCloudResume/ResumeTree/Models/TreeNodeModel.swift
read -r -d '' TREE_NODE_MODEL_CONTENT << 'ENDOFSWIFT_TREENODEMODEL'
// PhysCloudResume/ResumeTree/Models/TreeNodeModel.swift

import Foundation
import SwiftData

enum LeafStatus: String, Codable, Hashable {
    case isEditing
    case aiToReplace
    case disabled = "leafDisabled"
    case saved = "leafValueSaved"
    case isNotLeaf = "nodeIsNotLeaf"
}

@Model class TreeNode: Identifiable {
    var id = UUID().uuidString
    var name: String = ""
    var value: String
    var includeInEditor: Bool = false
    var myIndex: Int = -1 // Represents order within its parent's children array
    @Relationship(deleteRule: .cascade) var children: [TreeNode]? = nil
    weak var parent: TreeNode?
    var label: String { return resume.label(name) } // Assumes resume.label handles missing keys
    @Relationship(deleteRule: .noAction) var resume: Resume
    var status: LeafStatus
    var depth: Int = 0

    // This property should be explicitly set when a node is created or its role changes.
    // It's not reliably computable based on name/value alone.
    // For the "Fix Overflow" feature, we will pass this to the LLM and expect it back.
    var isTitleNode: Bool = false 

    var hasChildren: Bool {
        return !(children?.isEmpty ?? true)
    }

    var orderedChildren: [TreeNode] {
        (children ?? []).sorted { $0.myIndex < $1.myIndex }
    }

    var aiStatusChildren: Int {
        var count = 0
        if status == .aiToReplace {
            count += 1
        }
        if let children = children {
            for child in children {
                count += child.aiStatusChildren
            }
        }
        return count
    }

    init(
        name: String, value: String = "", children: [TreeNode]? = nil,
        parent: TreeNode? = nil, inEditor: Bool, status: LeafStatus = LeafStatus.disabled,
        resume: Resume, isTitleNode: Bool = false // Added isTitleNode to initializer
    ) {
        self.name = name
        self.value = value
        self.children = children
        self.parent = parent
        self.status = status
        includeInEditor = inEditor
        depth = parent != nil ? parent!.depth + 1 : 0
        self.resume = resume
        self.isTitleNode = isTitleNode // Initialize isTitleNode
    }

    @discardableResult
    func addChild(_ child: TreeNode) -> TreeNode {
        if children == nil {
            children = []
        }
        child.parent = self
        child.myIndex = (children?.count ?? 0)
        child.depth = depth + 1
        children?.append(child)
        return child
    }

    var growDepth: Bool { depth > 2 }

    static func traverseAndExportNodes(node: TreeNode, currentPath: String = "")
        -> [[String: Any]]
    {
        var result: [[String: Any]] = []
        let newPath = node.buildTreePath() // Use the instance method

        // Export node if it's marked for AI replacement OR if it's a title node (even if not for replacement, LLM might need context)
        // For "Fix Overflow", we are specifically interested in nodes from the "Skills & Expertise" section,
        // which will be filtered by the caller (extractSkillsForLLM in ResumeReviewService).
        // This function is more general for AI updates.
        if node.status == .aiToReplace {
            // If it's a title node (name is primary content)
            if node.isTitleNode && !node.name.isEmpty { // Check isTitleNode first
                let titleNodeData: [String: Any] = [
                    "id": node.id,
                    "value": node.name, // Exporting node.name as "value" for the LLM
                    "tree_path": newPath, // Path to this node
                    "isTitleNode": true, // Explicitly mark as title node
                ]
                result.append(titleNodeData)
            }
            // If it's a value node (value is primary content, or name is empty)
            // Also include title nodes if they *also* have a value to be edited separately.
            // For "Fix Overflow", we ensure only one piece of text (name or value) is sent per node ID for revision.
            // The extractSkillsForLLM function will handle this specific logic.
            // This general function might send both if a title node also has a value and is aiToReplace.
            if !node.value.isEmpty && !node.isTitleNode { // Ensure this isn't a title node already processed
                 let valueNodeData: [String: Any] = [
                    "id": node.id,
                    "value": node.value, // Exporting node.value
                    "tree_path": newPath,
                    "isTitleNode": false, // Explicitly mark as not a title node
                ]
                result.append(valueNodeData)
            }
        }

        for child in node.children ?? [] {
            // Pass the child's full path for its children's context
            result.append(contentsOf: traverseAndExportNodes(node: child, currentPath: newPath))
        }
        return result
    }
    
    static func updateValues(from jsonFileURL: URL, using context: ModelContext) throws {
        let jsonData = try Data(contentsOf: jsonFileURL)
        guard let jsonArray = try JSONSerialization.jsonObject(
            with: jsonData, options: []
        ) as? [[String: String]] else {
            print("Failed to parse JSON or JSON is not an array of dictionaries.")
            return
        }

        for jsonObject in jsonArray {
            if let id = jsonObject["id"], let newValue = jsonObject["value"], let isTitleNodeString = jsonObject["isTitleNode"],
               let isTitleNode = Bool(isTitleNodeString) {
                let fetchRequest = FetchDescriptor<TreeNode>(
                    predicate: #Predicate { $0.id == id }
                )
                if let node = try context.fetch(fetchRequest).first {
                    if isTitleNode {
                        node.name = newValue
                    } else {
                        node.value = newValue
                    }
                } else {
                    print("TreeNode with ID \(id) not found.")
                }
            } else {
                print("Skipping invalid JSON object: \(jsonObject)")
            }
        }
        try context.save()
    }

    static func deleteTreeNode(node: TreeNode, context: ModelContext) {
        for child in node.children ?? [] {
            deleteTreeNode(node: child, context: context)
        }
        if let parent = node.parent, let index = parent.children?.firstIndex(of: node) {
            parent.children?.remove(at: index)
        }
        context.delete(node)
        do {
            try context.save()
        } catch {
            print("Failed to save context after deleting TreeNode: \(error)")
        }
    }

    func deepCopy(newResume: Resume) -> TreeNode {
        let copyNode = TreeNode(
            name: name,
            value: value,
            parent: nil,
            inEditor: includeInEditor,
            status: status,
            resume: newResume,
            isTitleNode: isTitleNode // Copy isTitleNode
        )
        copyNode.myIndex = myIndex 

        if let children = children {
            for child in children {
                let childCopy = child.deepCopy(newResume: newResume)
                copyNode.addChild(childCopy)
            }
        }
        return copyNode
    }

    /// Builds the hierarchical path string for this node.
    /// Example: "Resume > Skills and Expertise > Software > Swift"
    func buildTreePath() -> String {
        var pathComponents: [String] = []
        var currentNode: TreeNode? = self
        while let node = currentNode {
            var componentName = "Unnamed Node"
            if !node.name.isEmpty {
                componentName = node.name
            } else if !node.value.isEmpty {
                componentName = String(node.value.prefix(20)) + (node.value.count > 20 ? "..." : "")
            }
            if node.parent == nil && node.name.lowercased() == "root" { // Check for root specifically
                 componentName = "Resume"
            }
            pathComponents.insert(componentName, at: 0)
            currentNode = node.parent
        }
        return pathComponents.joined(separator: " > ")
    }
}
ENDOFSWIFT_TREENODEMODEL

# Content for PhysCloudResume/AI/Views/ResumeReviewSheet.swift
read -r -d '' RESUME_REVIEW_SHEET_CONTENT << 'ENDOFSWIFT_RESUMEREVIEWSHEET'
// PhysCloudResume/AI/Views/ResumeReviewSheet.swift

import SwiftUI
import PDFKit // Required for PDFDocument access if not already imported

struct ResumeReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext // For finding TreeNodes

    @Binding var selectedResume: Resume?
    // Use the existing reviewService, it now has the new methods
    private let reviewService = ResumeReviewService()

    @State private var selectedReviewType: ResumeReviewType = .assessQuality
    @State private var customOptions = CustomReviewOptions() // For .custom type
    
    // State for general review text response (used by other review types)
    @State private var reviewResponseText = ""
    
    // State specific to Fix Overflow feature
    @State private var fixOverflowStatusMessage: String = ""
    @State private var isProcessingFixOverflow: Bool = false
    @State private var fixOverflowError: String? = nil

    // General processing and error state (can be shared or separated)
    @State private var isProcessingGeneral: Bool = false
    @State private var generalError: String? = nil
    
    // AppStorage for max iterations
    @AppStorage("fixOverflowMaxIterations") private var fixOverflowMaxIterations: Int = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text("AI Resume Review")
                .font(.title)
                .padding(.bottom, 8)

            // Review type selection
            Picker("Review Type", selection: $selectedReviewType) {
                ForEach(ResumeReviewType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedReviewType) { _, _ in
                // Reset states when review type changes
                reviewResponseText = ""
                fixOverflowStatusMessage = ""
                isProcessingGeneral = false
                isProcessingFixOverflow = false
                generalError = nil
                fixOverflowError = nil
            }

            // Custom options if custom type is selected
            if selectedReviewType == .custom {
                CustomReviewOptionsView(customOptions: $customOptions)
            }

            // Response Area
            Group {
                if isProcessingGeneral {
                    ProgressView { Text(reviewResponseText.isEmpty ? "Analyzing resume..." : reviewResponseText) }
                } else if isProcessingFixOverflow {
                    ProgressView { Text(fixOverflowStatusMessage.isEmpty ? "Optimizing skills section..." : fixOverflowStatusMessage) }
                } else if !reviewResponseText.isEmpty { // For general reviews
                    ScrollView {
                        Text(reviewResponseText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                } else if !fixOverflowStatusMessage.isEmpty { // For fix overflow completion/status
                     ScrollView {
                        Text(fixOverflowStatusMessage)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                } else if let error = generalError ?? fixOverflowError {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                } else {
                    if selectedReviewType == .fixOverflow {
                        Text("Ready to optimize the 'Skills & Expertise' section to prevent text overflow.")
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                         Text("Select a review type and submit your request.")
                            .foregroundColor(.secondary)
                            .padding()
                    }
                }
            }
            .frame(minHeight: 200)

            // Button row
            HStack {
                if isProcessingGeneral || isProcessingFixOverflow {
                    Button("Stop") {
                        reviewService.cancelRequest() // General cancel
                        isProcessingGeneral = false
                        isProcessingFixOverflow = false
                        fixOverflowStatusMessage = "Optimization stopped by user."
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Button("Close") { dismiss() }
                } else {
                    Button(selectedReviewType == .fixOverflow ? "Optimize Skills" : "Submit Request") {
                        handleSubmit()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedResume == nil)
                    Spacer()
                    Button("Close") { dismiss() }
                }
            }
        }
        .padding()
        .frame(width: 600, height: 500, alignment: .topLeading)
        .onAppear {
            // Initialize service if needed (though it's a let constant now)
            reviewService.initialize()
        }
    }

    // View for custom options (extracted for clarity)
    private struct CustomReviewOptionsView: View {
        @Binding var customOptions: CustomReviewOptions

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("Custom Review Options")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Include Job Listing", isOn: $customOptions.includeJobListing)
                    Toggle("Include Resume Text", isOn: $customOptions.includeResumeText)
                    Toggle("Include Resume Image", isOn: $customOptions.includeResumeImage)
                }
                Text("Custom Prompt")
                    .font(.headline)
                    .padding(.top, 4)
                TextEditor(text: $customOptions.customPrompt)
                    .font(.body)
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .frame(minHeight: 100)
            }
            .padding(.vertical, 8)
        }
    }
    
    // Main submission handler
    private func handleSubmit() {
        guard let resume = selectedResume else {
            generalError = "No resume selected."
            return
        }

        // Reset states
        reviewResponseText = ""
        fixOverflowStatusMessage = ""
        generalError = nil
        fixOverflowError = nil

        if selectedReviewType == .fixOverflow {
            isProcessingFixOverflow = true
            fixOverflowStatusMessage = "Starting skills optimization..."
            Task {
                await performFixOverflow(resume: resume)
                // isProcessingFixOverflow will be set to false at the end of performFixOverflow
            }
        } else {
            isProcessingGeneral = true
            reviewResponseText = "Submitting request..."
            // Call the existing general review request logic
            reviewService.sendReviewRequest(
                reviewType: selectedReviewType,
                resume: resume,
                customOptions: selectedReviewType == .custom ? customOptions : nil,
                onProgress: { contentChunk in
                    DispatchQueue.main.async {
                        if reviewResponseText == "Submitting request..." { reviewResponseText = "" }
                        reviewResponseText += contentChunk
                    }
                },
                onComplete: { result in
                    DispatchQueue.main.async {
                        isProcessingGeneral = false
                        switch result {
                        case .success(let finalMessage):
                            if reviewResponseText.isEmpty { // If no streaming chunks came through
                                reviewResponseText = finalMessage
                            } else if finalMessage != "Review complete" && !reviewResponseText.contains(finalMessage) {
                                // Append if it's a meaningful final message not already part of stream
                                // reviewResponseText += "\n\n" + finalMessage
                            }
                            // Optionally, refine the final message shown
                            if reviewResponseText.isEmpty {  reviewResponseText = "Review complete."}

                        case .failure(let error):
                            generalError = "Error: \(error.localizedDescription)"
                        }
                    }
                }
            )
        }
    }

    // MARK: - Fix Overflow Logic
    @MainActor
    private func performFixOverflow(resume: Resume) async {
        var loopCount = 0
        // previousResponseId is managed by the resume object itself via the service
        var operationSuccess = false
        
        // Ensure resume.pdfData is current before starting
        if resume.pdfData == nil {
            fixOverflowStatusMessage = "Generating initial PDF for analysis..."
            do {
                try await resume.ensureFreshRenderedText() 
                guard resume.pdfData != nil else {
                    fixOverflowError = "Failed to generate initial PDF for Fix Overflow."
                    isProcessingFixOverflow = false
                    return
                }
            } catch {
                fixOverflowError = "Error generating initial PDF: \(error.localizedDescription)"
                isProcessingFixOverflow = false
                return
            }
        }

        repeat {
            loopCount += 1
            fixOverflowStatusMessage = "Iteration \(loopCount)/\(fixOverflowMaxIterations): Analyzing skills section..."

            guard let currentPdfData = resume.pdfData,
                  let currentImageBase64 = reviewService.convertPDFToBase64Image(pdfData: currentPdfData) else {
                fixOverflowError = "Error converting current resume to image (Iteration \(loopCount))."
                break 
            }

            guard let skillsJsonString = reviewService.extractSkillsForLLM(resume: resume) else {
                fixOverflowError = "Error extracting skills from resume (Iteration \(loopCount))."
                break
            }
            
            if skillsJsonString == "[]" {
                fixOverflowStatusMessage = "No 'Skills and Expertise' items found to optimize or section is empty."
                operationSuccess = true 
                break
            }

            fixOverflowStatusMessage = "Iteration \(loopCount): Asking AI to revise skills..."
            
            let fixFitsResult: Result<FixFitsResponseContainer, Error> = await Task {
                await withCheckedContinuation { continuation in
                    reviewService.sendFixFitsRequest(
                        resume: resume, 
                        skillsJsonString: skillsJsonString,
                        base64Image: currentImageBase64
                    ) { result in
                        continuation.resume(returning: result)
                    }
                }
            }.result
            
            guard case .success(let fixFitsResponse) = fixFitsResult else {
                if case .failure(let error) = fixFitsResult {
                    fixOverflowError = "Error getting skill revisions (Iteration \(loopCount)): \(error.localizedDescription)"
                } else {
                    fixOverflowError = "Unknown error getting skill revisions (Iteration \(loopCount))."
                }
                break
            }

            fixOverflowStatusMessage = "Iteration \(loopCount): Applying suggested revisions..."
            var changesMadeInThisIteration = false
            for revisedNode in fixFitsResponse.revisedSkillsAndExpertise {
                if let treeNode = findTreeNode(byId: revisedNode.id, in: resume) {
                    if revisedNode.isTitleNode {
                        if treeNode.name != revisedNode.newValue {
                            treeNode.name = revisedNode.newValue
                            changesMadeInThisIteration = true
                        }
                    } else {
                        if treeNode.value != revisedNode.newValue {
                            treeNode.value = revisedNode.newValue
                            changesMadeInThisIteration = true
                        }
                    }
                } else {
                    print("Warning: TreeNode with ID \(revisedNode.id) not found for applying revision.")
                }
            }
            
            if !changesMadeInThisIteration && loopCount > 1 { 
                fixOverflowStatusMessage = "AI suggested no further changes. Assuming content fits or cannot be further optimized."
                operationSuccess = true 
                break
            }

            fixOverflowStatusMessage = "Iteration \(loopCount): Re-rendering resume with changes..."
            do {
                try await resume.ensureFreshRenderedText() 
                 guard resume.pdfData != nil else {
                    fixOverflowError = "Failed to re-render PDF after applying changes (Iteration \(loopCount))."
                    break
                }
            } catch {
                fixOverflowError = "Error re-rendering PDF (Iteration \(loopCount)): \(error.localizedDescription)"
                break
            }

            guard let updatedPdfData = resume.pdfData,
                  let updatedImageBase64 = reviewService.convertPDFToBase64Image(pdfData: updatedPdfData) else {
                fixOverflowError = "Error converting updated resume to image (Iteration \(loopCount))."
                break
            }

            fixOverflowStatusMessage = "Iteration \(loopCount): Asking AI to check if content fits..."
            let contentsFitResult: Result<ContentsFitResponse, Error> = await Task {
                await withCheckedContinuation { continuation in
                    reviewService.sendContentsFitRequest(
                        resume: resume, 
                        base64Image: updatedImageBase64
                    ) { result in
                        continuation.resume(returning: result)
                    }
                }
            }.result
            
            guard case .success(let contentsFitResponse) = contentsFitResult else {
                if case .failure(let error) = contentsFitResult {
                     fixOverflowError = "Error checking content fit (Iteration \(loopCount)): \(error.localizedDescription)"
                } else {
                    fixOverflowError = "Unknown error checking content fit (Iteration \(loopCount))."
                }
                break
            }

            if contentsFitResponse.contentsFit {
                fixOverflowStatusMessage = "AI confirms content fits after \(loopCount) iteration(s)."
                operationSuccess = true
                break 
            }

            if loopCount >= fixOverflowMaxIterations {
                fixOverflowStatusMessage = "Reached maximum iterations (\(fixOverflowMaxIterations)). Manual review of skills section recommended."
                operationSuccess = false 
                break 
            }
            
            fixOverflowStatusMessage = "Iteration \(loopCount): Content still overflowing. Preparing for next iteration..."
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay

        } while true 

        if fixOverflowError != nil {
            // Error message is already set
        } else if operationSuccess {
             // Success message already set if contentsFit was true
            if !fixOverflowStatusMessage.lowercased().contains("fits") { // If not already set by fit
                 fixOverflowStatusMessage = "Skills section optimization complete."
            }
        } else if loopCount >= fixOverflowMaxIterations {
            // Message for max iterations already set
        } else {
             fixOverflowStatusMessage = "Fix Overflow operation did not complete as expected. Please review."
        }

        isProcessingFixOverflow = false
        resume.debounceExport() // Ensure final state is saved and PDF view updates
    }

    // Helper to find TreeNode by ID within the selected resume
    private func findTreeNode(byId id: String, in resume: Resume) -> TreeNode? {
        // Use the computed `nodes` property which flattens the tree
        return resume.nodes.first { $0.id == id }
    }
}

#Preview {
    // Previewing this sheet requires a more complex setup due to @Binding and @Environment.
    // For now, a simple placeholder or direct instantiation if possible.
    struct PreviewWrapper: View {
        @State private var mockResume: Resume? = nil
        // In a real preview, you'd need to provide a mock ModelContainer
        // and potentially mock JobAppStore, ResStore, etc.
        var body: some View {
            Text("ResumeReviewSheet Preview (requires mock data setup)")
            // Example of how you might try to instantiate it if mocks were available:
            // ResumeReviewSheet(selectedResume: $mockResume)
            //     .environment(\.modelContext, try! ModelContainer(for: Resume.self).mainContext)
        }
    }
    return PreviewWrapper()
}
ENDOFSWIFT_RESUMEREVIEWSHEET

# --- Apply updates ---
echo "Starting file updates for Fix Overflow feature..."

write_file_content "AI/Models/ResumeReviewType.swift" "RESUME_REVIEW_TYPE_CONTENT"
write_file_content "App/Views/SettingsView.swift" "SETTINGS_VIEW_CONTENT"
write_file_content "AI/Models/ResumeReviewService.swift" "RESUME_REVIEW_SERVICE_CONTENT"
write_file_content "Resumes/Models/Resume.swift" "RESUME_MODEL_CONTENT"
write_file_content "ResumeTree/Models/TreeNodeModel.swift" "TREE_NODE_MODEL_CONTENT"
write_file_content "AI/Views/ResumeReviewSheet.swift" "RESUME_REVIEW_SHEET_CONTENT"

echo ""
echo "All file updates attempted."
echo "IMPORTANT: Please review the changes carefully, especially in ResumeReviewSheet.swift for the loop logic and asynchronous operations."
echo "Remember to test thoroughly after applying these changes."

