//
//  RepositoryDigestTool.swift
//  Sprung
//
//  The terminal tool of the git-exploration agent. The model calls it to submit
//  the AGENT-AUTHORED analysis layers of a `RepositoryDigest` — architecture,
//  capabilities, technical highlights, code excerpts, dependency usage,
//  production quality, skill signals, entry points, verbatim manifests/docs, and
//  an omissions log. It does NOT emit a card list: downstream extraction derives
//  skills and narrative cards from the rendered digest, exactly like a document.
//
//  The mechanical layers (repo name, file tree, language stats, git history,
//  authorship) are assembled by the kernel from `GitEvidenceCollector` data and
//  are NOT re-emitted by the model.
//

import Foundation

// MARK: - Repository Digest Tool

struct RepositoryDigestTool: AgentTool {
    static let name = "complete_analysis"
    static let description = """
        Call this when you have explored the repository thoroughly and are ready to submit \
        the repository digest — a faithful, fully-cited code dossier. Provide the AGENT-AUTHORED \
        analysis layers: architecture prose, capabilities, technical highlights (each with a \
        VERBATIM excerpt + path + line range + why it is notable), purpose-tagged code excerpts, \
        per-dependency usage depth, evidence-backed production-quality assessment, candidate skill \
        signals with anchors, entry points, the manifests and docs you chose to include VERBATIM, \
        and an explicit omissions log. Every claim must carry a receipt (path + line range, and a \
        commit/tenure reference where the claim is longitudinal). Do NOT produce a card list or a \
        summary — this is the high-fidelity record downstream extraction reads.
        """

