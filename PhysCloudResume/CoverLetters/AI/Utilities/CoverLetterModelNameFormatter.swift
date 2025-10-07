//
//  CoverLetterModelNameFormatter.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 6/11/25.
//

import Foundation

class CoverLetterModelNameFormatter {
    
    func formatModelNames(_ modelIds: [String]) -> String {
        let displayNames = modelIds.map { modelId in
            // Clean up model names for better display
            return modelId
                .replacingOccurrences(of: "openai/", with: "")
                .replacingOccurrences(of: "anthropic/", with: "")
                .replacingOccurrences(of: "meta-llama/", with: "")
                .replacingOccurrences(of: "google/", with: "")
                .replacingOccurrences(of: "x-ai/", with: "")
                .replacingOccurrences(of: "deepseek/", with: "")
        }
        
        if displayNames.count == 1 {
            return displayNames[0]
        } else if displayNames.count == 2 {
            return "\(displayNames[0]) and \(displayNames[1])"
        } else {
            let allButLast = displayNames.dropLast().joined(separator: ", ")
            if let last = displayNames.last {
                return "\(allButLast), and \(last)"
            } else {
                return allButLast
            }
        }
    }
}
