//
//  IntermediateRepresentation.swift
//  Sprung
//
//  A faithful, high-fidelity stand-in for an ingested source (a PDF or a git
//  repository), produced ONCE at ingestion. Downstream skill / narrative /
//  enrichment extraction runs — and can be re-run — against this representation
//  WITHOUT re-parsing the source (no Files-API re-upload, no live git agent).
//
//  ┌─ CACHE INVARIANT ──────────────────────────────────────────────────────┐
//  │ `renderedForExtraction()` becomes the cached source block for every       │
//  │ extraction pass (summary, skills, cards, verification, enrichment). It    │
//  │ MUST therefore be deterministic and byte-stable for a given value:        │
//  │   • ordered arrays only — never dictionary iteration                      │
//  │   • no timestamps / volatile provenance in the rendered text              │
//  │   • fixed field order                                                     │
//  │ A drift here re-pays the per-document source-block cache entry on every   │
//  │ pass. `IntermediateRepresentationTests` guards this.                      │
//  └───────────────────────────────────────────────────────────────────────┘
//

import Foundation

// MARK: - IntermediateRepresentation

/// The unified ingestion intermediate representation feeding extraction.
enum IntermediateRepresentation: Codable, Sendable {
    /// One-time multimodal transcription of a PDF (verbatim text + faithful
    /// visual/table descriptions + production-quality signal).
    case pdf(DocumentTranscription)
    /// Frozen output of a thorough multi-turn git-exploration agent — a code
    /// dossier with receipts (path + line range + commit on every claim).
    case git(RepositoryDigest)

    /// True when source locations are page-addressable (PDF). Git uses
    /// path/line/commit anchors instead, so it is NOT paged.
    var isPaged: Bool {
        if case .pdf = self { return true }
        return false
    }

    /// Verbatim/full textual content of the source. Used at ingestion to
    /// populate `ArtifactRecord.extractedContent` (the interview-context
    /// full-text path) and as voice-anchoring raw material — replacing native
    /// PDF text extraction with the higher-fidelity transcription.
    var fullText: String {
        switch self {
        case .pdf(let t):
            return t.fullText
        case .git(let d):
            // Git has no single prose body; the README/docs plus the agent's
            // architecture summary are the closest faithful "full text".
            var parts: [String] = []
            if !d.architecture.isEmpty { parts.append(d.architecture) }
            let docs = d.readmeAndDocs.map(\.content).filter { !$0.isEmpty }
            parts.append(contentsOf: docs)
            return parts.joined(separator: "\n\n")
        }
    }

    /// Deterministic Markdown rendering consumed by extraction passes as the
    /// cached source block. Byte-stable across calls and across a JSON
    /// round-trip for a given value. Volatile provenance is deliberately
    /// omitted (see CACHE INVARIANT above).
    func renderedForExtraction() -> String {
        switch self {
        case .pdf(let t):
            return t.renderedForExtraction()
        case .git(let d):
            return d.renderedForExtraction()
        }
    }

    // MARK: Codable (explicit discriminator for a stable persisted shape)

    private enum CodingKeys: String, CodingKey { case type, pdf, git }
    private enum Kind: String, Codable { case pdf, git }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .pdf:
            self = .pdf(try container.decode(DocumentTranscription.self, forKey: .pdf))
        case .git:
            self = .git(try container.decode(RepositoryDigest.self, forKey: .git))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pdf(let transcription):
            try container.encode(Kind.pdf, forKey: .type)
            try container.encode(transcription, forKey: .pdf)
        case .git(let digest):
            try container.encode(Kind.git, forKey: .type)
            try container.encode(digest, forKey: .git)
        }
    }

    // MARK: Persistence codec (single source of truth)

    /// The IR is persisted as a JSON string in `ArtifactRecord.intermediateRepresentationJSON`.
    /// `IRProvenance.createdAt` is a `Date`, so the encode/decode date strategy is
    /// load-bearing: every ingestion path MUST encode through `encodedJSONString()`
    /// and every read MUST decode through `decode(fromJSONString:)` so the strategies
    /// stay in lockstep. ISO-8601 is chosen for human-readable, stable persistence.
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Encode this IR to the JSON string stored on the artifact.
    func encodedJSONString() throws -> String {
        let data = try Self.makeEncoder().encode(self)
        return String(decoding: data, as: UTF8.self)
    }

    /// Decode an IR from a persisted JSON string (nil when absent or malformed).
    static func decode(fromJSONString json: String?) -> IntermediateRepresentation? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? makeDecoder().decode(IntermediateRepresentation.self, from: data)
    }
}

