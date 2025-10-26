//
//  ToolExecutor.swift
//  Sprung
//
//  Executes onboarding interview tools and manages continuations.
//

import Foundation
import SwiftOpenAI
import SwiftyJSON

actor ToolExecutor {
    private let registry: ToolRegistry
    private var continuations: [UUID: ContinuationToken] = [:]

    init(registry: ToolRegistry) {
        self.registry = registry
    }

    func availableToolSchemas(allowedNames: Set<String>? = nil) -> [Tool] {
        registry.toolSchemas(filteredBy: allowedNames)
    }

    func handleToolCall(_ call: ToolCall) async throws -> ToolResult {
        guard let tool = registry.tool(named: call.name) else {
            throw ToolError.invalidParameters("Unknown tool: \(call.name)")
        }

        let result = try await tool.execute(call.arguments)
        if case let .waiting(_, token) = result {
            continuations[token.id] = token
        }
        return result
    }

    func resumeContinuation(id: UUID, with input: JSON) async throws -> ToolResult {
        guard let token = continuations.removeValue(forKey: id) else {
            throw ToolError.invalidParameters("Unknown continuation: \(id)")
        }
        return await token.resumeHandler(input)
    }
}
