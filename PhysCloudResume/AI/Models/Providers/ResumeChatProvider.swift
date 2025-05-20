//
//  ResumeChatProvider.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/1/24.
//

import Foundation
import PDFKit
import AppKit
import SwiftData
import SwiftUI

/// Helper for handling resume chat functionality

@Observable
final class ResumeChatProvider {
    // The OpenAI client that will be used for API calls
    private let openAIClient: OpenAIClientProtocol

    private var streamTask: Task<Void, Never>?
    var message: String = ""
    var messages: [String] = []
    // Generic message format for the abstraction layer
    var genericMessages: [ChatMessage] = []
    var errorMessage: String = ""
    var lastRevNodeArray: [ProposedRevisionNode] = []
    
    // Track the last model used to know when to switch clients
    var lastModelUsed: String = ""

    // MARK: - Initializers

    /// Initialize with the new abstraction layer client
    /// - Parameter client: An OpenAI client conforming to OpenAIClientProtocol
    init(client: OpenAIClientProtocol) {
        openAIClient = client
    }

    // MARK: - Public Methods

    // Actor to safely coordinate continuations and prevent multiple resumes
    private actor ContinuationCoordinator {
        private var hasResumed = false

        func resumeWithValue<T, E: Error>(_ value: T, continuation: CheckedContinuation<T, E>) {
            guard !hasResumed else { return }
            hasResumed = true
            continuation.resume(returning: value)
        }

        func resumeWithError<T, E: Error>(_ error: E, continuation: CheckedContinuation<T, E>) {
            guard !hasResumed else { return }
            hasResumed = true
            continuation.resume(throwing: error)
        }
    }

    /// Send a chat completion request to the OpenAI API
    /// - Parameter messages: The message history to use for context
    /// - Parameter resume: Optional resume to update with response ID for server-side conversation state
    /// - Returns: void - results are stored in the message property
    func startChat(messages: [ChatMessage],
                   resume: Resume? = nil,
                   continueConversation: Bool = false) async throws
    {
        // Always use ChatCompletions API now
        // Clear previous error message before starting
        errorMessage = ""

        // Store for reference
        genericMessages = messages

        // Get model as string
        let modelString = OpenAIModelFetcher.getPreferredModelString()

        // Use our abstraction layer with a timeout
        let timeoutError = NSError(
            domain: "ResumeChatProviderError",
            code: -1001,
            userInfo: [NSLocalizedDescriptionKey: "API request timed out. Please try again."]
        )

        // Create a coordinator for safe continuation resumption
        let coordinator = ContinuationCoordinator()

        do {
            // Use the new structured output method from the abstraction layer
            let response = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RevisionsContainer, Error>) in
                let apiTask = Task {
                    do {
                        // Use the abstraction layer's structured output method
                        let result = try await openAIClient.sendChatCompletionWithStructuredOutput(
                            messages: messages,
                            model: modelString,
                            temperature: nil,
                            structuredOutputType: RevisionsContainer.self
                        )
                        await coordinator.resumeWithValue(result, continuation: continuation)
                    } catch {
                        await coordinator.resumeWithError(error, continuation: continuation)
                    }
                }

                // Set up a timeout task
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000_000) // 500s timeout
                    if !apiTask.isCancelled {
                        apiTask.cancel()
                        await coordinator.resumeWithError(timeoutError, continuation: continuation)
                    }
                }
            }

            // Convert structured response to JSON for compatibility with existing code
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(response)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{\"revArray\": []}"

            // Store the JSON string in messages array
            self.messages = [jsonString]

            if self.messages.isEmpty {
                throw NSError(
                    domain: "ResumeChatProviderError",
                    code: 1002,
                    userInfo: [NSLocalizedDescriptionKey: "No response content received from AI service."]
                )
            }

            // Get the revision nodes directly from the structured response
            lastRevNodeArray = response.revArray

            // Update generic messages for history
            genericMessages.append(ChatMessage(role: .assistant, content: jsonString))

        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: - Conversational Methods (ChatCompletions API)
    
    /// Starts a new conversation for resume analysis with ChatCompletions API
    /// - Parameters:
    ///   - resume: The resume to analyze
    ///   - customInstructions: Optional custom instructions for the analysis
    ///   - onProgress: Progress callback for streaming responses
    ///   - onComplete: Completion callback with result
    @MainActor
    func startNewResumeConversation(
        resume: Resume,
        customInstructions: String = "",
        onProgress: @escaping (String) -> Void = { _ in },
        onComplete: @escaping (Result<String, Error>) -> Void = { _ in }
    ) {
        // Create a query to get the system prompt and context
        let query = ResumeApiQuery(resume: resume)
        
        // Build system prompt from the query
        var systemPrompt = query.genericSystemMessage.content
        if !customInstructions.isEmpty {
            systemPrompt += "\n\nAdditional Instructions: \(customInstructions)"
        }
        
        let userMessage = "Please analyze this resume and provide detailed feedback for improvement."
        
        LLMRequestService.shared.sendResumeConversationRequest(
            resume: resume,
            userMessage: userMessage,
            systemPrompt: systemPrompt,
            isNewConversation: true,
            onProgress: onProgress,
            onComplete: onComplete
        )
    }
    
    /// Continues an existing conversation for the resume
    /// - Parameters:
    ///   - resume: The resume being discussed
    ///   - userMessage: The user's message to continue the conversation
    ///   - onProgress: Progress callback for streaming responses
    ///   - onComplete: Completion callback with result
    @MainActor
    func continueResumeConversation(
        resume: Resume,
        userMessage: String,
        onProgress: @escaping (String) -> Void = { _ in },
        onComplete: @escaping (Result<String, Error>) -> Void = { _ in }
    ) {
        LLMRequestService.shared.sendResumeConversationRequest(
            resume: resume,
            userMessage: userMessage,
            systemPrompt: nil, // System prompt already in context
            isNewConversation: false,
            onProgress: onProgress,
            onComplete: onComplete
        )
    }

    /// Helper method to save message content to debug file
    private func saveMessageToDebugFile(_ content: String, fileName: String) {
        // Check if debug prompt saving is enabled
        let saveDebugPrompts = UserDefaults.standard.bool(forKey: "saveDebugPrompts")
        
        // Only save if debug is enabled
        if saveDebugPrompts {
            let fileManager = FileManager.default
            let homeDirectoryURL = fileManager.homeDirectoryForCurrentUser
            let downloadsURL = homeDirectoryURL.appendingPathComponent("Downloads")
            let fileURL = downloadsURL.appendingPathComponent(fileName)
            
            do {
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
                Logger.debug("Debug message content saved to: \(fileURL.path)")
            } catch {
                Logger.debug("Error saving debug message: \(error.localizedDescription)")
            }
        } else {
            // Log that we would have saved a debug file, but it's disabled
            Logger.debug("Debug message NOT saved (saveDebugPrompts disabled)")
        }
    }
}
