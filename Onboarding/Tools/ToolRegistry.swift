//
//  ToolRegistry.swift
//  Sprung
//
//  Dynamic registry for onboarding interview tools.
//

import Foundation
import SwiftOpenAI
import SwiftyJSON

final class ToolRegistry {
    private var tools: [String: InterviewTool] = [:]
    private let queue = DispatchQueue(label: "com.sprung.onboarding.toolRegistry", attributes: .concurrent)

    func register(_ tool: InterviewTool) {
        queue.async(flags: .barrier) {
            self.tools[tool.name] = tool
        }
    }

    func tool(named name: String) -> InterviewTool? {
        queue.sync {
            tools[name]
        }
    }

    func allTools() -> [InterviewTool] {
        queue.sync {
            Array(tools.values)
        }
    }

    func toolSchemas() -> [Tool] {
        queue.sync {
            tools.values.map { tool in
                .function(
                    .init(
                        name: tool.name,
                        description: tool.description,
                        parameters: tool.parameters
                    )
                )
            }
        }
    }
}

