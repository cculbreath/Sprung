//
//  JobImportToolSchemas.swift
//  Sprung
//
//  Tool definitions for the job-posting import agent loop: Anthropic
//  server-side web_search + web_fetch (executed on Anthropic's infrastructure,
//  used only by the URL variant) plus the strict `submit_job` completion tool.
//  Input-schema keys are camelCase (keys we control); tool names stay
//  snake_case per the app-wide Anthropic tool naming convention.
//

import Foundation
import SwiftOpenAI

enum JobImportToolSchemas {
    // MARK: - Tool Names

    /// Completion tool: the agent submits the extracted job through this tool,
    /// which terminates the shared `AnthropicToolLoopRunner` loop.
    static let submitJobToolName = "submit_job"

    // MARK: - Budgets (single page — small on purpose)

    /// Server-side web_search invocations per request: a page or two to locate
    /// the posting if the given URL redirects or 404s.
    static let webSearchMaxUses = 5

    /// Server-side web_fetch invocations per request: one for the posting page,
    /// a few spare for a follow redirect / "read more" link.
    static let webFetchMaxUses = 5

    /// Token cap per fetched page. A full job posting page (nav + boilerplate +
    /// the description) fits comfortably here.
    static let webFetchMaxContentTokens = 16000

    // MARK: - Complete Tool Definitions

    /// URL variant: both server-side web tools plus the strict completion tool.
    /// The agent fetches the posting page itself, then submits.
    static var urlModeTools: [AnthropicTool] {
        [
            .serverTool(.webSearch(maxUses: webSearchMaxUses)),
            .serverTool(.webFetch(maxUses: webFetchMaxUses, maxContentTokens: webFetchMaxContentTokens)),
            .function(submitJobTool)
        ]
    }

    /// Text variant: the posting text is supplied directly (LinkedIn MCP
    /// `get_job_details` innerText), so there is no web step — only the
    /// completion tool, forced on the first turn.
    static var textModeTools: [AnthropicTool] {
        [.function(submitJobTool)]
    }

    private static var submitJobTool: AnthropicFunctionTool {
        AnthropicFunctionTool(
            name: submitJobToolName,
            description: """
                Submit the structured job posting. Call exactly once, after you \
                have the posting content. Extract ALL available information. For \
                jobDescription, include the COMPLETE description — every \
                responsibility, requirement, qualification, and benefit — never \
                summarize or truncate it. For any field the posting does not \
                state, use the exact string "Not specified".
                """,
            inputSchema: submitJobSchema,
            strict: true
        )
    }

    // MARK: - submit_job Schema (strict: every object closed, every property required)

    static var submitJobSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "jobTitle": [
                    "type": "string",
                    "description": "The exact job title as shown in the posting"
                ],
                "company": [
                    "type": "string",
                    "description": "Company name"
                ],
                "location": [
                    "type": "string",
                    "description": "Job location (city, state/country)"
                ],
                "workplaceType": [
                    "type": "string",
                    "description": "Remote, Hybrid, Onsite, or Flexible"
                ],
                "employmentType": [
                    "type": "string",
                    "description": "Full-time, Part-time, Contract, Internship, etc."
                ],
                "seniorityLevel": [
                    "type": "string",
                    "description": "Entry, Mid, Senior, Lead, Director, etc. if mentioned"
                ],
                "industries": [
                    "type": "string",
                    "description": "Relevant industries or sectors"
                ],
                "postedDate": [
                    "type": "string",
                    "description": "When the job was posted, if available"
                ],
                "salary": [
                    "type": "string",
                    "description": "Salary range or compensation details if mentioned"
                ],
                "jobDescription": [
                    "type": "string",
                    "description": "The COMPLETE job description including all responsibilities, requirements, qualifications, benefits, and any other details. Do not summarize."
                ],
                "applyLink": [
                    "type": "string",
                    "description": "Direct application URL if different from the source URL"
                ]
            ],
            "required": [
                "jobTitle", "company", "location", "workplaceType", "employmentType",
                "seniorityLevel", "industries", "postedDate", "salary", "jobDescription", "applyLink"
            ],
            "additionalProperties": false
        ]
    }
}
