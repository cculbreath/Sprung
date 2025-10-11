//
//  ResumeTemplateProcessor.swift
//  PhysCloudResume
//
//  Created by Assistant on 12/20/24.
//

import Foundation

/// Shared template processing logic for resume generation
@MainActor
class ResumeTemplateProcessor {
    
    /// Create template context from Resume data
    static func createTemplateContext(from resume: Resume) throws -> [String: Any] {
        do {
            return try ResumeTemplateDataBuilder.buildContext(from: resume)
        } catch {
            throw NSError(
                domain: "ResumeTemplateProcessor",
                code: 1001,
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed to build template context from resume: \(error)"
                ]
            )
        }
    }
    
}
