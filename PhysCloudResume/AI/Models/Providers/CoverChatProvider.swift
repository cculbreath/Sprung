// PhysCloudResume/AI/Models/CoverChatProvider.swift

import Foundation
import PDFKit
import AppKit
import SwiftUI
import SwiftData

@Observable
final class CoverChatProvider: BaseLLMProvider {
    // Stores generic chat messages for the abstraction layer (legacy)
    var genericMessages: [ChatMessage] = []
    var resultsAvailable: Bool = false
    var lastResponse: String = ""
    
    /// Extract cover letter content from response, handling Gemini and Claude JSON formats
    func extractCoverLetterContent(from text: String) -> String {
        // Check if the response contains curly braces (indicating JSON)
        if text.contains("{") && text.contains("}") {
            // Find the JSON portion (from first { to last })
            if let jsonStart = text.range(of: "{"),
               let jsonEnd = text.range(of: "}", options: .backwards) {
                let jsonSubstring = String(text[jsonStart.lowerBound...jsonEnd.upperBound])
                
                // Try to parse the JSON
                if let data = jsonSubstring.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    // First check for known field names
                    let knownKeys = ["cover_letter_body", "body_content", "cover_letter", "letter", "content", "text"]
                    for key in knownKeys {
                        if let value = json[key] as? String {
                            return value
                        }
                    }
                    
                    // If no known keys found, look for any string value that looks like cover letter content
                    // (long enough to be a cover letter, contains multiple sentences/paragraphs)
                    for (_, value) in json {
                        if let stringValue = value as? String,
                           stringValue.count > 100,  // At least 100 characters
                           stringValue.contains(".") || stringValue.contains("\n") {  // Has sentences or paragraphs
                            return stringValue
                        }
                    }
                    
                    // If JSON has only one key-value pair with a string value, use it
                    if json.count == 1,
                       let firstValue = json.values.first as? String {
                        return firstValue
                    }
                }
            }
        }
        
