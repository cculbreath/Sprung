//
//  AnthropicToolConverter.swift
//  Sprung
//
//  Converts tool schemas to Anthropic format.
//  Extracted from AnthropicRequestBuilder for single responsibility.
//

import Foundation
import SwiftOpenAI

/// Converts tool schemas to Anthropic format
struct AnthropicToolConverter {
    private let toolRegistry: ToolRegistry
    private let stateCoordinator: StateCoordinator

    init(toolRegistry: ToolRegistry, stateCoordinator: StateCoordinator) {
        self.toolRegistry = toolRegistry
        self.stateCoordinator = stateCoordinator
    }

    // MARK: - Tool Retrieval

    /// Get Anthropic tools based on current state and subphase
    func getAnthropicTools() async -> [AnthropicTool] {
        // Get current state for subphase inference
        let phase = await stateCoordinator.phase
        let toolPaneCard = await stateCoordinator.getCurrentToolPaneCard()
        let objectives = await stateCoordinator.getObjectiveStatusMap()

        // Get Phase 4 UI context for title set curation gating
        let phase4Context = await stateCoordinator.getPhase4UIContext()

        // Infer current subphase from objectives + UI state
        let subphase = ToolBundlePolicy.inferSubphase(
            phase: phase,
            toolPaneCard: toolPaneCard,
            objectives: objectives,
            phase4Context: phase4Context
        )

        // Select tools based on subphase
        let bundledNames = ToolBundlePolicy.selectBundleForSubphase(subphase)

        if bundledNames.isEmpty {
            Logger.debug("🔧 Anthropic tool bundling: subphase=\(subphase.rawValue), sending 0 tools", category: .ai)
            return []
        }

        // Get tool schemas and convert to Anthropic format
        let openAITools = await toolRegistry.toolSchemas(filteredBy: bundledNames)
        var anthropicTools: [AnthropicTool] = openAITools.compactMap { tool -> AnthropicTool? in
            guard case .function(let funcTool) = tool else { return nil }
            return convertToAnthropicTool(funcTool)
        }

        // Add web_search server-side tool
        anthropicTools.append(.serverTool(.webSearch()))

        Logger.debug(
            "🔧 Anthropic tool bundling: subphase=\(subphase.rawValue), sending \(anthropicTools.count) tools (incl. web_search)",
            category: .ai
        )

        return anthropicTools
    }

    // MARK: - Conversion

    /// Convert a function tool to Anthropic format
    func convertToAnthropicTool(_ funcTool: Tool.FunctionTool) -> AnthropicTool {
        // Convert JSONSchema to dictionary for Anthropic's input_schema
        let inputSchema = convertJSONSchemaToDictionary(funcTool.parameters)

        return .function(AnthropicFunctionTool(
            name: funcTool.name,
            description: funcTool.description,
            inputSchema: inputSchema
        ))
    }

    /// Convert JSONSchema to dictionary representation
    func convertJSONSchemaToDictionary(_ schema: JSONSchema) -> [String: Any] {
        var result: [String: Any] = [:]

        // Type - convert JSONSchemaType to string
        if let schemaType = schema.type {
            result["type"] = jsonSchemaTypeToString(schemaType)
        }

        // Properties
        if let properties = schema.properties {
            var propsDict: [String: Any] = [:]
            for (key, propSchema) in properties {
                propsDict[key] = convertJSONSchemaToDictionary(propSchema)
            }
            result["properties"] = propsDict
        }

        // Required
        if let required = schema.required {
            result["required"] = required
        }

        // Description
        if let description = schema.description {
            result["description"] = description
        }

        // Items (for arrays)
        if let items = schema.items {
            result["items"] = convertJSONSchemaToDictionary(items)
        }

        // Enum (JSONSchema uses backtick `enum`)
        if let enumValues = schema.`enum` {
            result["enum"] = enumValues
        }

        // Additional properties (simple Bool? in JSONSchema)
        if let additionalProps = schema.additionalProperties {
            result["additionalProperties"] = additionalProps
        }

        return result
    }

    /// Convert JSONSchemaType to its string representation
    func jsonSchemaTypeToString(_ type: JSONSchemaType) -> String {
        switch type {
        case .string: return "string"
        case .number: return "number"
        case .integer: return "integer"
        case .boolean: return "boolean"
        case .object: return "object"
        case .array: return "array"
        case .null: return "null"
        case .union(let types):
            // For union types, return the first non-null type
            // (Anthropic doesn't support union types directly)
            if let firstType = types.first(where: { $0 != .null }) {
                return jsonSchemaTypeToString(firstType)
            }
            return "string"
        }
    }
}