    static let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "architecture": [
                "type": "string",
                "description": "Prose describing subsystems, responsibilities, interactions, data flow, and key abstractions. Reference real files."
            ],
            "capabilities": [
                "type": "array",
                "items": ["type": "string"],
                "description": "What the software actually does — features built. One capability per entry."
            ],
            "technicalHighlights": [
                "type": "array",
                "description": "Non-obvious engineering, each anchored to a verbatim excerpt and its location.",
                "items": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string", "description": "Short name of the highlight"],
                        "description": ["type": "string", "description": "What it is and what it accomplishes"],
                        "verbatimExcerpt": ["type": "string", "description": "Code copied EXACTLY from the file (no paraphrase)"],
                        "path": ["type": "string", "description": "Repo-relative file path"],
                        "lineRange": ["type": "string", "description": "Line range, e.g. '45-120'"],
                        "whyNotable": ["type": "string", "description": "Why this is non-obvious / sophisticated"]
                    ],
                    "required": ["title", "description", "verbatimExcerpt", "path", "whyNotable"],
                    "additionalProperties": false
                ]
            ],
            "codeExcerpts": [
                "type": "array",
                "description": "Curated, purpose-tagged verbatim snippets, each tied to a specific claim.",
                "items": [
                    "type": "object",
                    "properties": [
                        "purpose": ["type": "string", "description": "What this excerpt is meant to demonstrate"],
                        "path": ["type": "string", "description": "Repo-relative file path"],
                        "lineRange": ["type": "string", "description": "Line range, e.g. '12-40'"],
                        "excerpt": ["type": "string", "description": "Code copied EXACTLY from the file (no paraphrase)"],
                        "tiedToClaim": ["type": "string", "description": "The claim this excerpt supports"]
                    ],
                    "required": ["purpose", "path", "excerpt"],
                    "additionalProperties": false
                ]
            ],
            "dependencyUsage": [
                "type": "array",
                "description": "Per significant dependency: how deeply it is actually used (defeats name-dropping).",
                "items": [
                    "type": "object",
                    "properties": [
                        "dependency": ["type": "string", "description": "Dependency / framework name"],
                        "importCount": ["type": "integer", "description": "Number of imports / call sites found (via grep)"],
                        "usageNotes": ["type": "string", "description": "Depth signal: which features are used and how"]
                    ],
                    "required": ["dependency", "importCount", "usageNotes"],
                    "additionalProperties": false
                ]
            ],
            "productionQuality": [
                "type": "object",
                "description": "Engineering-maturity assessment, each dimension evidence-backed (cite files). Leave a dimension empty only when no evidence was found.",
                "properties": [
                    "testing": ["type": "string", "description": "Test coverage, frameworks, discipline — with file evidence"],
                    "cicd": ["type": "string", "description": "CI/CD pipelines and automation — with file evidence"],
                    "infraAndDeploy": ["type": "string", "description": "Infrastructure / deployment (Docker, k8s, terraform) — with file evidence"],
                    "observability": ["type": "string", "description": "Logging, metrics, tracing — with file evidence"],
                    "lintFormatTypeSafety": ["type": "string", "description": "Lint / format / type-safety tooling — with file evidence"],
                    "docsQuality": ["type": "string", "description": "Documentation quality — with file evidence"],
                    "accessibilityI18n": ["type": "string", "description": "Accessibility / internationalization — with file evidence"],
                    "securityTooling": ["type": "string", "description": "Security tooling / practices — with file evidence"]
                ],
                "required": [
                    "testing", "cicd", "infraAndDeploy", "observability",
                    "lintFormatTypeSafety", "docsQuality", "accessibilityI18n", "securityTooling"
                ],
                "additionalProperties": false
            ],
            "skillSignals": [
                "type": "array",
                "description": "Candidate skills the code demonstrates — RAW MATERIAL for downstream extraction, not the final skill bank. Be honest about strength.",
                "items": [
                    "type": "object",
                    "properties": [
                        "skill": ["type": "string", "description": "Skill name"],
                        "strength": [
                            "type": "string",
                            "enum": ["strong", "moderate", "weak"],
                            "description": "How strongly the code evidences this skill"
                        ],
                        "anchors": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Concrete receipts: file:line refs and/or commit/tenure references"
                        ]
                    ],
                    "required": ["skill", "strength", "anchors"],
                    "additionalProperties": false
                ]
            ],
            "entryPoints": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Detected mains / app / server bootstraps (repo-relative paths)."
            ],
            "manifests": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Repo-relative PATHS of package manifests / Dockerfile / CI / lint configs to include (package.json, Package.swift, Cargo.toml, go.mod, pyproject, Dockerfile, compose, k8s, terraform, CI workflows, Makefile, lint/format configs, tsconfig). The system reads each file's content VERBATIM — list paths only, do NOT paste contents. Richest declared-skill signal."
            ],
            "readmeAndDocs": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Repo-relative PATHS of README / CONTRIBUTING / ADRs / docs to include. The system reads each file's content VERBATIM — list paths only, do NOT paste contents."
            ],
            "omissions": [
                "type": "string",
                "description": "Explicit prose log of directories/files NOT examined and why (size caps, vendored, generated). No silent caps."
            ]
        ],
        "required": [
            "architecture", "capabilities", "technicalHighlights", "codeExcerpts",
            "dependencyUsage", "productionQuality", "skillSignals", "entryPoints",
            "manifests", "readmeAndDocs", "omissions"
        ],
        "additionalProperties": false
    ]

    // MARK: - Parameter Types for Decoding

    /// The agent-authored analysis layers of a `RepositoryDigest`. Reuses the IR
    /// contract types verbatim (all `Codable`), so decoding this is the parser.
    struct Parameters: Codable {
        let architecture: String
        let capabilities: [String]
        let technicalHighlights: [TechnicalHighlight]
        let codeExcerpts: [CodeExcerpt]
        let dependencyUsage: [DependencyUsage]
        let productionQuality: RepoProductionQuality
        let skillSignals: [SkillSignal]
        let entryPoints: [String]
        let manifests: [String]        // repo-relative paths; kernel reads each file's content
        let readmeAndDocs: [String]    // repo-relative paths; kernel reads each file's content
        let omissions: String
    }
}
