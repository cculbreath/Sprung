//
//  AITypes.swift
//  Sprung
//
//
import Foundation
// This file defines types that are used in the AI protocol interfaces
// These types abstract away the implementation details of specific AI libraries
// MARK: - Clarifying Questions Types
/// Structure for the LLM's clarifying questions request
struct ClarifyingQuestionsRequest: Codable {
    let questions: [ClarifyingQuestion]
    let proceedWithRevisions: Bool  // True if LLM wants to skip questions
}
/// Individual clarifying question
struct ClarifyingQuestion: Codable, Identifiable, Equatable {
    let id: String
    let question: String
    let context: String? // Optional context about why this question is being asked
}
/// Individual question answer
struct QuestionAnswer: Codable {
    let questionId: String
    let answer: String?  // nil if user declined to answer
}
