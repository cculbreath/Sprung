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

        // Add server-side tools
        anthropicTools.append(.serverTool(.webSearch()))
        anthropicTools.append(.serverTool(.webFetch()))

        Logger.debug(
            "🔧 Anthropic tool bundling: subphase=\(subphase.rawValue), sending \(anthropicTools.count) tools (incl. web_search, web_fetch)",
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
