//
//  AgentPrompts.swift
//  Sprung
//
//  System prompts for the git analysis agent.
//

import Foundation

enum GitAgentPrompts {

    /// Main system prompt for the git analysis agent
    static func systemPrompt(authorFilter: String? = nil) -> String {
        var prompt = PromptLibrary.gitAgentSystemPrompt

        // Add author filter context if provided
        if let author = authorFilter {
            let authorContext = PromptLibrary.substitute(
                template: PromptLibrary.gitAgentAuthorFilter,
                replacements: ["AUTHOR": author]
            )
            prompt += "\n\n" + authorContext
        }

        return prompt
    }
}