// MARK: - Shared provenance

/// Reproducibility metadata for an IR. NEVER appears in `renderedForExtraction()`
/// (it carries `createdAt` and other volatile values that would break the cache
/// invariant). Git-specific fields are nil for PDF transcriptions.
struct IRProvenance: Codable, Sendable {
    var sourceArtifactId: String
    var sha256: String?
    var modelId: String
    var promptVersion: String
    var createdAt: Date
    // Git-only:
    var analyzedCommit: String?
    var explorationTurnCount: Int?
    var toolVersions: String?

    init(
        sourceArtifactId: String,
        sha256: String? = nil,
        modelId: String,
        promptVersion: String,
        createdAt: Date,
        analyzedCommit: String? = nil,
        explorationTurnCount: Int? = nil,
        toolVersions: String? = nil
    ) {
        self.sourceArtifactId = sourceArtifactId
        self.sha256 = sha256
        self.modelId = modelId
        self.promptVersion = promptVersion
        self.createdAt = createdAt
        self.analyzedCommit = analyzedCommit
        self.explorationTurnCount = explorationTurnCount
        self.toolVersions = toolVersions
    }
}

// MARK: - PDF transcription

/// One-time, deliberately high-fidelity transcription of a PDF. Explicitly NOT a
/// summary: text is verbatim, visuals are fully described (with their actual data),
/// and production quality is judged from what the model sees.
struct DocumentTranscription: Codable, Sendable {
    /// Verbatim reading-order transcription as Markdown — headings / lists /
    /// structure preserved, NOT condensed.
    var fullText: String
    /// Charts/figures/diagrams/images described faithfully, with their data.
    var visualElements: [VisualElement]
    /// Tables rendered faithfully.
    var tables: [TranscribedTable]
    /// Explicit support-skill signal (LaTeX, graphic-design chops, …).
    var productionQuality: TranscriptionProductionQuality
    /// Section outline / page map.
    var structure: String
    var docMeta: DocMeta
    var provenance: IRProvenance

    init(
        fullText: String,
        visualElements: [VisualElement] = [],
        tables: [TranscribedTable] = [],
        productionQuality: TranscriptionProductionQuality,
        structure: String = "",
        docMeta: DocMeta,
        provenance: IRProvenance
    ) {
        self.fullText = fullText
        self.visualElements = visualElements
        self.tables = tables
        self.productionQuality = productionQuality
        self.structure = structure
        self.docMeta = docMeta
        self.provenance = provenance
    }

    /// Deterministic Markdown for the extraction source block. Page-ordered
    /// visuals/tables; no provenance. Empty sections are omitted.
    func renderedForExtraction() -> String {
        var lines: [String] = []
        lines.append("# Document Transcription")
        lines.append("")
        lines.append(fullText)

        if !visualElements.isEmpty {
            lines.append("")
            lines.append("## Visual Elements")
            for element in visualElements {
                var header = "### Page \(element.page) — \(element.kind)"
                if let caption = element.caption, !caption.isEmpty {
                    header += ": \(caption)"
                }
                lines.append("")
                lines.append(header)
                lines.append(element.faithfulDescription)
                if let dataPoints = element.dataPoints, !dataPoints.isEmpty {
                    lines.append("Data points:")
                    for point in dataPoints { lines.append("- \(point)") }
                }
            }
        }

        if !tables.isEmpty {
            lines.append("")
            lines.append("## Tables")
            for table in tables {
                lines.append("")
                lines.append("### Page \(table.page)")
                lines.append(table.markdown)
            }
        }

        lines.append("")
        lines.append("## Production Quality")
        lines.append(contentsOf: productionQuality.renderedLines())

        if !structure.isEmpty {
            lines.append("")
            lines.append("## Document Structure")
            lines.append(structure)
        }

        lines.append("")
        lines.append("## Document Metadata")
        lines.append("- Pages: \(docMeta.pageCount)")
        lines.append("- Language: \(docMeta.language)")
        lines.append("- Document class: \(docMeta.docClassGuess)")

        return lines.joined(separator: "\n")
    }
}

