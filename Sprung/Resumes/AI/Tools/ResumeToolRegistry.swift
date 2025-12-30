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
    /// Callback to present UI and await user response
    let presentUI: (@MainActor (ResumeToolUIRequest) async -> ResumeToolUIResponse)?
}

/// Request for UI presentation from a tool
enum ResumeToolUIRequest {
    case skillExperiencePicker(skills: [SkillQuery])
}

/// Response from UI after user interaction
enum ResumeToolUIResponse {
    case skillExperienceResults([SkillExperienceResult])
    case cancelled
}

/// Skill query parameter from LLM
struct SkillQuery: Codable, Equatable {
    let keyword: String
}

/// User's response about skill experience
struct SkillExperienceResult: Codable, Equatable {
    let keyword: String
    let level: ExperienceLevel
    let comment: String?
}

/// Experience level options
enum ExperienceLevel: String, Codable, CaseIterable, Equatable {
    case none = "none"
    case novice = "novice"
    case competent = "competent"
    case advanced = "advanced"
    case expert = "expert"

    var displayName: String {
        switch self {
        case .none: return "No Experience"
        case .novice: return "Novice"
        case .competent: return "Competent"
        case .advanced: return "Advanced"
        case .expert: return "Expert"
        }
    }

    var shortDescription: String {
        switch self {
        case .none: return "I have no experience with this"
        case .novice: return "Basic understanding, limited practical use"
        case .competent: return "Can work independently on typical tasks"
        case .advanced: return "Deep expertise, can mentor others"
        case .expert: return "Industry-leading knowledge"
        }
    }
}

// MARK: - Tool Result

/// Result of tool execution
enum ResumeToolResult {
    /// Tool completed immediately with a result
    case immediate(JSON)
    /// Tool requires user interaction - UI will be presented
    case pendingUserAction(ResumeToolUIRequest)
    /// Tool encountered an error
    case error(String)
}

// MARK: - Tool Registry

/// Registry for managing resume customization tools.
/// Builds tool definitions for OpenRouter and routes tool calls to implementations.
@MainActor
class ResumeToolRegistry {
    private var tools: [any ResumeTool] = []

    init() {
        // Register default tools
        registerTool(QueryUserExperienceLevelTool())
    }

    /// Register a tool with the registry
    func registerTool(_ tool: any ResumeTool) {
        tools.append(tool)
    }

    /// Build ChatCompletionParameters.Tool array for OpenRouter
    func buildChatTools() -> [ChatCompletionParameters.Tool] {
        tools.map { tool in
            let schema = Self.buildJSONSchema(from: type(of: tool).parametersSchema)
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

    // MARK: - JSON Schema Building

    /// Build JSONSchema from dictionary representation
    static func buildJSONSchema(from dict: [String: Any]) -> JSONSchema {
        return buildJSONSchemaRecursive(from: dict)
    }

    private static func buildJSONSchemaRecursive(from dict: [String: Any]) -> JSONSchema {
        let typeStr = dict["type"] as? String ?? "object"
        let desc = dict["description"] as? String
        let enumValues = dict["enum"] as? [String]

        let schemaType: JSONSchemaType
        switch typeStr {
        case "string": schemaType = .string
        case "integer": schemaType = .integer
        case "number": schemaType = .number
        case "boolean": schemaType = .boolean
        case "array": schemaType = .array
        case "object": schemaType = .object
        default: schemaType = .string
        }

        // Handle properties for objects
        var properties: [String: JSONSchema]? = nil
        if let propsDict = dict["properties"] as? [String: [String: Any]] {
            var propSchemas: [String: JSONSchema] = [:]
            for (key, propSpec) in propsDict {
                propSchemas[key] = buildJSONSchemaRecursive(from: propSpec)
            }
            properties = propSchemas
        }

        // Handle items for arrays
        var items: JSONSchema? = nil
        if schemaType == .array, let itemsDict = dict["items"] as? [String: Any] {
            items = buildJSONSchemaRecursive(from: itemsDict)
        }

        let required = dict["required"] as? [String]
        let additionalProps = dict["additionalProperties"] as? Bool ?? false

        return JSONSchema(
            type: schemaType,
            description: desc,
            properties: properties,
            items: items,
            required: required,
            additionalProperties: additionalProps,
            enum: enumValues
        )
    }
}
