// PhysCloudResume/Shared/Extensions/String+Extensions.swift

import Foundation

extension String {
    /// Checks if the string represents a Gemini model name
    func isGeminiModel() -> Bool {
        let lowercased = self.lowercased()
        return lowercased.contains("gemini") || 
               lowercased.starts(with: "google.") || 
               lowercased.contains("gemma")
    }
}