/// A described visual on a page. `dataPoints` carries the actual values a chart
/// conveys so the information is not lost when the pixels are gone.
struct VisualElement: Codable, Sendable {
    var page: Int
    /// chart | figure | diagram | image | photo
    var kind: String
    var caption: String?
    /// What it depicts + the actual data/values conveyed.
    var faithfulDescription: String
    var dataPoints: [String]?

    init(page: Int, kind: String, caption: String? = nil, faithfulDescription: String, dataPoints: [String]? = nil) {
        self.page = page
        self.kind = kind
        self.caption = caption
        self.faithfulDescription = faithfulDescription
        self.dataPoints = dataPoints
    }
}

/// A faithfully rendered table.
struct TranscribedTable: Codable, Sendable {
    var page: Int
    /// Markdown rendering (or structured rows serialized to Markdown).
    var markdown: String

    init(page: Int, markdown: String) {
        self.page = page
        self.markdown = markdown
    }
}

/// Production-quality signal judged from the rendered document — the explicit
/// support-skill axis (typesetting system, layout, typography, polish).
struct TranscriptionProductionQuality: Codable, Sendable {
    /// LaTeX | Word | InDesign | GoogleDocs | …
    var typesettingSystemGuess: String
    var typesettingEvidence: String
    var layoutSophistication: String
    var columns: Int?
    var typography: String
    var colorAndGraphicDesignSignals: String
    var overallPolish: String
    var rationale: String

    init(
        typesettingSystemGuess: String,
        typesettingEvidence: String = "",
        layoutSophistication: String = "",
        columns: Int? = nil,
        typography: String = "",
        colorAndGraphicDesignSignals: String = "",
        overallPolish: String = "",
        rationale: String = ""
    ) {
        self.typesettingSystemGuess = typesettingSystemGuess
        self.typesettingEvidence = typesettingEvidence
        self.layoutSophistication = layoutSophistication
        self.columns = columns
        self.typography = typography
        self.colorAndGraphicDesignSignals = colorAndGraphicDesignSignals
        self.overallPolish = overallPolish
        self.rationale = rationale
    }

    /// Deterministic bullet lines; empty fields are omitted.
    func renderedLines() -> [String] {
        var lines: [String] = []
        func add(_ label: String, _ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { lines.append("- \(label): \(trimmed)") }
        }
        add("Typesetting system", typesettingSystemGuess)
        add("Typesetting evidence", typesettingEvidence)
        add("Layout sophistication", layoutSophistication)
        if let columns { lines.append("- Columns: \(columns)") }
        add("Typography", typography)
        add("Color & graphic design", colorAndGraphicDesignSignals)
        add("Overall polish", overallPolish)
        add("Rationale", rationale)
        return lines
    }
}

/// Document-level metadata.
struct DocMeta: Codable, Sendable {
    var pageCount: Int
    var language: String
    /// resume | paper | portfolio | slides | …
    var docClassGuess: String

    init(pageCount: Int, language: String = "", docClassGuess: String = "") {
        self.pageCount = pageCount
        self.language = language
        self.docClassGuess = docClassGuess
    }
}

// MARK: - Git repository digest

/// The frozen output of a thorough multi-turn git-exploration agent: a verifiable
/// code dossier WITH RECEIPTS, rich enough that downstream extraction never
/// re-clones or re-runs the live agent. Real skill signal lives in architecture,
/// dependency-usage depth, authorship, and engineering sophistication — those
/// fields are first-class precisely because they separate skill from boilerplate.
struct RepositoryDigest: Codable, Sendable {
    var repoName: String

    // ── Mechanical layer (lossless, cheap) ───────────────────────────────
    /// Rendered file tree with sizes / per-dir counts.
    var fileTree: String
    /// LOC + file count + % per language.
    var languageStats: [LanguageStat]
    /// VERBATIM manifests (package.json / Package.swift / Cargo.toml / go.mod /
    /// pyproject / Dockerfile / compose / k8s / terraform / CI / Makefile /
    /// lint+format configs / tsconfig). Richest declared-skill signal; kept whole.
    var manifests: [RepoFile]
    /// Verbatim README, CONTRIBUTING, ADRs, /docs.
    var readmeAndDocs: [RepoFile]
    /// Detected mains / app / server bootstraps.
    var entryPoints: [String]
    var gitHistory: GitHistory
    /// Per-contributor commit/LOC share + blame on core files — did the applicant
    /// write the bulk, or is it forked/boilerplate?
    var authorship: [ContributorShare]

