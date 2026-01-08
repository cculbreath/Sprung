//
//  AgentToolProtocol.swift
//  Sprung
//
//  Protocol for tools used by the git analysis agent.
//

import Foundation

/// Protocol for all agent tools used by the git analysis agent
protocol AgentTool {
    /// Tool name (used in function calling)
    static var name: String { get }
    /// Tool description for LLM
    static var description: String { get }
    /// JSON Schema for parameters
    static var parametersSchema: [String: Any] { get }
}
