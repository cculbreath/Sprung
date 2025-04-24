//
//  BestCoverLetterResponse.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/24/25.
//

import Foundation

/// Response from the AI best cover letter recommendation analysis
struct BestCoverLetterResponse: Codable {
    /// UUID of the selected best cover letter
    let bestLetterUuid: String
    
    /// Analysis of the strengths and voice of the selected cover letter
    let strengthAndVoiceAnalysis: String
    
    /// Explanation of why this cover letter was selected as the best
    let verdict: String
    
    /// Additional improvement suggestions (optional)
    let improvementSuggestions: String?
    
    /// Raw score assigned to the letter (optional)
    let score: Double?
    
    /// Creates a new best cover letter response
    /// - Parameters:
    ///   - bestLetterUuid: The UUID of the selected letter
    ///   - strengthAndVoiceAnalysis: Analysis of the letter's strengths and voice
    ///   - verdict: Explanation of why this letter was selected
    ///   - improvementSuggestions: Optional suggestions for improvement
    ///   - score: Optional numerical score
    init(
        bestLetterUuid: String,
        strengthAndVoiceAnalysis: String,
        verdict: String,
        improvementSuggestions: String? = nil,
        score: Double? = nil
    ) {
        self.bestLetterUuid = bestLetterUuid
        self.strengthAndVoiceAnalysis = strengthAndVoiceAnalysis
        self.verdict = verdict
        self.improvementSuggestions = improvementSuggestions
        self.score = score
    }
}