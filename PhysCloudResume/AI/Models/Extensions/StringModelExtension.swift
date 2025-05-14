//
//  StringModelExtension.swift
//  PhysCloudResume
//
//  Created by Team on 5/13/25.
//

import Foundation
import PDFKit
import AppKit
import SwiftUI

extension String {
    
    /// Checks if the model is one of OpenAI's reasoning models
    func isReasoningModel() -> Bool {
        return self.lowercased().contains("o3") ||
               self.lowercased().contains("o4") || self.lowercased().contains("o1")
    }
    
    /// Checks if the model supports image inputs
    func supportsImages() -> Bool {
        let lower = self.lowercased()
        // Assume any Gemini model supports images
        if lower.contains("gemini") {
            return true
        }
        // For OpenAI vision models
        let openAIVisionModelsSubstrings = [
            "gpt-4o", "gpt-4-turbo", "gpt-4-vision",
            "gpt-4.1", "gpt-image", "o4", "cua", "o3", "o1", "gpt-4.5"
        ]
        return openAIVisionModelsSubstrings.contains { lower.contains($0) }
    }
}