    // ── Dependency-depth layer (semi-mechanical; defeats name-dropping) ───
    var dependencyUsage: [DependencyUsage]

    // ── Agent-authored analysis (multi-turn, frozen, evidence-anchored) ───
    /// Subsystems, responsibilities, interactions, data flow, key abstractions.
    var architecture: String
    /// What the software actually does (features built).
    var capabilities: [String]
    /// Non-obvious engineering, each with verbatim excerpt + path/lines + why.
    var technicalHighlights: [TechnicalHighlight]
    /// Curated, PURPOSE-TAGGED verbatim snippets tied to specific claims.
    var codeExcerpts: [CodeExcerpt]
    var productionQuality: RepoProductionQuality
    /// Pre-extraction candidate skills + strength + anchors (raw material the
    /// extraction prompt refines — NOT the final Skill bank).
    var skillSignals: [SkillSignal]
    /// Explicit log of dirs/files NOT examined and why (size caps, vendored,
    /// generated) — honors "no silent caps".
    var omissions: String
    var provenance: IRProvenance

    init(
        repoName: String,
        fileTree: String = "",
        languageStats: [LanguageStat] = [],
        manifests: [RepoFile] = [],
        readmeAndDocs: [RepoFile] = [],
        entryPoints: [String] = [],
        gitHistory: GitHistory,
        authorship: [ContributorShare] = [],
        dependencyUsage: [DependencyUsage] = [],
        architecture: String = "",
        capabilities: [String] = [],
        technicalHighlights: [TechnicalHighlight] = [],
        codeExcerpts: [CodeExcerpt] = [],
        productionQuality: RepoProductionQuality,
        skillSignals: [SkillSignal] = [],
        omissions: String = "",
        provenance: IRProvenance
    ) {
        self.repoName = repoName
        self.fileTree = fileTree
        self.languageStats = languageStats
        self.manifests = manifests
        self.readmeAndDocs = readmeAndDocs
        self.entryPoints = entryPoints
        self.gitHistory = gitHistory
        self.authorship = authorship
        self.dependencyUsage = dependencyUsage
        self.architecture = architecture
        self.capabilities = capabilities
        self.technicalHighlights = technicalHighlights
        self.codeExcerpts = codeExcerpts
        self.productionQuality = productionQuality
        self.skillSignals = skillSignals
        self.omissions = omissions
        self.provenance = provenance
    }

