import Foundation
import SwiftData
import SwiftyJSON

// MARK: - Import Report

/// Discrepancies accumulated while importing the agent's workspace output back
/// into the model graph. Surfaced on the completion card so partial imports are
/// never silent.
struct RevisionImportReport {
    /// Section files that could not be imported (unreadable, malformed, or not
    /// matching any exported section).
    var sectionsSkipped: [String] = []
    /// Imported node ids that matched nothing in the resume tree.
    var unmatchedIds: [String] = []
    /// Value edits the agent attempted on nodes that are not editable.
    var blockedEdits: [String] = []
    /// Node creations blocked because the parent is not editable.
    var blockedCreations: [String] = []
    /// Editable list children removed because the agent omitted them.
    var prunedNodes: [String] = []
    /// Nodes the user edited in the main window mid-session that intersected
    /// with the agent's output.
    var manualEditConflicts: [String] = []

    var isEmpty: Bool {
        sectionsSkipped.isEmpty
            && unmatchedIds.isEmpty
            && blockedEdits.isEmpty
            && blockedCreations.isEmpty
            && prunedNodes.isEmpty
            && manualEditConflicts.isEmpty
    }

    var summaryText: String {
        var lines: [String] = []
        func add(_ title: String, _ items: [String]) {
            guard !items.isEmpty else { return }
            lines.append("\(title) (\(items.count)):")
            lines.append(contentsOf: items.map { "  • \($0)" })
        }
        add("Sections skipped", sectionsSkipped)
        add("Unmatched node ids", unmatchedIds)
        add("Edits blocked (non-editable)", blockedEdits)
        add("Node creations blocked", blockedCreations)
        add("Nodes removed (omitted from revision)", prunedNodes)
        add("Mid-session edit conflicts", manualEditConflicts)
        return lines.joined(separator: "\n")
    }
}

/// Manages an ephemeral filesystem workspace for the resume revision agent.
/// Pattern: CardMergeWorkspaceService — create → export → agent loop → import → delete.
@MainActor
final class ResumeRevisionWorkspaceService {

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    /// Base directory override for tests. When nil, the default Application
    /// Support location is used.
    private let baseDirectoryOverride: URL?

    /// Workspace directory path (per-session: revision-workspace/<UUID>/)
    private(set) var workspacePath: URL?

    /// IDs of nodes that were marked editable at export time.
    /// These are the only nodes the agent was actually handed; import-time
    /// authorization additionally re-derives editability from the live resume.
    private(set) var editableNodeIDs: Set<String> = []

    /// Report describing discrepancies from the most recent import/build.
    private(set) var lastImportReport: RevisionImportReport?

    /// Maps exported file slug → original section node id, so import resolves
    /// sections robustly even when two section names sanitize identically.
    private var sectionSlugToNodeID: [String: String] = [:]

    /// Report accumulated across importRevisedTreeNodes → buildNewResume.
    private var workingReport: RevisionImportReport?

    init(baseDirectory: URL? = nil) {
        self.baseDirectoryOverride = baseDirectory
    }

    // MARK: - Computed Paths

    private var treenodesPath: URL? { workspacePath?.appendingPathComponent("treenodes") }
    private var knowledgeCardsPath: URL? { workspacePath?.appendingPathComponent("knowledge_cards") }
    private var writingSamplesPath: URL? { workspacePath?.appendingPathComponent("writing_samples") }
    /// Pristine copies of the exported treenode JSON. The write tool's allowlist
    /// does not permit writing here, so these stay byte-identical to the export
    /// and are used at import to detect mid-session manual edits.
    private var snapshotsPath: URL? { workspacePath?.appendingPathComponent("snapshots") }
    private var manifestPath: URL? { workspacePath?.appendingPathComponent("manifest.txt") }

    // MARK: - Workspace Lifecycle

