//
//  CoverLetterPrompts.swift
//  Sprung
//
//
import Foundation
enum CoverLetterPrompts {
    enum EditorPrompts: String, Codable, CaseIterable {
        case improve = """
            Please carefully read the draft and identify at least three ways the content and quality of the writing can be improved. \
            Provide a new draft that incorporates the identified improvements.
            """
        case zinsser = """
            Carefully read the letter as a professional editor, specifically William Zinsser, incorporating the writing techniques and style he advocates in "On Writing Well." \
            Provide a new draft that incorporates Zinsser's edits to improve the quality of the writing.
            """
        case mimic = """
            The draft provided does not align closely with the tone, style, or word choice demonstrated in the sample letters. \
            Please rewrite the draft to convincingly match the voice, structure, and nuanced feel of the samples. \
            Prioritize consistency in tone and linguistic choices, ensuring the revised draft mirrors the fluidity and authenticity of the original style.
            """
        case custom = "Please provide a revised draft of the provided cover letter incorporating the following feedback: "
    }
}
/// Represents the human-readable revision operation applied to a cover letter
enum RevisionOperation: String, Codable {
    case improve = "Improve"
    case zinsser = "Zinsser"
    case mimic = "Mimic"
    case custom = "Custom"
}
extension CoverLetterPrompts.EditorPrompts {
    /// Maps an EditorPrompt case to its corresponding revision operation
    var operation: RevisionOperation {
        switch self {
        case .improve: return .improve
        case .zinsser: return .zinsser
        case .mimic: return .mimic
        case .custom: return .custom
        }
    }
}