        // If no JSON detected or parsing failed, return as-is
        return text
    }
    

    // MARK: - Initializers

    /// Initialize with the app state
    /// - Parameter appState: The application state
    override init(appState: AppState) {
        // Get the current model and create appropriate client
        let modelString = OpenAIModelFetcher.getPreferredModelString()
        let client = AppLLMClientFactory.createClientForModel(model: modelString, appState: appState)
        super.init(client: client)
        Logger.debug("🎯 CoverChatProvider initialized with model: \(modelString)")
    }
    
    /// Initialize with AppLLM client
    /// - Parameter client: AppLLM client conforming to AppLLMClientProtocol
    override init(client: AppLLMClientProtocol) {
        super.init(client: client)
    }
    

    /// Formats the model name to a simplified version
    /// - Parameter modelName: The full model name from the API
    /// - Returns: A simplified model name without snapshot dates
    private func formatModelName(_ modelName: String) -> String {
        // Use AIModels helper if available, otherwise use our local implementation
        if let formattedName = AIModels.friendlyModelName(for: modelName) {
            return formattedName
        }
        
        // Fallback logic if AIModels doesn't have this model
        let components = modelName.split(separator: "-")

        // Handle different model naming patterns
        if modelName.lowercased().contains("gpt") {
            if components.count >= 2 {
                // Extract main version (e.g., "GPT-4" from "gpt-4-1106-preview")
                if components[1].allSatisfy({ $0.isNumber || $0 == "." }) { // Check if it's a version number like 4 or 3.5
                    return "GPT-\(components[1])"
                }
            }
        } else if modelName.lowercased().contains("claude") {
            // Handle Claude models
            if components.count >= 2 {
                if components[1] == "3" && components.count >= 3 {
                    // Handle "claude-3-opus-20240229" -> "Claude 3 Opus"
                    return "Claude 3 \(components[2].capitalized)"
                } else {
                    // Handle other Claude versions
                    return "Claude \(components[1])"
                }
            }
        }
        // Default fallback: Use the first part of the model name, capitalized.
        return modelName.split(separator: "-").first?.capitalized ?? modelName.capitalized
    }

    /// Add a user message to the chat history
    /// - Parameter text: The message text
    override func addUserMessage(_ text: String) -> [AppLLMMessage] {
        // Use the base class implementation
        return super.addUserMessage(text)
    }

    /// Add an assistant message to the chat history
    /// - Parameter text: The message text
    override func addAssistantMessage(_ text: String) -> [AppLLMMessage] {
        // Use the base class implementation
        return super.addAssistantMessage(text)
    }

    /// Calls the LLM API to generate a cover letter
    /// - Parameters:
    ///   - res: The resume to use
    ///   - jobAppStore: The job app store
    ///   - chatProvider: The chat provider
    ///   - buttons: The cover letter buttons
    ///   - isNewConversation: Whether this is a new conversation (toolbar button press)
    @MainActor
    func coverChatAction(
        res: Resume?,
        jobAppStore: JobAppStore,
        chatProvider _: CoverChatProvider, // chatProvider is self, no need to pass
        buttons: Binding<CoverLetterButtons>,
        isNewConversation: Bool = true
    ) {
        guard let app = jobAppStore.selectedApp else { return }
        guard let selectedCover = app.selectedCover else { return }

        // If generating a new cover letter (using squiggle button) and the current letter is already generated,
        // create a new cover letter by getting the CoverLetterStore from the JobAppStore
        var letter = selectedCover
        if isNewConversation, selectedCover.generated {
            // Create a new cover letter for a fresh generation
            let newLetter = jobAppStore.coverLetterStore.createDuplicate(letter: selectedCover)
            app.selectedCover = newLetter
            letter = newLetter
        }

        buttons.wrappedValue.runRequested = true

        if isNewConversation {
            // Clear conversation context and reset our history synchronously
            letter.clearConversationContext()
            conversationHistory = []
            Logger.debug("🧹 Cleared conversation context for new conversation")
        }

        let modelString = OpenAIModelFetcher.getPreferredModelString()
        var systemMessage = CoverLetterPrompts.systemMessage.content
        
        // Model-specific formatting instructions
        if modelString.lowercased().contains("gemini") {
            systemMessage += " Do not format your response as JSON. Return the cover letter text directly without any JSON wrapping or structure."
        } else if modelString.lowercased().contains("claude") {
            // Claude tends to return JSON even when not asked, so be very explicit
            systemMessage += "\n\nIMPORTANT: Return ONLY the plain text body of the cover letter. Do NOT include JSON formatting, do NOT include 'Dear Hiring Manager' or any salutation, do NOT include any closing or signature. Start directly with the first paragraph of the letter body and end with the last paragraph. No JSON, no formatting, just the plain text paragraphs."
        }
        
        // Get the user input depending on the mode
        let userMessage = CoverLetterPrompts.generate(
            coverLetter: letter,
            resume: res!, // Already safely unwrapped above
            mode: letter.currentMode ?? CoverAiMode.none
        )

        // Update the letter's AI mode to match what we're actually doing
        if letter.currentMode == nil || letter.currentMode == CoverAiMode.none {
            letter.currentMode = .generate
        }
        
        // Initialize or continue conversation using BaseLLMProvider methods
        if isNewConversation {
            _ = initializeConversation(systemPrompt: systemMessage, userPrompt: userMessage)
            Logger.debug("📝 Initialized conversation with \(conversationHistory.count) messages")
        } else {
            _ = addUserMessage(userMessage)
            Logger.debug("📝 Added user message, total messages: \(conversationHistory.count)")
        }

        Task {
            do {
                // Create query using our conversation history
                Logger.debug("📦 Creating query with \(conversationHistory.count) messages")
                if conversationHistory.isEmpty {
                    Logger.error("⚠️ Conversation history is empty!")
                }
                let query = AppLLMQuery(
                    messages: conversationHistory,
                    modelIdentifier: modelString,
                    temperature: 1.0
                )
                
                // Execute query directly using our BaseLLMProvider client
                let response = try await executeQuery(query)
                
                // Extract response content
                let responseText: String
                switch response {
                case .text(let text):
                    // Check if this is a JSON response from Gemini
                    responseText = extractCoverLetterContent(from: text)
                case .structured(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        responseText = extractCoverLetterContent(from: text)
                    } else {
                        responseText = ""
                    }
                }
                
                // Add response to conversation history
                _ = addAssistantMessage(responseText)
                
                // Process results to update the cover letter
                processResults(
                    newMessage: responseText,
                    coverLetter: letter,
                    buttons: buttons,
                    model: modelString,
                    isRevision: !isNewConversation // Revision if continuing conversation
                )
            } catch {
                buttons.wrappedValue.runRequested = false
                self.errorMessage = "Error: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Conversational Methods
    
    /// Starts a new conversation for cover letter generation/revision
    /// - Parameters:
    ///   - coverLetter: The cover letter to work with
    ///   - userMessage: The initial user message
    ///   - onProgress: Progress callback for streaming responses
    ///   - onComplete: Completion callback with result
    @MainActor
    func startNewCoverLetterConversation(
        coverLetter: CoverLetter,
        userMessage: String,
        onProgress: @escaping (String) -> Void = { _ in },
        onComplete: @escaping (Result<String, Error>) -> Void = { _ in }
    ) {
        // Build system prompt for cover letters
        let systemPrompt = buildCoverLetterSystemPrompt(for: coverLetter)
        
        // Clear conversation history
        conversationHistory = []
        
        // Initialize conversation
        _ = initializeConversation(systemPrompt: systemPrompt, userPrompt: userMessage)
        
        // Execute query
        Task {
            do {
                let modelString = OpenAIModelFetcher.getPreferredModelString()
                
                // Create query
                let query = AppLLMQuery(
                    messages: conversationHistory,
                    modelIdentifier: modelString,
                    temperature: 1.0
                )
                
                // Get response
                let response = try await executeQuery(query)
                
                // Extract response text
                let responseText: String
                switch response {
                case .text(let text):
                    responseText = text
                    onProgress(text)
                case .structured(let data):
                    responseText = String(data: data, encoding: .utf8) ?? ""
                    onProgress(responseText)
                }
                
                // Add response to conversation
                _ = addAssistantMessage(responseText)
                
                onComplete(.success(responseText))
            } catch {
                onComplete(.failure(error))
            }
        }
    }
    
    /// Continues an existing conversation for the cover letter
    /// - Parameters:
    ///   - coverLetter: The cover letter being discussed
    ///   - userMessage: The user's message to continue the conversation
    ///   - onProgress: Progress callback for streaming responses
    ///   - onComplete: Completion callback with result
    @MainActor
    func continueCoverLetterConversation(
        coverLetter: CoverLetter,
        userMessage: String,
        onProgress: @escaping (String) -> Void = { _ in },
        onComplete: @escaping (Result<String, Error>) -> Void = { _ in }
    ) {
        // Add user message to conversation
        _ = addUserMessage(userMessage)
        
        // Execute query
        Task {
            do {
                let modelString = OpenAIModelFetcher.getPreferredModelString()
                
                // Create query
                let query = AppLLMQuery(
                    messages: conversationHistory,
                    modelIdentifier: modelString,
                    temperature: 1.0
                )
                
                // Get response
                let response = try await executeQuery(query)
                
                // Extract response text
                let responseText: String
                switch response {
                case .text(let text):
                    responseText = text
                    onProgress(text)
                case .structured(let data):
                    responseText = String(data: data, encoding: .utf8) ?? ""
                    onProgress(responseText)
                }
                
                // Add response to conversation
                _ = addAssistantMessage(responseText)
                
                onComplete(.success(responseText))
            } catch {
                onComplete(.failure(error))
            }
        }
    }
    
    /// Builds a system prompt for cover letter conversations
    /// - Parameter coverLetter: The cover letter to build the prompt for
    /// - Returns: A system prompt string
    private func buildCoverLetterSystemPrompt(for coverLetter: CoverLetter) -> String {
        // Build a comprehensive system prompt for cover letter assistance
        var systemPrompt = """
        You are an expert cover letter writing assistant. Your role is to help create, revise, and improve cover letters that are personalized, compelling, and professional.
        
        Current cover letter content:
        \(coverLetter.content)
        """
        
        // Add job application context if available
        if let jobApp = coverLetter.jobApp {
            systemPrompt += """
            
            Job Application Context:
            - Position: \(jobApp.jobPosition)
            - Company: \(jobApp.companyName)
            - Job Description: \(jobApp.jobDescription)
            """
        }
        
        systemPrompt += """
        
        Please provide helpful suggestions, improvements, and revisions to make this cover letter more effective for the target position.
        """
        
        // For Gemini models, explicitly state not to use JSON formatting
        let modelString = OpenAIModelFetcher.getPreferredModelString()
        if modelString.lowercased().contains("gemini") {
            systemPrompt += " Do not format your response as JSON. Return the text directly without any JSON wrapping or structure."
        }
        
        return systemPrompt
    }

    private func processResults(
        newMessage: String,
        coverLetter: CoverLetter,
        buttons: Binding<CoverLetterButtons>,
        model: String? = nil,
        isRevision: Bool // True if this is a revision of an existing letter
    ) {
        // Update the cover letter with the response
        coverLetter.content = newMessage
        coverLetter.generated = true
        coverLetter.moddedDate = Date()
        coverLetter.generationModel = model

        let formattedModel = formatModelName(model ?? "LLM")

        // Naming logic update:
        if isRevision {
            // For revisions, we should already have a new cover letter with
            // the appropriate option letter assigned in createDuplicate,
            // so we just need to append the revision type if it's not present
            let revisionType = coverLetter.editorPrompt.operation.rawValue

            // Extract the part after the colon (if it exists)
            let nameBase = coverLetter.editableName

            // Only append the revision type if it's not already there
            if !nameBase.contains(revisionType) {
                coverLetter.setEditableName(nameBase + ", " + revisionType)
            }
        } else {
            // This is a fresh generation of content (not a revision)
            // Either the first generation for this letter or a regeneration
            // with the Generate New button

            // Get or create an appropriate option letter
            let optionLetter: String
            if coverLetter.optionLetter.isEmpty {
                // No existing option letter, use the next available letter
                // This ensures we never reuse a letter, even if others are deleted
                optionLetter = coverLetter.getNextOptionLetter()
            } else {
                // Already has an option letter, preserve it
                optionLetter = coverLetter.optionLetter
            }

            // Create a descriptive suffix with model and resume background info
            var nameSuffix = formattedModel
            if coverLetter.includeResumeRefs {
                nameSuffix += " with Res BG"
            }
            // No "without Res BG" suffix is added when the checkbox is unchecked

            // Set the full name with the "Option X: description" format
            coverLetter.name = "Option \(optionLetter): \(nameSuffix)"
        }

        // Update UI state
        buttons.wrappedValue.runRequested = false
        
        // Convert conversation history to MessageParams for storage
        coverLetter.messageHistory = conversationHistory.map { appMessage in
            MessageParams(
                content: appMessage.contentParts.compactMap { 
                    if case let .text(content) = $0 { return content } 
                    return nil 
                }.joined(), 
                role: mapRole(appMessage.role)
            )
        }
    }
    
    /// Maps AppLLMMessage.Role to MessageParams.MessageRole
    /// - Parameter role: The AppLLMMessage.Role to map
    /// - Returns: The equivalent MessageParams.MessageRole
    private func mapRole(_ role: AppLLMMessage.Role) -> MessageParams.MessageRole {
        switch role {
        case .system: return .system
        case .user: return .user
        case .assistant: return .assistant
        }
    }

    @MainActor
    func coverChatRevise(
        res _: Resume?,
        jobAppStore: JobAppStore,
        chatProvider _: CoverChatProvider,
        buttons: Binding<CoverLetterButtons>,
        customFeedback: Binding<String>,
        isNewConversation: Bool = false
    ) {
        guard let app = jobAppStore.selectedApp else { return }
        guard let letter = app.selectedCover else { return }

        buttons.wrappedValue.runRequested = true

        if isNewConversation { // Should generally be false for revisions
            // Clear conversation context synchronously
            letter.clearConversationContext()
            conversationHistory = []
            Logger.debug("🧹 Cleared conversation context for new revision conversation")
        }

        // Use the same model that generated the original cover letter, fallback to preferred model
        let modelString = letter.generationModel ?? OpenAIModelFetcher.getPreferredModelString()
        var systemPrompt = CoverLetterPrompts.systemMessage.content
        
        // For Gemini models, explicitly state not to use JSON formatting
        if modelString.lowercased().contains("gemini") {
            systemPrompt += " Do not format your response as JSON. Return the cover letter text directly without any JSON wrapping or structure."
        }

        // Build user message based on editor prompt
        let userMessage: String
        if letter.editorPrompt == .custom {
            userMessage = """
            Upon reading your latest draft, \(Applicant().name) has provided the following feedback:

                \(customFeedback.wrappedValue)

            Please prepare a revised draft that improves upon the original while incorporating this feedback. 
            Your response should only include the plain full text of the revised letter draft without any 
            markdown formatting or additional explanations or reasoning.

            Current draft:
            \(letter.content)
            """
        } else {
            // Use the same consolidated prompt logic as batch generation
            guard let resume = app.selectedRes else {
                userMessage = "Error: No resume selected"
                return
            }
            
            userMessage = CoverLetterPrompts.generate(
                coverLetter: letter, 
                resume: resume, 
                mode: .rewrite,
                customFeedbackString: ""
            )
        }
        
        // Initialize or continue conversation
        if isNewConversation {
            _ = initializeConversation(systemPrompt: systemPrompt, userPrompt: userMessage)
        } else {
            _ = addUserMessage(userMessage)
        }

        Task {
            do {
                // Create client for the specific model
                let specificClient = AppLLMClientFactory.createClientForModel(
                    model: modelString, 
                    appState: AppState()
                )
                
                // Create query
                let query = AppLLMQuery(
                    messages: conversationHistory,
                    modelIdentifier: modelString,
                    temperature: 1.0
                )
                
                // Execute query with the specific client
                let response = try await specificClient.executeQuery(query)
                
                // Extract response content
                let responseText: String
                switch response {
                case .text(let text):
                    // Check if this is a JSON response from Gemini
                    responseText = extractCoverLetterContent(from: text)
                case .structured(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        responseText = extractCoverLetterContent(from: text)
                    } else {
                        responseText = ""
                    }
                }
                
                // Add response to conversation history
                _ = addAssistantMessage(responseText)
                
                // Process results to update the cover letter
                processResults(
                    newMessage: responseText,
                    coverLetter: letter,
                    buttons: buttons,
                    model: modelString,
                    isRevision: true // Revisions are always true here
                )
            } catch {
                buttons.wrappedValue.runRequested = false
                self.errorMessage = "Error: \(error.localizedDescription)"
            }
        }
    }
}
