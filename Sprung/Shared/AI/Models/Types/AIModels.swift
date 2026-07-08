//
//  AIModels.swift
//  Sprung
//
//
import Foundation
import PDFKit
import AppKit
import SwiftUI
/// Utilities for AI model management and display
struct AIModels {
    /// Returns a friendly, human-readable name for a model
    /// - Parameter modelName: The raw model name
    /// - Returns: A simplified, user-friendly model name
    static func friendlyModelName(for modelName: String) -> String? {
        let components = modelName.split(separator: "-")
        // Handle different model naming patterns
        // Handle o1 models first (before general GPT handling)
        if modelName.lowercased().contains("gpt") {
            if components.count >= 2 {
                // Extract main version (e.g., "GPT-4" from "gpt-4-1106-preview")
                if components[1].allSatisfy({ $0.isNumber || $0 == "." }) { // Check if it's a version number like 4 or 3.5
                    return "GPT-\(components[1])"
                }
                // Handle mini variants
                if components.contains("mini") {
                    return "GPT-\(components[1]) Mini"
                }
            }
            // Special case for GPT-4o models
            if modelName.lowercased().contains("gpt-4o") {
                return "GPT-4o"
            }
        } else if modelName.lowercased().contains("claude") {
            // Handle Claude models
            if components.count >= 2 {
                if components[1] == "3" && components.count >= 3 {
                    // Handle "claude-3-opus-20240229" -> "Claude 3 Opus"
                    return "Claude 3 \(components[2].capitalized)"
                } else if components[1] == "3.5" && components.count >= 3 {
                    // Handle "claude-3.5-sonnet-20240620" -> "Claude 3.5 Sonnet"
                    return "Claude 3.5 \(components[2].capitalized)"
                } else {
                    // Handle other Claude versions
                    return "Claude \(components[1])"
                }
            }
        } else if modelName.lowercased().contains("grok") {
            // Handle Grok models
            if components.count >= 2 {
                var result = "Grok \(components[1])"
                // Check for mini variant
                if components.contains("mini") {
                    result += " Mini"
                    // Check for fast variant
                    if components.contains("fast") {
                        result += " Fast"
                    }
                }
                return result
            }
            return "Grok"
        } else if modelName.lowercased().contains("gemini") {
            // Handle Gemini models
            if modelName.contains("2.5") && modelName.contains("flash") {
                return "Gemini 2.5 Flash"
            } else if modelName.contains("2.0") && modelName.contains("flash") {
                return "Gemini 2.0 Flash"
            } else if components.count >= 2 {
                if components.contains("pro") {
                    return "Gemini Pro"
                }
                if components.contains("flash") {
                    return "Gemini Flash"
                }
                return "Gemini \(components[1].capitalized)"
            }
            return "Gemini"
        }
        // Default fallback: Use the first part of the model name, capitalized
        return modelName.split(separator: "-").map { $0.capitalized }
            .joined(separator: " ")
    }
    }
