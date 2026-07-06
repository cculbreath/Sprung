//
//  SiteJobSearchToolSchemas.swift
//  Sprung
//
//  Tool definitions for the agentic small-site job search loop: Anthropic
//  server-side web_search + web_fetch (executed on Anthropic's
//  infrastructure) plus the strict `submit_job_listings` completion tool.
//  Input-schema keys are camelCase (keys we control); tool names stay
//  snake_case per the app-wide Anthropic tool naming convention.
//

import Foundation
import SwiftOpenAI

enum SiteJobSearchToolSchemas {
    // MARK: - Tool Names

    /// Completion tool: the agent submits its page-verified posting list
    /// through this tool, which terminates the shared `AnthropicToolLoopRunner`
    /// loop.
    static let submitListingsToolName = "submit_job_listings"

    // MARK: - Budgets

    /// Server-side web_search invocations per request. The search space is a
    /// single site (queries are scoped with the site: operator), so a smaller
    /// budget than the open-web event discovery loop is plenty — web_fetch
    /// navigation of the site's own index pages does most of the discovery.
    static let webSearchMaxUses = 8

    /// Server-side web_fetch invocations per request — index/listing pages in
    /// Phase A plus one per candidate posting verified in Phase B. Generous on
    /// purpose: fetch budget is what caps how many postings survive
    /// verification (matches the event discovery loop).
    static let webFetchMaxUses = 25

    /// Token cap per fetched page. A posting page's facts (title, company,
    /// location, salary, posted date, description) never need a whole site.
    static let webFetchMaxContentTokens = 8000

    // MARK: - Complete Tool Definitions

    /// All site-search tools: both server-side web tools plus the strict
    /// completion tool.
    static var allTools: [AnthropicTool] {
        [
            .serverTool(.webSearch(maxUses: webSearchMaxUses)),
            .serverTool(.webFetch(maxUses: webFetchMaxUses, maxContentTokens: webFetchMaxContentTokens)),
            .function(AnthropicFunctionTool(
                name: submitListingsToolName,
                description: """
                    Submit the final list of page-verified job postings from the target site. \
                    Call exactly once, when Phase B verification is complete. Every listing must \
                    carry details verified by fetching its posting page — never submit a listing \
                    on a search snippet or index-page teaser alone. Submit an empty list (with \
                    emptyReason) if the site was unreachable or nothing matched.
                    """,
                inputSchema: submitListingsSchema,
                strict: true
            ))
        ]
    }

    // MARK: - submit_job_listings Schema (strict: every object closed, every property required)

    static var submitListingsSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "listings": [
                    "type": "array",
                    "description": "Every posting verified in Phase B. Empty if the site was unreachable or nothing matched.",
                    "items": listingSchema
                ],
                "emptyReason": [
                    "type": ["string", "null"],
                    "description": "When listings is empty: one plain sentence saying why (site unreachable / bot-walled, or no postings matched). Null when listings is non-empty."
                ]
            ],
            "required": ["listings", "emptyReason"],
            "additionalProperties": false
        ]
    }

    private static var listingSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "title": [
                    "type": "string",
                    "description": "Job title exactly as shown on the fetched posting page"
                ],
                "company": [
                    "type": "string",
                    "description": "Hiring company as shown on the posting page (the site's own name only when the site itself is the employer)"
                ],
                "url": [
                    "type": "string",
                    "description": "The posting's canonical detail-page URL — the page that was fetched and verified"
                ],
                "location": [
                    "type": ["string", "null"],
                    "description": "Location as shown on the posting page (e.g. \"Austin, TX\" or \"Remote\"); null if the page shows none"
                ],
                "salary": [
                    "type": ["string", "null"],
                    "description": "Salary or pay range exactly as listed on the posting page; null if the page does not state one"
                ],
                "summary": [
                    "type": "string",
                    "description": "Faithful excerpt or condensation of the posting page's description — the page's own wording, no fabrication, no invented details"
                ],
                "postedDate": [
                    "type": ["string", "null"],
                    "description": "Posting date exactly as shown on the page (any format the page uses); null if the page shows none"
                ]
            ],
            "required": ["title", "company", "url", "location", "salary", "summary", "postedDate"],
            "additionalProperties": false
        ]
    }
}