    /// Deterministic Markdown for the extraction source block. No provenance.
    /// Empty sections omitted.
    func renderedForExtraction() -> String {
        var lines: [String] = []
        lines.append("# Repository Digest: \(repoName)")

        if !architecture.isEmpty {
            lines.append("")
            lines.append("## Architecture")
            lines.append(architecture)
        }

        if !capabilities.isEmpty {
            lines.append("")
            lines.append("## Capabilities")
            for capability in capabilities { lines.append("- \(capability)") }
        }

        if !languageStats.isEmpty {
            lines.append("")
            lines.append("## Languages")
            for stat in languageStats {
                lines.append("- \(stat.language): \(stat.loc) LOC, \(stat.fileCount) files, \(stat.percentString)")
            }
        }

        if !dependencyUsage.isEmpty {
            lines.append("")
            lines.append("## Dependency Usage")
            for dependency in dependencyUsage {
                lines.append("- \(dependency.dependency) (\(dependency.importCount) imports): \(dependency.usageNotes)")
            }
        }

        if !technicalHighlights.isEmpty {
            lines.append("")
            lines.append("## Technical Highlights")
            for highlight in technicalHighlights {
                lines.append("")
                lines.append("### \(highlight.title)")
                lines.append(highlight.description)
                lines.append("Location: \(highlight.locationString)")
                if !highlight.whyNotable.isEmpty { lines.append("Why notable: \(highlight.whyNotable)") }
                if !highlight.verbatimExcerpt.isEmpty {
                    lines.append("```")
                    lines.append(highlight.verbatimExcerpt)
                    lines.append("```")
                }
            }
        }

        if !codeExcerpts.isEmpty {
            lines.append("")
            lines.append("## Code Excerpts")
            for excerpt in codeExcerpts {
                lines.append("")
                lines.append("### \(excerpt.purpose) — \(excerpt.locationString)")
                if let claim = excerpt.tiedToClaim, !claim.isEmpty { lines.append("Supports: \(claim)") }
                lines.append("```")
                lines.append(excerpt.excerpt)
                lines.append("```")
            }
        }

        lines.append("")
        lines.append("## Production Quality")
        lines.append(contentsOf: productionQuality.renderedLines())

        if !authorship.isEmpty {
            lines.append("")
            lines.append("## Authorship")
            for share in authorship {
                var line = "- \(share.name): \(share.commitShareString) commits, \(share.locShareString) LOC"
                if let blame = share.blameOnCoreFiles, !blame.isEmpty { line += " — \(blame)" }
                lines.append(line)
            }
        }

        lines.append("")
        lines.append("## Git History")
        lines.append(contentsOf: gitHistory.renderedLines())

        if !entryPoints.isEmpty {
            lines.append("")
            lines.append("## Entry Points")
            for entry in entryPoints { lines.append("- \(entry)") }
        }

        if !skillSignals.isEmpty {
            lines.append("")
            lines.append("## Candidate Skill Signals")
            for signal in skillSignals {
                var line = "- \(signal.skill) (\(signal.strength))"
                if !signal.anchors.isEmpty { line += " — anchors: \(signal.anchors.joined(separator: "; "))" }
                lines.append(line)
            }
        }

        if !manifests.isEmpty {
            lines.append("")
            lines.append("## Manifests")
            for manifest in manifests {
                lines.append("")
                lines.append("### \(manifest.path)")
                lines.append("```")
                lines.append(manifest.content)
                lines.append("```")
            }
        }

        if !readmeAndDocs.isEmpty {
            lines.append("")
            lines.append("## Documentation")
            for doc in readmeAndDocs {
                lines.append("")
                lines.append("### \(doc.path)")
                lines.append(doc.content)
            }
        }

        if !fileTree.isEmpty {
            lines.append("")
            lines.append("## File Tree")
            lines.append("```")
            lines.append(fileTree)
            lines.append("```")
        }

        if !omissions.isEmpty {
            lines.append("")
            lines.append("## Omissions (not examined)")
            lines.append(omissions)
        }

        return lines.joined(separator: "\n")
    }
}

struct LanguageStat: Codable, Sendable {
    var language: String
    var loc: Int
    var fileCount: Int
    var percent: Double

    init(language: String, loc: Int, fileCount: Int, percent: Double) {
        self.language = language
        self.loc = loc
        self.fileCount = fileCount
        self.percent = percent
    }

    /// Stable one-decimal percentage, locale-independent.
    var percentString: String { String(format: "%.1f%%", percent) }
}

/// A verbatim file kept whole (manifest, README, ADR, …).
struct RepoFile: Codable, Sendable {
    var path: String
    var content: String

    init(path: String, content: String) {
        self.path = path
        self.content = content
    }
}

struct GitHistory: Codable, Sendable {
    var commitCount: Int
    var dateRange: String
    var cadence: String
    var topChurnFiles: [String]
    var branches: [String]
    var tags: [String]

    init(
        commitCount: Int,
        dateRange: String = "",
        cadence: String = "",
        topChurnFiles: [String] = [],
        branches: [String] = [],
        tags: [String] = []
    ) {
        self.commitCount = commitCount
        self.dateRange = dateRange
        self.cadence = cadence
        self.topChurnFiles = topChurnFiles
        self.branches = branches
        self.tags = tags
    }

    func renderedLines() -> [String] {
        var lines: [String] = []
        lines.append("- Commits: \(commitCount)")
        if !dateRange.isEmpty { lines.append("- Date range: \(dateRange)") }
        if !cadence.isEmpty { lines.append("- Cadence: \(cadence)") }
        if !topChurnFiles.isEmpty { lines.append("- Top-churn files: \(topChurnFiles.joined(separator: ", "))") }
        if !branches.isEmpty { lines.append("- Branches: \(branches.joined(separator: ", "))") }
        if !tags.isEmpty { lines.append("- Tags: \(tags.joined(separator: ", "))") }
        return lines
    }
}

