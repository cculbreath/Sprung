//
//  APIResponses.swift
//  PhysCloudResume
//
//  Created by Team on 5/13/25.
//

import Foundation
import PDFKit
import AppKit
import SwiftUI

// MARK: - Local Protocol Definitions
// These protocols replace OpenAI dependencies for our abstraction layer

// This line is commented out since we now have a better implementation in StructuredOutput.swift
// protocol StructuredOutput: Codable {}

/// Response from an OpenAI Responses API request
struct ResponsesAPIResponse: Codable, Equatable {
    /// The unique ID of the response (used for continuation)
    let id: String
    /// The content of the response
    let content: String
    /// The model used for the response
    let model: String
}

/// Voting scheme for multi-model selection
enum VotingScheme: String, CaseIterable {
    case firstPastThePost = "First Past The Post"
    case scoreVoting = "Score Voting (20 points)"
    
    var description: String {
        switch self {
        case .firstPastThePost:
            return "Each model votes for one favorite letter"
        case .scoreVoting:
            return "Each model allocates 20 points among all letters"
        }
    }
}

/// Score allocation for a single cover letter in score voting
struct CoverLetterScore: Codable {
    let letterUuid: String
    let score: Int
    let reasoning: String
}

/// Response schema for best cover letter selection
struct BestCoverLetterResponse: Codable, StructuredOutput {
    let strengthAndVoiceAnalysis: String
    let bestLetterUuid: String
    let verdict: String
    
    // Optional: Used only for score voting
    let scoreAllocations: [CoverLetterScore]?
    
    // Implement validate for StructuredOutput
    func validate() -> Bool {
        // Check if we have non-empty values
        let baseValidation = !strengthAndVoiceAnalysis.isEmpty &&
               !bestLetterUuid.isEmpty &&
               !verdict.isEmpty
        
        // If scoreAllocations exist, validate them
        if let scores = scoreAllocations {
            let totalScore = scores.reduce(0) { $0 + $1.score }
            // Score voting should allocate exactly 20 points
            return baseValidation && totalScore == 20 && scores.allSatisfy { $0.score >= 0 }
        }
        
        return baseValidation
    }
    
    // Backward compatibility initializer for FPTP voting
    init(strengthAndVoiceAnalysis: String, bestLetterUuid: String, verdict: String) {
        self.strengthAndVoiceAnalysis = strengthAndVoiceAnalysis
        self.bestLetterUuid = bestLetterUuid
        self.verdict = verdict
        self.scoreAllocations = nil
    }
    
    // Full initializer including score allocations
    init(strengthAndVoiceAnalysis: String, bestLetterUuid: String, verdict: String, scoreAllocations: [CoverLetterScore]?) {
        self.strengthAndVoiceAnalysis = strengthAndVoiceAnalysis
        self.bestLetterUuid = bestLetterUuid
        self.verdict = verdict
        self.scoreAllocations = scoreAllocations
    }
}


// MARK: - Chat Message Types

/// Represents a chat message in a conversation
struct ChatMessage: Codable, Equatable {
    /// The role of the message sender (system, user, assistant)
    let role: ChatRole
    /// The content of the message
    let content: String
    /// Optional base64-encoded image data for vision models
    let imageData: String?

    /// Creates a new chat message with text only
    /// - Parameters:
    ///   - role: The role of the message sender
    ///   - content: The content of the message
    init(role: ChatRole, content: String) {
        self.role = role
        self.content = content
        self.imageData = nil
    }
    
    /// Creates a new chat message with text and image
    /// - Parameters:
    ///   - role: The role of the message sender
    ///   - content: The content of the message
    ///   - imageData: Base64-encoded image data
    init(role: ChatRole, content: String, imageData: String) {
        self.role = role
        self.content = content
        self.imageData = imageData
    }

    enum ChatRole: String, Codable {
        case system
        case user
        case assistant
    }
}
