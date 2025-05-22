// 
//  StructuredOutput.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 5/21/25.
//

import Foundation

/// Protocol for types that can be used as structured outputs from LLMs
protocol StructuredOutput: Codable {
    /// Optional method to validate the structured output data
    /// - Returns: True if valid, false if invalid
    func validate() -> Bool
    
    /// Convert the structured output to a JSON string (for debugging)
    /// - Returns: A JSON string or nil if conversion fails
    func toJSONString() -> String?
}

/// Default implementations for StructuredOutput protocol
extension StructuredOutput {
    /// Default implementation always returns true
    func validate() -> Bool {
        return true
    }
    
    /// Default implementation to convert to JSON string
    func toJSONString() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        do {
            let data = try encoder.encode(self)
            return String(data: data, encoding: .utf8)
        } catch {
            Logger.error("Failed to convert to JSON string: \(error.localizedDescription)")
            return nil
        }
    }
}
