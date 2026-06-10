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

    /// Get the Anthropic tool set for the current PHASE.
    ///
    /// PROMPT-CACHE INVARIANT: the tool list must be byte-identical on every
    /// request within a phase (tools render at position 0 of the prompt; any
    /// add/remove/reorder invalidates the entire cache). We therefore send the
    /// union of all subphase bundles for the current phase, sorted by tool name.
    /// Subphase gating is enforced app-side at dispatch time
    /// (StateCoordinator.checkToolAvailability), where an out-of-subphase call
    /// returns a structured "tool_not_available" result instead of executing.
    func getAnthropicTools() async -> [AnthropicTool] {
        let phase = await stateCoordinator.phase
        let phaseToolNames = (ToolBundlePolicy.allowedToolsByPhase[phase] ?? []).sorted()

        var anthropicTools: [AnthropicTool] = []
        for name in phaseToolNames {
            guard let tool = toolRegistry.tool(named: name) else { continue }
            let funcTool = Tool.FunctionTool(
                name: tool.name,
                parameters: tool.parameters,
                strict: tool.isStrict,
                description: tool.description
            )
            anthropicTools.append(convertToAnthropicTool(funcTool))
        }

        // Add server-side tools (fixed order, after sorted function tools)
        anthropicTools.append(.serverTool(.webSearch()))
        anthropicTools.append(.serverTool(.webFetch()))

        Logger.debug(
            "🔧 Anthropic tools: phase=\(phase.rawValue), sending \(anthropicTools.count) tools (incl. web_search, web_fetch)",
            category: .ai
        )

        return anthropicTools
    }

    // MARK: - Conversion

    /// Convert a function tool to Anthropic format
    func convertToAnthropicTool(_ funcTool: Tool.FunctionTool) -> AnthropicTool {
        AnthropicSchemaConverter.convertToAnthropicTool(funcTool)
    }

    /// Convert JSONSchema to dictionary representation
    func convertJSONSchemaToDictionary(_ schema: JSONSchema) -> [String: Any] {
        AnthropicSchemaConverter.convertJSONSchemaToDictionary(schema)
    }

    /// Convert JSONSchemaType to its string representation
    func jsonSchemaTypeToString(_ type: JSONSchemaType) -> String {
        AnthropicSchemaConverter.jsonSchemaTypeToString(type)
    }
}
