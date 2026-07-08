//
//  JobScoutToolSchemas.swift
//  Sprung
//
//  Tool definitions for the Job Scout agent loop: `search_board` (client-side
//  routing into the Dice/ZipRecruiter/LinkedIn search services),
//  `get_job_details` (LinkedIn posting text over the local MCP server), and
//  the strict `recommend_jobs` completion tool. Input-schema keys are
//  camelCase (keys we control); tool names stay snake_case per the app-wide
//  Anthropic tool naming convention. Every schema is strict-compatible:
//  every object closed (additionalProperties:false), every property required,
//  optionals as explicit-null union types.
//

import Foundation
import SwiftOpenAI

enum JobScoutToolSchemas {
    // MARK: - Tool Names

    static let searchBoardToolName = "search_board"
    static let getJobDetailsToolName = "get_job_details"
    /// Completion tool: the agent submits its final recommendations through
    /// this tool, which terminates the shared `AnthropicToolLoopRunner` loop.
    static let recommendJobsToolName = "recommend_jobs"

    /// `search_board`'s `datePosted` values (camelCase keys we control; the
    /// service maps them onto LinkedIn's snake_case wire facet).
    static let datePostedValues = ["pastHour", "past24Hours", "pastWeek", "pastMonth"]

    // MARK: - web_fetch Budget (drill into the promising few)

    /// Server-side web_fetch invocations per run: enough to read the handful of
    /// genuinely promising Dice/ZipRecruiter postings, never every result.
    /// (LinkedIn postings go through get_job_details / the local MCP instead.)
    static let webFetchMaxUses = 8
    /// Token cap per fetched posting — enough to judge the requirements and
    /// responsibilities without one page dominating the conversation across
    /// several fetches. Judgment needs the gist, not a verbatim extraction.
    static let webFetchMaxContentTokens = 4000

    // MARK: - Complete Tool Definitions

    static var allTools: [AnthropicTool] {
        [
            .serverTool(.webFetch(maxUses: webFetchMaxUses, maxContentTokens: webFetchMaxContentTokens)),
            .function(AnthropicFunctionTool(
                name: searchBoardToolName,
                description: """
                    Search one job board for current postings. Only boards enabled for this run \
                    may be searched. Results come back deduplicated: postings already in the \
                    user's pipeline, and repeats already returned this run, are removed before \
                    you see them (droppedDuplicates reports how many). Dice and ZipRecruiter \
                    results carry company/location details (Dice includes a short description \
                    snippet); LinkedIn results carry only titles and canonical posting URLs; \
                    jsearch and serpApi are Google-for-Jobs aggregators (Indeed, LinkedIn, \
                    Glassdoor and more), and indeed searches Indeed directly — all three carry \
                    company, location, and a description snippet. To read a posting's full text \
                    before recommending it, fetch its url with web_fetch (LinkedIn postings use \
                    get_job_details instead).
                    """,
                inputSchema: searchBoardSchema,
                strict: true
            )),
            .function(AnthropicFunctionTool(
                name: getJobDetailsToolName,
                description: """
                    Fetch the full posting text behind a LinkedIn job URL. LinkedIn URLs ONLY — \
                    LinkedIn needs the signed-in session the app holds, so its postings can't be \
                    read with web_fetch. For Dice and ZipRecruiter postings, use web_fetch on the \
                    posting url instead. Calls here share a limited hourly LinkedIn budget with \
                    the rest of the app: drill into the handful of genuinely promising titles, \
                    never every result.
                    """,
                inputSchema: getJobDetailsSchema,
                strict: true
            )),
            .function(AnthropicFunctionTool(
                name: recommendJobsToolName,
                description: """
                    Submit your final recommendations. Call exactly once, when you have searched \
                    the enabled boards and judged the results against the candidate's background. \
                    Every recommendation must be a posting a search in THIS run returned — never \
                    from memory. Stay within the recommendation limit from the task message. If \
                    nothing is worth recommending, submit an empty list with an emptyReason that \
                    says plainly why.
                    """,
                inputSchema: recommendJobsSchema,
                strict: true
            ))
        ]
    }

    // MARK: - search_board Schema