struct ContributorShare: Codable, Sendable {
    var name: String
    /// Fraction in [0, 1].
    var commitShare: Double
    var locShare: Double
    var blameOnCoreFiles: String?

    init(name: String, commitShare: Double, locShare: Double, blameOnCoreFiles: String? = nil) {
        self.name = name
        self.commitShare = commitShare
        self.locShare = locShare
        self.blameOnCoreFiles = blameOnCoreFiles
    }

    var commitShareString: String { String(format: "%.0f%%", commitShare * 100) }
    var locShareString: String { String(format: "%.0f%%", locShare * 100) }
}

/// Per-dependency depth signal, e.g. "react: 142 imports, custom hooks, context
/// providers, Suspense boundaries" vs "lodash: 3 imports".
struct DependencyUsage: Codable, Sendable {
    var dependency: String
    var importCount: Int
    var usageNotes: String

    init(dependency: String, importCount: Int, usageNotes: String) {
        self.dependency = dependency
        self.importCount = importCount
        self.usageNotes = usageNotes
    }
}

struct TechnicalHighlight: Codable, Sendable {
    var title: String
    var description: String
    var verbatimExcerpt: String
    var path: String
    var lineRange: String?
    var whyNotable: String

    init(title: String, description: String, verbatimExcerpt: String = "", path: String, lineRange: String? = nil, whyNotable: String = "") {
        self.title = title
        self.description = description
        self.verbatimExcerpt = verbatimExcerpt
        self.path = path
        self.lineRange = lineRange
        self.whyNotable = whyNotable
    }

    var locationString: String {
        if let lineRange, !lineRange.isEmpty { return "\(path):\(lineRange)" }
        return path
    }
}

struct CodeExcerpt: Codable, Sendable {
    var purpose: String
    var path: String
    var lineRange: String?
    var excerpt: String
    var tiedToClaim: String?

    init(purpose: String, path: String, lineRange: String? = nil, excerpt: String, tiedToClaim: String? = nil) {
        self.purpose = purpose
        self.path = path
        self.lineRange = lineRange
        self.excerpt = excerpt
        self.tiedToClaim = tiedToClaim
    }

    var locationString: String {
        if let lineRange, !lineRange.isEmpty { return "\(path):\(lineRange)" }
        return path
    }
}

/// Engineering-maturity signal, each dimension with evidence.
struct RepoProductionQuality: Codable, Sendable {
    var testing: String
    var cicd: String
    var infraAndDeploy: String
    var observability: String
    var lintFormatTypeSafety: String
    var docsQuality: String
    var accessibilityI18n: String
    var securityTooling: String

    init(
        testing: String = "",
        cicd: String = "",
        infraAndDeploy: String = "",
        observability: String = "",
        lintFormatTypeSafety: String = "",
        docsQuality: String = "",
        accessibilityI18n: String = "",
        securityTooling: String = ""
    ) {
        self.testing = testing
        self.cicd = cicd
        self.infraAndDeploy = infraAndDeploy
        self.observability = observability
        self.lintFormatTypeSafety = lintFormatTypeSafety
        self.docsQuality = docsQuality
        self.accessibilityI18n = accessibilityI18n
        self.securityTooling = securityTooling
    }

    func renderedLines() -> [String] {
        var lines: [String] = []
        func add(_ label: String, _ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { lines.append("- \(label): \(trimmed)") }
        }
        add("Testing", testing)
        add("CI/CD", cicd)
        add("Infrastructure & deploy", infraAndDeploy)
        add("Observability", observability)
        add("Lint / format / type-safety", lintFormatTypeSafety)
        add("Documentation", docsQuality)
        add("Accessibility & i18n", accessibilityI18n)
        add("Security tooling", securityTooling)
        return lines
    }
}

struct SkillSignal: Codable, Sendable {
    var skill: String
    /// e.g. strong | moderate | weak
    var strength: String
    var anchors: [String]

    init(skill: String, strength: String, anchors: [String] = []) {
        self.skill = skill
        self.strength = strength
        self.anchors = anchors
    }
}
