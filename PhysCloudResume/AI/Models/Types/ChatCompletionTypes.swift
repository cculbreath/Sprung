//
//  ChatCompletionTypes.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 5/20/25.
//

import Foundation
import SwiftOpenAI

/// This file provides typealiases for types from SwiftOpenAI
/// This approach allows us to:
/// 1. Keep the protocol decoupled from the implementation
/// 2. Maintain compatibility with existing code
/// 3. Easily swap implementations in the future

/// Namespace for chat completion parameter types
/// Acts as a wrapper around SwiftOpenAI types to provide abstraction
public enum ChatCompletionTypes {
    /// Typealias for SwiftOpenAI's response format
    public typealias ResponseFormat = SwiftOpenAI.ResponseFormat
    
    /// Typealias for SwiftOpenAI's JSONSchema
    public typealias JSONSchema = SwiftOpenAI.JSONSchema
    
    /// Typealias for SwiftOpenAI's JSONSchemaResponseFormat 
    public typealias JSONSchemaResponseFormat = SwiftOpenAI.JSONSchemaResponseFormat
    
    /// Typealias for SwiftOpenAI's Message
    public typealias Message = SwiftOpenAI.ChatCompletionParameters.Message
}