    static var searchBoardSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "board": [
                    "type": "string",
                    "enum": JobScoutService.ScoutBoard.allCases.map(\.rawValue),
                    "description": "The board to search — must be enabled for this run"
                ],
                "keywords": [
                    "type": "string",
                    "description": "Role keywords for this search (e.g. \"medical physicist\"). Vary phrasing between calls to the same board."
                ],
                "location": [
                    "type": ["string", "null"],
                    "description": "Location filter (e.g. \"Austin, TX\"); null to search without one"
                ],
                "datePosted": [
                    "type": ["string", "null"],
                    "description": "Recency filter, one of \(datePostedValues.joined(separator: " | ")); honored on linkedIn only, ignored elsewhere. Null for no filter."
                ]
            ],
            "required": ["board", "keywords", "location", "datePosted"],
            "additionalProperties": false
        ]
    }

    // MARK: - get_job_details Schema

    static var getJobDetailsSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "url": [
                    "type": "string",
                    "description": "The LinkedIn posting URL exactly as a search_board result returned it"
                ]
            ],
            "required": ["url"],
            "additionalProperties": false
        ]
    }

    // MARK: - recommend_jobs Schema (strict: every object closed, every property required)

    static var recommendJobsSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "recommendations": [
                    "type": "array",
                    "description": "The postings worth the candidate's attention, strongest match first, at most the recommendation limit. Empty if nothing qualified.",
                    "items": recommendationSchema
                ],
                "emptyReason": [
                    "type": ["string", "null"],
                    "description": "When recommendations is empty: one plain sentence saying why (boards unreachable, nothing matched the candidate). Null when recommendations is non-empty."
                ]
            ],
            "required": ["recommendations", "emptyReason"],
            "additionalProperties": false
        ]
    }

    private static var recommendationSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "url": [
                    "type": "string",
                    "description": "The posting URL exactly as the search result returned it — never rewritten"
                ],
                "title": [
                    "type": "string",
                    "description": "Job title as the board or posting shows it"
                ],
                "company": [
                    "type": "string",
                    "description": "Hiring company. For LinkedIn results (which carry no company in search results) take it from get_job_details."
                ],
                "reasoning": [
                    "type": "string",
                    "description": "2-3 plain sentences, in a natural voice, connecting this posting to the candidate's actual background. No formulas, no invented metrics, no buzzwords."
                ],
                "match": matchAssessmentSchema
            ],
            "required": ["url", "title", "company", "reasoning", "match"],
            "additionalProperties": false
        ]
    }

    // MARK: - match Assessment Schema (strict: closed, every dimension required)

    /// A dimensioned fit assessment attached to each recommendation. Ratings
    /// are honest enums — `unknown` is a real answer ("the posting doesn't
    /// say"), never a number.
    private static var matchAssessmentSchema: [String: Any] {
        [
            "type": "object",
            "description": "A dimensioned fit assessment for this posting against the candidate's real background. Augments the reasoning; never replaces it.",
            "properties": [
                "skills": ratingProperty(
                    "How well the candidate's demonstrated skills and experience meet the posting's requirements."
                ),
                "seniority": ratingProperty(
                    "How well the candidate's seniority fits the role's level — under- or over-qualified both weaken it."
                ),
                "locationFit": ratingProperty(
                    "How well the posting's location and work arrangement fit the candidate's stated preferences."
                ),
                "compensation": ratingProperty(
                    "How well the stated compensation fits the candidate; unknown when the posting gives no salary."
                ),
                "verdict": [
                    "type": "string",
                    "enum": ["strong", "promising", "marginal"],
                    "description": "Overall recommendation strength. A ceiling on enthusiasm, never a quota — marginal is the honest verdict when the fit is thin."
                ]
            ],
            "required": ["skills", "seniority", "locationFit", "compensation", "verdict"],
            "additionalProperties": false
        ]
    }

    /// One rating dimension: a required enum with an explicit `unknown` so an
    /// unstated fact is a deliberate answer, not an omission.
    private static func ratingProperty(_ description: String) -> [String: Any] {
        [
            "type": "string",
            "enum": ["strong", "moderate", "weak", "unknown"],
            "description": description
        ]
    }
}