    /// Creates a fresh per-session workspace directory under
    /// `revision-workspace/<UUID>/`, sweeping any stale sibling session
    /// directories left behind by previous sessions.
    func createWorkspace() throws -> URL {
        let baseDir: URL
        if let baseDirectoryOverride {
            baseDir = baseDirectoryOverride
        } else {
            guard let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first else {
                throw WorkspaceError.workspaceCreationFailed("Could not locate the Application Support directory")
            }
            baseDir = appSupport
                .appendingPathComponent("Sprung")
                .appendingPathComponent("revision-workspace")
        }

        // Sweep stale session directories (and any legacy fixed-path layout)
        // so an orphaned session can never corrupt — or be corrupted by — this one.
        if FileManager.default.fileExists(atPath: baseDir.path) {
            let staleItems: [URL]
            do {
                staleItems = try FileManager.default.contentsOfDirectory(at: baseDir, includingPropertiesForKeys: nil)
            } catch {
                throw WorkspaceError.workspaceCreationFailed(
                    "Could not enumerate existing revision workspaces: \(error.localizedDescription)"
                )
            }
            for item in staleItems {
                do {
                    try FileManager.default.removeItem(at: item)
                } catch {
                    Logger.warning(
                        "Could not remove stale revision workspace item '\(item.lastPathComponent)': \(error.localizedDescription)",
                        category: .ai
                    )
                }
            }
            if !staleItems.isEmpty {
                Logger.info("Swept \(staleItems.count) stale revision workspace item(s)", category: .ai)
            }
        }

        let session = baseDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
        for subdir in ["treenodes", "knowledge_cards", "writing_samples", "snapshots"] {
            let dir = session.appendingPathComponent(subdir)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        workspacePath = session
        Logger.info("Created revision workspace at \(session.path)", category: .ai)
        return session
    }

    /// Deletes only the current session directory. Tolerates an already-missing
    /// directory; never touches sibling sessions.
    func deleteWorkspace() throws {
        guard let workspace = workspacePath else { return }

        if FileManager.default.fileExists(atPath: workspace.path) {
            try FileManager.default.removeItem(at: workspace)
            Logger.info("Deleted revision workspace", category: .ai)
        }

        workspacePath = nil
    }

    // MARK: - Export: Resume PDF

    /// Render the full resume PDF (all fields, locked + unlocked) and write to workspace.
    func exportResumePDF(resume: Resume, pdfGenerator: NativePDFGenerator) async throws {
        guard let workspace = workspacePath else {
            throw WorkspaceError.workspaceNotCreated
        }

        let template = try pdfGenerator.resolveTemplate(for: resume)
        let pdfData = try await pdfGenerator.generatePDF(for: resume, template: template.slug)
        let pdfFile = workspace.appendingPathComponent("resume.pdf")
        try pdfData.write(to: pdfFile)

        Logger.info("Exported resume PDF (\(pdfData.count) bytes)", category: .ai)
    }

    // MARK: - Export: Modifiable TreeNodes

    /// Export AI-modifiable treenode subtrees to the workspace as per-section JSON files.
    /// Writes a pristine snapshot of each file to the protected snapshot area and
    /// returns a manifest describing exported sections and target page count.
    func exportModifiableTreeNodes(from resume: Resume) throws -> WorkspaceManifest {
        guard let treenodesDir = treenodesPath, let snapshotsDir = snapshotsPath else {
            throw WorkspaceError.workspaceNotCreated
        }

        guard let root = resume.rootNode else {
            throw WorkspaceError.invalidResumeData("Resume has no root node")
        }

        var sectionMeta: [WorkspaceManifest.SectionInfo] = []
        var usedSlugs: Set<String> = []

        editableNodeIDs = []
        sectionSlugToNodeID = [:]

        // Walk top-level section children of root
        for section in root.orderedChildren {
            let editableRoots = collectEditableRoots(from: section)
            guard !editableRoots.isEmpty else { continue }

            let sectionName = section.name.isEmpty ? section.displayLabel : section.name
            var sanitized = sectionName.lowercased()
                .replacingOccurrences(of: " ", with: "_")
                .filter { $0.isLetter || $0.isNumber || $0 == "_" }
            if sanitized.isEmpty { sanitized = "section" }

            // Dedupe slugs so two sections can never collide on one file.
            var slug = sanitized
            var suffix = 2
            while usedSlugs.contains(slug) {
                slug = "\(sanitized)_\(suffix)"
                suffix += 1
            }
            usedSlugs.insert(slug)
            sectionSlugToNodeID[slug] = section.id

            // Serialize only the editable subtrees
            let nodeArray = editableRoots.map { $0.toRevisionDictionary() }
            let jsonData = try JSONSerialization.data(withJSONObject: nodeArray, options: [.prettyPrinted, .sortedKeys])
            try jsonData.write(to: treenodesDir.appendingPathComponent("\(slug).json"))
            // Pristine snapshot — the write tool cannot touch this area, so it
            // stays byte-identical to the export for mid-session-edit detection.
            try jsonData.write(to: snapshotsDir.appendingPathComponent("\(slug).json"))

            sectionMeta.append(WorkspaceManifest.SectionInfo(
                name: sectionName,
                file: "treenodes/\(slug).json",
                nodeCount: editableRoots.count
            ))
        }

        // Resolve page limit from template manifest
        let pageLimit: Int?
        if let template = resume.template {
            let manifest = TemplateManifestDefaults.manifest(for: template)
            pageLimit = manifest.pageLimit
        } else {
            pageLimit = nil
        }

        let manifest = WorkspaceManifest(
            sections: sectionMeta,
            targetPageCount: pageLimit
        )

        // Write manifest
        if let manifestFile = manifestPath {
            let manifestData = try encoder.encode(manifest)
            try manifestData.write(to: manifestFile)
        }

        Logger.info("Exported \(sectionMeta.count) sections with modifiable treenodes", category: .ai)
        return manifest
    }

    /// Find the AI-editable root nodes within a section.
    /// Editable roots are nodes with `status == .aiToReplace`; their entire subtree is editable.
    /// Records all editable node IDs for import-time enforcement.
    private func collectEditableRoots(from section: TreeNode) -> [TreeNode] {
        var roots: [TreeNode] = []
        findEditableRoots(node: section, result: &roots)
        guard !roots.isEmpty else { return [] }
        // Record all editable IDs (roots + their entire subtrees, excluding group-excluded nodes)
        for root in roots {
            recordEditableIDs(node: root)
        }
        return roots
    }

    /// Walk the tree to find AI-editable subtree roots.
    /// A root is any node with `status == .aiToReplace`; its entire subtree is editable.
    private func findEditableRoots(node: TreeNode, result: inout [TreeNode]) {
        if node.status == .aiToReplace {
            result.append(node)
            return // Entire subtree is editable
        }
        for child in node.orderedChildren {
            findEditableRoots(node: child, result: &result)
        }
    }

    /// Record a node and all its descendants as editable.
    /// Skips children with `.excludedFromGroup` status (user excluded them from AI review).
    private func recordEditableIDs(node: TreeNode) {
        guard node.status != .excludedFromGroup else { return }
        editableNodeIDs.insert(node.id)
        for child in node.orderedChildren {
            recordEditableIDs(node: child)
        }
    }

    // MARK: - Export: Job Description

    func exportJobDescription(_ text: String) throws {
        guard let workspace = workspacePath else {
            throw WorkspaceError.workspaceNotCreated
        }

        let file = workspace.appendingPathComponent("job_description.txt")
        try Self.wrapText(text).write(to: file, atomically: true, encoding: .utf8)
        Logger.info("Exported job description (\(text.count) chars)", category: .ai)
    }

    // MARK: - Export: Job Metadata

    /// Export the structured job listing metadata (title, company, location,
    /// seniority, salary, …) so the agent sees more than the raw description.
    func exportJobMetadata(for jobApp: JobApp) throws {
        guard let workspace = workspacePath else {
            throw WorkspaceError.workspaceNotCreated
        }

        var lines: [String] = ["# Job Listing Metadata", ""]
        func add(_ label: String, _ value: String) {
            guard !value.isEmpty else { return }
            lines.append("- \(label): \(value)")
        }
        add("Position", jobApp.jobPosition)
        add("Company", jobApp.companyName)
        add("Location", jobApp.jobLocation)
        add("Seniority Level", jobApp.seniorityLevel)
        add("Employment Type", jobApp.employmentType)
        add("Job Function", jobApp.jobFunction)
        add("Industries", jobApp.industries)
        add("Salary", jobApp.salary)
        add("Posted", jobApp.jobPostingTime)

        let file = workspace.appendingPathComponent("job_metadata.txt")
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        Logger.info("Exported job metadata", category: .ai)
    }

    // MARK: - Export: Job Requirements

    /// Export the preprocessed, tiered job requirements. Returns whether the
    /// file was written — skipped (with a log) when preprocessing has not
    /// produced results for this job yet, so prompt construction can avoid
    /// pointing the agent at a file that does not exist.
    @discardableResult
    func exportJobRequirements(_ requirements: ExtractedRequirements?) throws -> Bool {
        guard let workspace = workspacePath else {
            throw WorkspaceError.workspaceNotCreated
        }

        guard let requirements, requirements.isValid else {
            Logger.info("No preprocessed job requirements to export", category: .ai)
            return false
        }

        var lines: [String] = [
            "# Job Requirements (extracted from the posting, tiered by priority)",
            ""
        ]
        func addTier(_ title: String, _ items: [String]) {
            guard !items.isEmpty else { return }
            lines.append("## \(title)")
            lines.append(contentsOf: items.map { Self.wrapText("- \($0)") })
            lines.append("")
        }
        addTier("Must Have (explicitly required)", requirements.mustHave)
        addTier("Strong Signal (emphasized or repeated)", requirements.strongSignal)
        addTier("Preferred (nice to have)", requirements.preferred)
        addTier("Cultural / Soft Skills", requirements.cultural)

        let file = workspace.appendingPathComponent("job_requirements.txt")
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        Logger.info("Exported tiered job requirements", category: .ai)
        return true
    }

    // MARK: - Export: Knowledge Cards

    /// Export each card as readable Markdown (the agent's read tool truncates
    /// long lines, so single-line Codable JSON is unreadable to it) and write
    /// an overview ordered by job relevance: cards flagged relevant during
    /// preprocessing come first, but ALL cards are listed — curation is by
    /// ordering, never exclusion.
    func exportKnowledgeCards(_ cards: [KnowledgeCard], relevantCardIds: [String]?) throws {
        guard let cardsDir = knowledgeCardsPath, let workspace = workspacePath else {
            throw WorkspaceError.workspaceNotCreated
        }

        let relevantIds = Set((relevantCardIds ?? []).map { $0.lowercased() })
        let relevant = cards.filter { relevantIds.contains($0.id.uuidString.lowercased()) }
        let remaining = cards.filter { !relevantIds.contains($0.id.uuidString.lowercased()) }
        let ordered = relevant + remaining

        for card in cards {
            let cardFile = cardsDir.appendingPathComponent("\(card.id.uuidString).txt")
            try renderCardMarkdown(card).write(to: cardFile, atomically: true, encoding: .utf8)
        }

        // Write overview, relevance-ordered
        var overviewLines: [String] = ["# Knowledge Cards Overview", ""]
        if !relevant.isEmpty {
            overviewLines.append(
                "Cards marked RELEVANT were identified as relevant to this job during "
                + "preprocessing and are listed first. All cards remain available."
            )
            overviewLines.append("")
        }
        for card in ordered {
            let type = card.cardType?.displayName ?? "General"
            let org = card.organization ?? ""
            let dates = card.dateRange ?? ""
            let preview = card.narrative
                .replacingOccurrences(of: "\n", with: " ")
                .prefix(200)
            let isRelevant = relevantIds.contains(card.id.uuidString.lowercased())
            overviewLines.append("## \(card.title)\(isRelevant ? " [RELEVANT TO THIS JOB]" : "")")
            overviewLines.append("- File: knowledge_cards/\(card.id.uuidString).txt")
            overviewLines.append("- Type: \(type)")
            if !org.isEmpty { overviewLines.append("- Organization: \(org)") }
            if !dates.isEmpty { overviewLines.append("- Date Range: \(dates)") }
            overviewLines.append(Self.wrapText("- Narrative: \(preview)..."))
            overviewLines.append("")
        }

        let overviewFile = workspace.appendingPathComponent("knowledge_cards_overview.txt")
        try overviewLines.joined(separator: "\n").write(to: overviewFile, atomically: true, encoding: .utf8)

        Logger.info("Exported \(cards.count) knowledge cards (\(relevant.count) flagged relevant)", category: .ai)
    }

    /// Render a knowledge card as readable Markdown: header metadata, wrapped
    /// narrative, and decoded enrichment fields as bullet lists. Modeled on how
    /// CardVerificationPrompts.renderCards presents cards to the onboarding auditor.
    private func renderCardMarkdown(_ card: KnowledgeCard) -> String {
        var lines: [String] = ["# \(card.title)", ""]

        lines.append("- Type: \(card.cardType?.displayName ?? "General")")
        if let org = card.organization, !org.isEmpty {
            lines.append("- Organization: \(org)")
        }
        if let dates = card.dateRange, !dates.isEmpty {
            lines.append("- Date Range: \(dates)")
        }
        if let location = card.location, !location.isEmpty {
            lines.append("- Location: \(location)")
        }
        if let quality = card.evidenceQuality, !quality.isEmpty {
            lines.append("- Evidence Quality: \(quality)")
        }

        if !card.narrative.isEmpty {
            lines.append("")
            lines.append("## Narrative")
            lines.append("")
            lines.append(Self.wrapText(card.narrative))
        }

        let facts = card.facts
        if !facts.isEmpty {
            lines.append("")
            lines.append("## Facts")
            lines.append("")
            for fact in facts {
                lines.append(Self.wrapText("- [\(fact.category)] \(fact.statement)"))
            }
        }

        let bullets = card.suggestedBullets
        if !bullets.isEmpty {
            lines.append("")
            lines.append("## Suggested Resume Bullets")
            lines.append("")
            for bullet in bullets {
                lines.append(Self.wrapText("- \(bullet)"))
            }
        }

        let technologies = card.technologies
        if !technologies.isEmpty {
            lines.append("")
            lines.append("## Technologies")
            lines.append("")
            lines.append(Self.wrapText(technologies.joined(separator: ", ")))
        }

        let outcomes = card.outcomes
        if !outcomes.isEmpty {
            lines.append("")
            lines.append("## Outcomes")
            lines.append("")
            for outcome in outcomes {
                lines.append(Self.wrapText("- \(outcome)"))
            }
        }

        let excerpts = card.verbatimExcerpts
        if !excerpts.isEmpty {
            lines.append("")
            lines.append("## Verbatim Excerpts (author's own voice)")
            for excerpt in excerpts {
                lines.append("")
                lines.append("### \(excerpt.context)")
                if !excerpt.location.isEmpty {
                    lines.append("- Source: \(excerpt.location)")
                }
                lines.append("")
                lines.append(Self.wrapText(excerpt.text))
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Export: Skill Bank

    func exportSkillBank(_ skills: [Skill]) throws {
        guard let workspace = workspacePath else {
            throw WorkspaceError.workspaceNotCreated
        }

        let categories = SkillCategoryUtils.sortedCategories(from: skills)
        var lines: [String] = ["# Skill Bank", ""]

        for category in categories {
            lines.append("## \(category)")
            let categorySkills = skills
                .filter { SkillCategoryUtils.normalizeCategory($0.categoryRaw) == category }
                .sorted { $0.canonical < $1.canonical }

            for skill in categorySkills {
                let proficiency = skill.proficiencyRaw.capitalized
                let variants = skill.atsVariants
                var line = "- \(skill.canonical) (\(proficiency))"
                if !variants.isEmpty {
                    line += " — ATS: \(variants.joined(separator: ", "))"
                }
                lines.append(line)
            }
            lines.append("")
        }

        let file = workspace.appendingPathComponent("skill_bank.txt")
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)

        Logger.info("Exported \(skills.count) skills across \(categories.count) categories", category: .ai)
    }

    // MARK: - Export: Voice Materials

    /// What the voice export actually wrote, so prompt construction can key off
    /// the same selection the workspace contains.
    struct VoiceExportSummary {
        let samplesExported: Int
        let voiceProfileExported: Bool
    }

    /// Export the user's voice materials: the writing samples selected by the
    /// canonical writer's-voice criteria (same selection as
    /// `CoverRefStore.writersVoice` — enabled-by-default samples, capped at 3)
    /// and the distilled voice primer as `voice_profile.txt`.
    @discardableResult
    func exportVoiceMaterials(_ coverRefs: [CoverRef]) throws -> VoiceExportSummary {
        guard let samplesDir = writingSamplesPath, let workspace = workspacePath else {
            throw WorkspaceError.workspaceNotCreated
        }

        // Canonical selection — the same helper CoverRefStore.writersVoice uses.
        let samples = CoverRefStore.voiceSamples(in: coverRefs)
        let primer = coverRefs.first { $0.type == .voicePrimer }

        for sample in samples {
            let slugName = sample.name.lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .filter { $0.isLetter || $0.isNumber || $0 == "-" }
            let file = samplesDir.appendingPathComponent("\(slugName).txt")
            try Self.wrapText(sample.content).write(to: file, atomically: true, encoding: .utf8)
        }

        var profileExported = false
        if let primer {
            let profileFile = workspace.appendingPathComponent("voice_profile.txt")
            try renderVoiceProfile(primer).write(to: profileFile, atomically: true, encoding: .utf8)
            profileExported = true
        }

        Logger.info(
            "Exported \(samples.count) writing samples"
                + (profileExported ? " and the voice profile" : ""),
            category: .ai
        )
        return VoiceExportSummary(samplesExported: samples.count, voiceProfileExported: profileExported)
    }

    /// Render the distilled voice primer (summary + structured analysis) as
    /// readable Markdown.
    private func renderVoiceProfile(_ primer: CoverRef) -> String {
        var lines: [String] = ["# Voice Profile", ""]

        if !primer.content.isEmpty {
            lines.append(Self.wrapText(primer.content))
        }

        if let analysis = primer.voicePrimer {
            func add(_ label: String, _ value: String?) {
                guard let value, !value.isEmpty else { return }
                lines.append("")
                lines.append("## \(label)")
                lines.append(Self.wrapText(value))
            }
            add("Tone", analysis["tone"]["description"].string)
            add("Sentence Structure", analysis["structure"]["description"].string)
            add("Vocabulary", analysis["vocabulary"]["description"].string)
            add("Rhetoric Style", analysis["rhetoric"]["description"].string)

            func addList(_ label: String, _ values: [String]) {
                guard !values.isEmpty else { return }
                lines.append("")
                lines.append("## \(label)")
                lines.append(contentsOf: values.map { Self.wrapText("- \($0)") })
            }
            addList("Writing Strengths", analysis["markers"]["strengths"].arrayValue.compactMap(\.string))
            addList("Distinctive Traits", analysis["markers"]["quirks"].arrayValue.compactMap(\.string))
            addList("Style Notes", analysis["markers"]["recommendations"].arrayValue.compactMap(\.string))
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Text Wrapping

    /// Wrap text to readable line lengths for the agent's line-oriented read
    /// tool (it truncates long lines and paginates by line index). Existing
    /// newlines are preserved; each line is word-wrapped at `width` columns.
    static func wrapText(_ text: String, width: Int = 100) -> String {
        text.components(separatedBy: "\n")
            .map { wrapLine($0, width: width) }
            .joined(separator: "\n")
    }

    private static func wrapLine(_ line: String, width: Int) -> String {
        guard line.count > width else { return line }
        var wrapped: [String] = []
        var current = ""
        for word in line.split(separator: " ") {
            if current.isEmpty {
                current = String(word)
            } else if current.count + 1 + word.count <= width {
                current += " \(word)"
            } else {
                wrapped.append(current)
                current = String(word)
            }
        }
        if !current.isEmpty { wrapped.append(current) }
        return wrapped.joined(separator: "\n")
    }

    // MARK: - Export: Font Size Nodes

    func exportFontSizeNodes(_ nodes: [FontSizeNode]) throws {
        guard let workspace = workspacePath else {
            throw WorkspaceError.workspaceNotCreated
        }

        guard !nodes.isEmpty else {
            Logger.info("No font size nodes to export", category: .ai)
            return
        }

        let sortedNodes = nodes.sorted(by: { $0.index < $1.index })
        let jsonArray = sortedNodes.map { node -> [String: Any] in
            ["key": node.key, "fontString": node.fontString, "index": node.index]
        }

        let jsonData = try JSONSerialization.data(withJSONObject: jsonArray, options: [.prettyPrinted, .sortedKeys])
        let file = workspace.appendingPathComponent("fontsizenodes.json")
        try jsonData.write(to: file)

        Logger.info("Exported \(nodes.count) font size nodes", category: .ai)
    }

    // MARK: - Export: Title Sets

    func exportTitleSets(_ titleSets: [TitleSetRecord]) throws {
        guard let workspace = workspacePath else {
            throw WorkspaceError.workspaceNotCreated
        }

        guard !titleSets.isEmpty else {
            Logger.info("No title sets to export", category: .ai)
            return
        }

        var lines: [String] = ["# Title Sets Library", ""]
        for (index, record) in titleSets.enumerated() {
            lines.append("\(index + 1). \(record.displayString)")
        }

        let file = workspace.appendingPathComponent("title_sets.txt")
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)

        Logger.info("Exported \(titleSets.count) title sets", category: .ai)
    }

    // MARK: - Import: Revised Font Sizes

    /// Read fontsizenodes.json from the workspace and return parsed entries.
    func importRevisedFontSizes() throws -> [[String: Any]]? {
        guard let workspace = workspacePath else {
            throw WorkspaceError.workspaceNotCreated
        }

        let file = workspace.appendingPathComponent("fontsizenodes.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }

        let data = try Data(contentsOf: file)
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }

        return array.isEmpty ? nil : array
    }

    // MARK: - Import: Revised TreeNodes

    /// Read all treenode JSON files from the workspace.
    /// Returns a dictionary keyed by section slug, each containing an array of node dictionaries.
    /// Unreadable or malformed sections are skipped and recorded in the import report.
    func importRevisedTreeNodes() throws -> [String: [[String: Any]]] {
        guard let treenodesDir = treenodesPath else {
            throw WorkspaceError.workspaceNotCreated
        }

        var report = RevisionImportReport()

        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: treenodesDir,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var result: [String: [[String: Any]]] = [:]

        for fileURL in fileURLs {
            let sectionName = fileURL.deletingPathExtension().lastPathComponent

            let nodes: [[String: Any]]
            do {
                let data = try Data(contentsOf: fileURL)
                guard let parsed = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                    Logger.warning("Failed to parse treenode file: \(fileURL.lastPathComponent)", category: .ai)
                    report.sectionsSkipped.append("\(sectionName) (not a JSON array of nodes)")
                    continue
                }
                nodes = parsed
            } catch {
                Logger.warning("Failed to read treenode file \(fileURL.lastPathComponent): \(error.localizedDescription)", category: .ai)
                report.sectionsSkipped.append("\(sectionName) (unreadable: \(error.localizedDescription))")
                continue
            }

            // Validate required fields; a malformed section is skipped (and
            // reported), not allowed to abort the entire import.
            let requiredFields: Set<String> = ["id", "name", "value", "myIndex", "children"]
            var malformedReason: String?
            for (index, node) in nodes.enumerated() {
                let missing = requiredFields.subtracting(Set(node.keys))
                if !missing.isEmpty {
                    malformedReason = "node \(index) missing: \(missing.sorted().joined(separator: ", "))"
                    break
                }
            }
            if let malformedReason {
                Logger.warning("Skipping malformed treenode file \(fileURL.lastPathComponent): \(malformedReason)", category: .ai)
                report.sectionsSkipped.append("\(sectionName) (\(malformedReason))")
                continue
            }

            result[sectionName] = nodes
        }

        workingReport = report
        Logger.info("Imported revised treenodes from \(result.count) sections", category: .ai)
        return result
    }

    // MARK: - Build New Resume

    /// Create a new Resume by cloning the original and applying revised treenode values and font sizes.
    /// Populates `lastImportReport` with every discrepancy encountered.
    func buildNewResume(
        from original: Resume,
        revisedNodes: [String: [[String: Any]]],
        revisedFontSizes: [[String: Any]]? = nil,
        context: ModelContext
    ) throws -> Resume {
        guard let jobApp = original.jobApp else {
            throw WorkspaceError.invalidResumeData("The original resume is no longer linked to a job application")
        }
        guard let originalRoot = original.rootNode else {
            throw WorkspaceError.invalidResumeData("The original resume has no content tree")
        }

        var report = workingReport ?? RevisionImportReport()
        workingReport = nil

        // Re-derive editability from the live resume NOW so mid-session status
        // toggles in the main window are honored at import time.
        var currentEditableIDs: Set<String> = []
        recordCurrentEditableIDs(node: originalRoot, inheritedEditable: false, into: &currentEditableIDs)

        // Pristine export snapshots, used to detect mid-session manual edits.
        let snapshotValues = loadSnapshotValues()

        let newResume = Resume(
            jobApp: jobApp,
            enabledSources: original.enabledSources,
            template: original.template
        )
        context.insert(newResume)

        // Deep-clone the original tree. Clones receive fresh ids; the maps tie
        // workspace ids (original-resume namespace) to their clones.
        var cloneByOriginalID: [String: TreeNode] = [:]
        var originalIDByCloneID: [String: String] = [:]
        let clonedRoot = deepCloneTreeNode(
            originalRoot,
            for: newResume,
            context: context,
            cloneByOriginalID: &cloneByOriginalID,
            originalIDByCloneID: &originalIDByCloneID
        )
        newResume.rootNode = clonedRoot

        // Apply revised values, resolving each file via the export slug map.
        for (slug, nodes) in revisedNodes.sorted(by: { $0.key < $1.key }) {
            guard let sectionOriginalID = sectionSlugToNodeID[slug],
                  let sectionClone = cloneByOriginalID[sectionOriginalID] else {
                Logger.warning("Treenode file '\(slug).json' does not match any exported section", category: .ai)
                report.sectionsSkipped.append("\(slug) (no matching exported section)")
                continue
            }

            applyRevisedNodes(
                nodes,
                parentClone: sectionClone,
                parentOriginalID: sectionOriginalID,
                reorderSiblings: false,
                cloneByOriginalID: cloneByOriginalID,
                currentEditableIDs: currentEditableIDs,
                snapshotValues: snapshotValues,
                resume: newResume,
                context: context,
                report: &report
            )

            // Remove editable LIST children the agent deleted by omission.
            let retainedIDs = collectAllRevisionIDs(from: nodes)
            pruneAbsentEditableNodes(
                from: sectionClone,
                retainedIDs: retainedIDs,
                currentEditableIDs: currentEditableIDs,
                originalIDByCloneID: originalIDByCloneID,
                context: context,
                report: &report
            )
        }

        // Apply revised font sizes
        if let revisedFontSizes = revisedFontSizes {
            var clonedFontNodes: [FontSizeNode] = []
            for entry in revisedFontSizes {
                guard let key = entry["key"] as? String,
                      let fontString = entry["fontString"] as? String else { continue }
                let index = entry["index"] as? Int ?? 0
                let node = FontSizeNode(key: key, index: index, fontString: fontString, resume: newResume)
                context.insert(node)
                clonedFontNodes.append(node)
            }
            newResume.fontSizeNodes = clonedFontNodes
        } else {
            // Clone original font size nodes
            for node in original.fontSizeNodes {
                let cloned = FontSizeNode(key: node.key, index: node.index, fontString: node.fontString, resume: newResume)
                context.insert(cloned)
                newResume.fontSizeNodes.append(cloned)
            }
        }

        // Copy metadata from original
        newResume.keyLabels = original.keyLabels
        newResume.sectionVisibilityOverrides = original.sectionVisibilityOverrides
        newResume.importedEditorKeys = original.importedEditorKeys

        lastImportReport = report
        if !report.isEmpty {
            Logger.warning("RevisionAgent import discrepancies:\n\(report.summaryText)", category: .ai)
        }

        return newResume
    }

    /// Deep-clone a TreeNode tree for a new resume.
    /// Clones are minted with fresh ids — TreeNode ids are never duplicated
    /// across resumes. The maps record original-id ↔ clone correspondence for
    /// import matching.
    private func deepCloneTreeNode(
        _ node: TreeNode,
        for resume: Resume,
        context: ModelContext,
        cloneByOriginalID: inout [String: TreeNode],
        originalIDByCloneID: inout [String: String]
    ) -> TreeNode {
        let clone = TreeNode(
            name: node.name,
            value: node.value,
            children: nil,
            parent: nil,
            inEditor: node.includeInEditor,
            status: node.status,
            resume: resume,
            isTitleNode: node.isTitleNode
        )
        clone.myIndex = node.myIndex
        clone.editorLabel = node.editorLabel
        clone.copySchemaMetadata(from: node)
        context.insert(clone)
        cloneByOriginalID[node.id] = clone
        originalIDByCloneID[clone.id] = node.id

        for child in node.orderedChildren {
            let childClone = deepCloneTreeNode(
                child,
                for: resume,
                context: context,
                cloneByOriginalID: &cloneByOriginalID,
                originalIDByCloneID: &originalIDByCloneID
            )
            clone.addChild(childClone)
            // Preserve the original sibling ordering exactly.
            childClone.myIndex = child.myIndex
        }

        return clone
    }

    /// Walk the original tree recording every node that is editable RIGHT NOW:
    /// a node marked `.aiToReplace`, or any descendant of one. An
    /// `.excludedFromGroup` node blocks inheritance (it and its unmarked
    /// descendants are not editable), but an explicit `.aiToReplace` mark
    /// deeper down still counts — exclusion stops inheritance, not direct
    /// selection. Mirrors `TreeNode.hasAncestorWithAIStatus`.
    private func recordCurrentEditableIDs(
        node: TreeNode,
        inheritedEditable: Bool,
        into ids: inout Set<String>
    ) {
        let editable: Bool
        if node.status == .excludedFromGroup {
            editable = false
        } else {
            editable = inheritedEditable || node.status == .aiToReplace
        }
        if editable { ids.insert(node.id) }
        for child in node.orderedChildren {
            recordCurrentEditableIDs(node: child, inheritedEditable: editable, into: &ids)
        }
    }

    /// Load original values from the protected export snapshots, keyed by node id.
    private func loadSnapshotValues() -> [String: String] {
        guard let snapshotsDir = snapshotsPath else { return [:] }
        var values: [String: String] = [:]

        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: snapshotsDir, includingPropertiesForKeys: nil)
        } catch {
            Logger.warning("Could not enumerate export snapshots: \(error.localizedDescription)", category: .ai)
            return [:]
        }

        for file in files where file.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: file)
                if let nodes = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    collectSnapshotValues(from: nodes, into: &values)
                }
            } catch {
                Logger.warning("Could not read export snapshot \(file.lastPathComponent): \(error.localizedDescription)", category: .ai)
            }
        }
        return values
    }

    private func collectSnapshotValues(from nodes: [[String: Any]], into values: inout [String: String]) {
        for node in nodes {
            if let id = node["id"] as? String, let value = node["value"] as? String {
                values[id] = value
            }
            if let children = node["children"] as? [[String: Any]] {
                collectSnapshotValues(from: children, into: &values)
            }
        }
    }

    /// Apply revised node dictionaries to the cloned tree.
    ///
    /// - Existing nodes are matched globally via `cloneByOriginalID` (the
    ///   top-level array may contain editable roots from different depths).
    /// - Only nodes editable at import time receive value changes; blocked
    ///   edits are recorded in the report.
    /// - `new-` ids materialize as fresh nodes — but only under an editable
    ///   parent. The sentinel namespace lives only inside one workspace
    ///   lifetime and is never persisted.
    /// - When `reorderSiblings` is true (recursive sibling arrays under an
    ///   editable parent), the array order is authoritative for `myIndex`.
    private func applyRevisedNodes(
        _ revisions: [[String: Any]],
        parentClone: TreeNode,
        parentOriginalID: String?,
        reorderSiblings: Bool,
        cloneByOriginalID: [String: TreeNode],
        currentEditableIDs: Set<String>,
        snapshotValues: [String: String],
        resume: Resume,
        context: ModelContext,
        report: inout RevisionImportReport
    ) {
        var orderedParticipants: [TreeNode] = []
        var matchedExisting: [TreeNode] = []

        for revision in revisions {
            guard let nodeId = revision["id"] as? String, !nodeId.isEmpty else {
                report.unmatchedIds.append("(missing id)")
                continue
            }

            if nodeId.hasPrefix("new-") {
                let parentEditable = parentOriginalID.map { currentEditableIDs.contains($0) } ?? false
                guard parentEditable else {
                    report.blockedCreations.append(describeRevision(revision, fallback: nodeId))
                    Logger.warning(
                        "RevisionAgent: Blocked creation of '\(nodeId)' under non-editable parent '\(parentClone.name)'",
                        category: .ai
                    )
                    continue
                }
                let newNode = createTreeNodeFromDictionary(revision, resume: resume, context: context)
                parentClone.addChild(newNode)
                orderedParticipants.append(newNode)
                continue
            }

            guard let clone = cloneByOriginalID[nodeId] else {
                report.unmatchedIds.append(nodeId)
                Logger.warning("RevisionAgent: No node matches imported id '\(nodeId)'", category: .ai)
                continue
            }

            let isEditable = currentEditableIDs.contains(nodeId)
            if isEditable {
                applyValue(revision, to: clone, originalID: nodeId, snapshotValues: snapshotValues, report: &report)
                if let isTitleNode = revision["isTitleNode"] as? Bool {
                    clone.isTitleNode = isTitleNode
                }
                if clone.parent === parentClone {
                    orderedParticipants.append(clone)
                    matchedExisting.append(clone)
                }
            } else if let value = revision["value"] as? String, value != clone.value {
                report.blockedEdits.append(nodeLabel(clone))
                Logger.warning("RevisionAgent: Skipped edit to non-editable node '\(nodeId)' (\(clone.name))", category: .ai)
            }

            // Always recurse into children — some children may be editable even if parent isn't
            if let children = revision["children"] as? [[String: Any]] {
                applyRevisedNodes(
                    children,
                    parentClone: clone,
                    parentOriginalID: nodeId,
                    reorderSiblings: true,
                    cloneByOriginalID: cloneByOriginalID,
                    currentEditableIDs: currentEditableIDs,
                    snapshotValues: snapshotValues,
                    resume: resume,
                    context: context,
                    report: &report
                )
            }
        }

        // The imported sibling array order is authoritative (agent-specified
        // ordering wins) — but only inside an editable parent.
        let parentEditable = parentOriginalID.map { currentEditableIDs.contains($0) } ?? false
        if reorderSiblings, parentEditable, !orderedParticipants.isEmpty {
            reindexSiblings(orderedParticipants, matchedExisting: matchedExisting, parentClone: parentClone)
        }
    }

    /// Apply an imported value to an editable clone, detecting mid-session
    /// manual edits via the export snapshot:
    /// - User edited + agent did not change it → the manual edit is preserved.
    /// - User edited + agent rewrote it → the agent's rewrite wins.
    /// Both cases are recorded as conflicts in the report.
    private func applyValue(
        _ revision: [String: Any],
        to clone: TreeNode,
        originalID: String,
        snapshotValues: [String: String],
        report: inout RevisionImportReport
    ) {
        guard let importedValue = revision["value"] as? String else { return }
        let currentValue = clone.value

        if let snapshot = snapshotValues[originalID], snapshot != currentValue {
            // The user edited this node in the main window mid-session.
            if importedValue == snapshot {
                report.manualEditConflicts.append(
                    "\(nodeLabel(clone)): kept the edit you made during the session (the agent did not change this field)"
                )
                return
            }
            if importedValue != currentValue {
                clone.value = importedValue
                report.manualEditConflicts.append(
                    "\(nodeLabel(clone)): the agent's rewrite replaced an edit you made during the session"
                )
            }
            return
        }

        if importedValue != currentValue {
            clone.value = importedValue
        }
    }

    /// Re-assign `myIndex` so the imported array order wins, reusing the index
    /// slots previously held by the matched siblings (excluded children keep
    /// their relative positions) and extending past the maximum for additions.
    private func reindexSiblings(
        _ participants: [TreeNode],
        matchedExisting: [TreeNode],
        parentClone: TreeNode
    ) {
        var pool = matchedExisting.map(\.myIndex).sorted()
        if participants.count > pool.count {
            var next = (parentClone.children?.map(\.myIndex).max() ?? -1) + 1
            while pool.count < participants.count {
                pool.append(next)
                next += 1
            }
        }
        for (index, node) in participants.enumerated() where index < pool.count {
            node.myIndex = pool[index]
        }
    }

    /// Create a TreeNode from a revision dictionary (for new nodes).
    /// The node (and all descendants) receive fresh UUID ids — `new-` sentinel
    /// ids from the workspace are never persisted.
    private func createTreeNodeFromDictionary(
        _ dict: [String: Any],
        resume: Resume,
        context: ModelContext
    ) -> TreeNode {
        let node = TreeNode(
            name: dict["name"] as? String ?? "",
            value: dict["value"] as? String ?? "",
            children: nil,
            parent: nil,
            inEditor: true,
            status: .saved,
            resume: resume,
            isTitleNode: dict["isTitleNode"] as? Bool ?? false
        )
        context.insert(node)

        if let children = dict["children"] as? [[String: Any]] {
            for childDict in children {
                let child = createTreeNodeFromDictionary(childDict, resume: resume, context: context)
                node.addChild(child)
            }
        }

        return node
    }

    /// Recursively collect all node IDs present in a revision dictionary tree.
    private func collectAllRevisionIDs(from revisions: [[String: Any]]) -> Set<String> {
        var ids = Set<String>()
        for revision in revisions {
            if let id = revision["id"] as? String, !id.hasPrefix("new-") {
                ids.insert(id)
            }
            if let children = revision["children"] as? [[String: Any]] {
                ids.formUnion(collectAllRevisionIDs(from: children))
            }
        }
        return ids
    }

    /// Walk a cloned subtree and remove editable LIST children whose ids are
    /// absent from the revision JSON (the agent deleted them by omission).
    ///
    /// Omission-equals-deletion applies ONLY to list children — anonymous list
    /// items (highlights, keywords, courses, roles, custom list values) and
    /// entries of a top-level section collection. Omission of a named scalar
    /// field (dates, names, URLs) means UNCHANGED, never deleted.
    private func pruneAbsentEditableNodes(
        from node: TreeNode,
        retainedIDs: Set<String>,
        currentEditableIDs: Set<String>,
        originalIDByCloneID: [String: String],
        context: ModelContext,
        report: inout RevisionImportReport
    ) {
        guard let children = node.children else { return }

        let toRemove = children.filter { child in
            // Agent-created nodes from this session have no original id — never prune.
            guard let originalID = originalIDByCloneID[child.id] else { return false }
            // Only nodes the agent was actually handed at export time...
            guard editableNodeIDs.contains(originalID) else { return false }
            // ...that are still editable now (honors mid-session toggle-off)...
            guard currentEditableIDs.contains(originalID) else { return false }
            // ...and are list children, not scalar fields.
            guard isPrunableListChild(child, parent: node) else { return false }
            return !retainedIDs.contains(originalID)
        }

        for child in toRemove {
            node.children?.removeAll { $0.id == child.id }
            report.prunedNodes.append(nodeLabel(child))
            deleteSubtree(child, context: context)
            Logger.info("RevisionAgent: Pruned omitted node '\(nodeLabel(child))'", category: .ai)
        }

        // Recurse into surviving children
        for child in node.orderedChildren {
            pruneAbsentEditableNodes(
                from: child,
                retainedIDs: retainedIDs,
                currentEditableIDs: currentEditableIDs,
                originalIDByCloneID: originalIDByCloneID,
                context: context,
                report: &report
            )
        }
    }

    /// Names of top-level sections whose children are collection entries
    /// (deletable by omission). The `custom` wrapper holds named attribute
    /// containers (objective, jobTitles, …), not entries — omitting one of
    /// those means UNCHANGED, never deleted.
    private static let collectionSectionNames: Set<String> = Set(
        ExperienceSectionKey.allCases
            .filter { $0 != .custom }
            .map(\.rawValue)
    )

    /// True when omitting this child from the revision JSON may delete it:
    /// anonymous list items (highlights, keywords, courses, roles, custom list
    /// values), or entries of a top-level collection section. Named scalar
    /// fields (dates, names, URLs) and named attribute containers are never
    /// deleted by omission.
    private func isPrunableListChild(_ child: TreeNode, parent: TreeNode) -> Bool {
        if child.name.isEmpty { return true }
        let parentIsTopLevelSection = parent.parent != nil && parent.parent?.parent == nil
        return parentIsTopLevelSection
            && Self.collectionSectionNames.contains(parent.name)
            && child.hasChildren
    }

    /// Delete a node and all its descendants from the model context.
    private func deleteSubtree(_ node: TreeNode, context: ModelContext) {
        for child in node.children ?? [] {
            deleteSubtree(child, context: context)
        }
        context.delete(node)
    }

    // MARK: - Labels

    private func nodeLabel(_ node: TreeNode) -> String {
        if !node.name.isEmpty { return node.name }
        if !node.value.isEmpty { return String(node.value.prefix(60)) }
        return node.id
    }

    private func describeRevision(_ dict: [String: Any], fallback: String) -> String {
        if let name = dict["name"] as? String, !name.isEmpty { return name }
        if let value = dict["value"] as? String, !value.isEmpty { return String(value.prefix(60)) }
        return fallback
    }

    // MARK: - Errors

    enum WorkspaceError: Error, LocalizedError {
        case workspaceNotCreated
        case workspaceCreationFailed(String)
        case invalidResumeData(String)
        case invalidNodeData(String)

        var errorDescription: String? {
            switch self {
            case .workspaceNotCreated:
                return "Workspace has not been created"
            case .workspaceCreationFailed(let reason):
                return "Could not create workspace: \(reason)"
            case .invalidResumeData(let reason):
                return "Invalid resume data: \(reason)"
            case .invalidNodeData(let reason):
                return "Invalid node data: \(reason)"
            }
        }
    }
}

// MARK: - Workspace Manifest

struct WorkspaceManifest: Codable {
    struct SectionInfo: Codable {
        let name: String
        let file: String
        let nodeCount: Int
    }

    let sections: [SectionInfo]
    let targetPageCount: Int?
}
