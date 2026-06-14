//
//  AgentPrompts.swift
//  Sprung
//
//  System prompt for the git repository-digest producer agent. The prompt
//  instructs the agent to explore the repository and emit a faithful, fully-cited
//  code dossier (RepositoryDigest analysis layers) — NOT a card list or summary.
//

import Foundation

enum GitAgentPrompts {

    /// Main system prompt for the repository-digest producer agent.
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
