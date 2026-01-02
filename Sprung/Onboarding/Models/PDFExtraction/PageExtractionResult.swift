//
//  PageExtractionResult.swift
//  Sprung
//
//  Structured result from LLM vision page extraction.
//  Includes graphics analysis for resume skill extraction.
//

import Foundation

/// Graphics information extracted from a page, with skills assessment for resume building
struct PageGraphicsInfo: Codable {
    /// Number of graphics/figures on the page
    let numberOfGraphics: Int

    /// Description of what each graphic shows (content/data/information conveyed)
    let graphicsContent: [String]

    /// Skills assessment for each graphic - what skills are demonstrated by creating it
    /// Examples: "Advanced Excel data visualization", "Publication-quality matplotlib figures",
    /// "Professional UML architecture diagrams", "Stock imagery (no skill demonstrated)"
    let qualitativeAssessment: [String]

    /// JSON Schema for Gemini structured output
    static var jsonSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "number_of_graphics": ["type": "integer"],
                "graphics_content": [
                    "type": "array",
                    "items": ["type": "string"]
                ],
                "qualitative_assessment": [
                    "type": "array",
                    "items": ["type": "string"]
                ]
            ],
            "required": ["number_of_graphics", "graphics_content", "qualitative_assessment"]
        ]
    }
}

/// Result from extracting a single page with LLM vision
struct PageExtractionResult: Codable {
    /// Extracted text content, preserving structure
    let text: String

    /// Information about graphics/figures on the page
    let graphics: PageGraphicsInfo

    /// JSON Schema for Gemini structured output
    static var jsonSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "text": ["type": "string"],
                "graphics": PageGraphicsInfo.jsonSchema
            ],
            "required": ["text", "graphics"]
        ]
    }
}
