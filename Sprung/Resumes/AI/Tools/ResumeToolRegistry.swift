//
//  ResumeToolRegistry.swift
//  Sprung
//
//  Tool registry for resume customization workflow.
//  Provides extensible tool support via OpenRouter's native tool calling.
//
import Foundation
import SwiftyJSON
import SwiftOpenAI

// MARK: - Tool Protocol

/// Protocol for tools available during resume customization.
/// Similar to `InterviewTool` but designed for the resume workflow context.
protocol ResumeTool {
    static var name: String { get }
    static var description: String { get }
    static var parametersSchema: [String: Any] { get }

    /// Execute the tool with the given parameters.
    /// - Parameters:
    ///   - params: The JSON parameters passed by the LLM
    ///   - context: Context about the current resume and workflow
    /// - Returns: The result of tool execution
    func execute(_ params: JSON, context: ResumeToolContext) async throws -> ResumeToolResult
}

// MARK: - Tool Context

/// Context provided to tools during execution.
struct ResumeToolContext {
    /// The resume being customized
    let resume: Resume
    /// The job application context (if available)
    let jobApp: JobApp?
}

// MARK: - Tool Result

/// Result of tool execution
enum ResumeToolResult {
    /// Tool completed immediately with a result
    case immediate(JSON)
    /// Tool encountered an error
    case error(String)
}

// MARK: - Tool Registry

/// Registry for managing resume customization tools.
/// Builds tool definitions for OpenRouter and routes tool calls to implementations.
@MainActor
class ResumeToolRegistry {
    private var tools: [any ResumeTool] = []

    init(knowledgeCardStore: KnowledgeCardStore? = nil) {
        if let store = knowledgeCardStore {
            registerTool(ReadKnowledgeCardsTool(knowledgeCardStore: store))
        }
    }

    /// Register a tool with the registry
    func registerTool(_ tool: any ResumeTool) {
        tools.append(tool)
    }

    /// Build ChatCompletionParameters.Tool array for OpenRouter
    func buildChatTools() -> [ChatCompletionParameters.Tool] {
        tools.map { tool in
            // Tool schemas are static compile-time dictionaries; crash correctly signals malformed schema
            let schema = try! JSONSchema.from(dictionary: type(of: tool).parametersSchema)
            let function = ChatCompletionParameters.ChatFunction(
                name: type(of: tool).name,
                strict: false,
                description: type(of: tool).description,
                parameters: schema
            )
            return ChatCompletionParameters.Tool(function: function)
        }
    }

    /// Execute a tool by name
    /// - Parameters:
    ///   - name: The tool name from the LLM's tool call
    ///   - arguments: JSON string of arguments
    ///   - context: The execution context
    /// - Returns: The tool result
    func executeTool(
        name: String,
        arguments: String,
        context: ResumeToolContext
    ) async throws -> ResumeToolResult {
        guard let tool = tools.first(where: { type(of: $0).name == name }) else {
            return .error("Unknown tool: \(name)")
        }

        let params: JSON
        if let data = arguments.data(using: .utf8) {
            params = try JSON(data: data)
        } else {
            return .error("Failed to parse tool arguments as JSON")
        }

        return try await tool.execute(params, context: context)
    }

    /// Get tool names for logging/debugging
    var toolNames: [String] {
        tools.map { type(of: $0).name }
    }
}
