import Foundation
import SwiftData

// MARK: - Material Exporter

/// Renders the resume model graph (treenodes, job context, knowledge cards,
/// skill bank, voice materials, font sizes, title sets) into the per-session
/// workspace files the revision agent reads. Operates on a guaranteed
/// `RevisionWorkspaceLayout`; the lifecycle owner creates it once the workspace
/// exists. Stateless beyond the layout — `exportModifiableTreeNodes` returns the
/// editable-node contract (`RevisionExportManifest`) instead of stashing it.
@MainActor
struct RevisionMaterialExporter {

    let layout: RevisionWorkspaceLayout

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    // MARK: - Export: Resume PDF

    /// Render the full resume PDF (all fields, locked + unlocked), write it to
    /// the workspace, and seed `render_info.json` with the initial page count.
    /// Returns that page count; when it cannot be determined, returns 0 and the
    /// metadata carries the honest "unavailable" marker — never a fake count.
    func exportResumePDF(resume: Resume, pdfGenerator: NativePDFGenerator) async throws -> Int {
        let pdfData: Data
        do {
            let template = try pdfGenerator.resolveTemplate(for: resume)
            pdfData = try await pdfGenerator.generatePDF(for: resume, template: template.slug)
        } catch {
            Logger.error(
                "Initial resume render failed — seeding render_info.json as unavailable: \(error.localizedDescription)",
                category: .ai
            )
            try? writeRenderInfo(.unavailable)
            throw error
        }
        let pdfFile = layout.root.appendingPathComponent("resume.pdf")
        try pdfData.write(to: pdfFile)

        let pageCount = RevisionPDFRenderer.countPDFPages(pdfData)
        if pageCount > 0 {
            try writeRenderInfo(.rendered(pageCount: pageCount))
        } else {
            Logger.error(
                "Could not determine the page count of the initial resume render — seeding render_info.json as unavailable",
                category: .ai
            )
            try writeRenderInfo(.unavailable)
        }

        Logger.info("Exported resume PDF (\(pdfData.count) bytes, \(pageCount) page(s))", category: .ai)
        return pageCount
    }

    /// Write the initial-render metadata file (`render_info.json`) at the
    /// workspace root. Read-only for the agent: the write tool only accepts
    /// `treenodes/*.json` and `fontsizenodes.json`.
    func writeRenderInfo(_ info: WorkspaceRenderInfo) throws {
        try Self.renderInfoData(info)
            .write(to: layout.root.appendingPathComponent("render_info.json"))
    }

    /// Pure half: encode the render metadata (camelCase keys, stable ordering).
    static func renderInfoData(_ info: WorkspaceRenderInfo) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(info)
    }

    // MARK: - Export: Modifiable TreeNodes

    /// Export AI-modifiable treenode subtrees to the workspace as per-section JSON
    /// files. Writes a pristine snapshot of each file to the protected snapshot
    /// area and returns the human-facing manifest plus the export→import contract.
    func exportModifiableTreeNodes(
        from resume: Resume
    ) throws -> (manifest: WorkspaceManifest, export: RevisionExportManifest) {
        guard let root = resume.rootNode else {
            throw RevisionWorkspaceError.invalidResumeData("Resume has no root node")
        }

        let treenodesDir = layout.treenodes
        let snapshotsDir = layout.snapshots

        var sectionMeta: [WorkspaceManifest.SectionInfo] = []
        var usedSlugs: Set<String> = []
        var editableNodeIDs: Set<String> = []
        var sectionSlugToNodeID: [String: String] = [:]

        // Walk top-level section children of root
        for section in root.orderedChildren {
            let editableRoots = collectEditableRoots(from: section, into: &editableNodeIDs)
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
            // Pristine snapshot — written outside the tool-visible workspace,
            // so it stays byte-identical to the export. Ground truth for
            // diffs, proposal verification, and mid-session-edit detection.
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
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: layout.manifest)

        Logger.info("Exported \(sectionMeta.count) sections with modifiable treenodes", category: .ai)
        return (
            manifest,
            RevisionExportManifest(sectionSlugToNodeID: sectionSlugToNodeID, editableNodeIDs: editableNodeIDs)
        )
    }

    /// Find the AI-editable root nodes within a section.
    /// Editable roots are nodes with `status == .aiToReplace`; their entire subtree is editable.
    /// Records all editable node IDs (for import-time enforcement) into `editableIDs`.
    private func collectEditableRoots(from section: TreeNode, into editableIDs: inout Set<String>) -> [TreeNode] {
        var roots: [TreeNode] = []
        findEditableRoots(node: section, result: &roots)
        guard !roots.isEmpty else { return [] }
        // Record all editable IDs (roots + their entire subtrees, excluding group-excluded nodes)
        for root in roots {
            recordEditableIDs(node: root, into: &editableIDs)
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
    private func recordEditableIDs(node: TreeNode, into editableIDs: inout Set<String>) {
        guard node.status != .excludedFromGroup else { return }
        editableIDs.insert(node.id)
        for child in node.orderedChildren {
            recordEditableIDs(node: child, into: &editableIDs)
        }
    }

    // MARK: - Export: Job Description

    func exportJobDescription(_ text: String) throws {
        let file = layout.root.appendingPathComponent("job_description.txt")
        try Self.wrapText(text).write(to: file, atomically: true, encoding: .utf8)
        Logger.info("Exported job description (\(text.count) chars)", category: .ai)
    }

    // MARK: - Export: Job Metadata

    /// Export the structured job listing metadata (title, company, location,
    /// seniority, salary, …) so the agent sees more than the raw description.
    func exportJobMetadata(for jobApp: JobApp) throws {
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

        let file = layout.root.appendingPathComponent("job_metadata.txt")
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

        let file = layout.root.appendingPathComponent("job_requirements.txt")
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
        let cardsDir = layout.knowledgeCards

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

        let overviewFile = layout.root.appendingPathComponent("knowledge_cards_overview.txt")
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
        let categories = SkillCategoryUtils.sortedCategories(from: skills)
        var lines: [String] = ["# Skill Bank", ""]

        for category in categories {
            lines.append("## \(category)")
            let categorySkills = skills
                .filter { SkillCategoryUtils.normalizeCategory($0.categoryRaw) == category }
                .sorted { $0.canonical < $1.canonical }

            for skill in categorySkills {
                let variants = skill.atsVariants
                var line = "- \(skill.canonical)"
                if !variants.isEmpty {
                    line += " — ATS: \(variants.joined(separator: ", "))"
                }
                lines.append(line)
            }
            lines.append("")
        }

        let file = layout.root.appendingPathComponent("skill_bank.txt")
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)

        Logger.info("Exported \(skills.count) skills across \(categories.count) categories", category: .ai)
    }

    // MARK: - Export: Voice Materials

    /// What the voice export actually wrote, so prompt construction can key off
    /// the same selection the workspace contains.
    struct VoiceExportSummary {
        let samplesExported: Int
    }

    /// Export the user's voice materials: the writing samples selected by the
    /// canonical writer's-voice criteria (same selection as
    /// `CoverRefStore.writersVoice` — enabled-by-default samples, capped at 3)
    /// and the distilled voice primer as `voice_profile.txt`.
    @discardableResult
    func exportVoiceMaterials(_ coverRefs: [CoverRef]) throws -> VoiceExportSummary {
        let samplesDir = layout.writingSamples

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
            let profileFile = layout.root.appendingPathComponent("voice_profile.txt")
            try renderVoiceProfile(primer).write(to: profileFile, atomically: true, encoding: .utf8)
            profileExported = true
        }

        Logger.info(
            "Exported \(samples.count) writing samples"
                + (profileExported ? " and the voice profile" : ""),
            category: .ai
        )
        return VoiceExportSummary(samplesExported: samples.count)
    }

    /// Render the analyzed voice profile as readable Markdown.
    private func renderVoiceProfile(_ primer: CoverRef) -> String {
        var lines: [String] = ["# Voice Profile", ""]

        if !primer.content.isEmpty {
            lines.append(Self.wrapText(primer.content))
        }

        if let profile = primer.voiceProfile {
            for (label, value) in profile.characteristicPairs {
                lines.append("")
                lines.append("## \(label)")
                lines.append(Self.wrapText(value))
            }
            if !profile.sampleExcerpts.isEmpty {
                lines.append("")
                lines.append("## Voice Excerpts")
                lines.append(contentsOf: profile.sampleExcerpts.map { Self.wrapText("- \"\($0)\"") })
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Export: Font Size Nodes

    func exportFontSizeNodes(_ nodes: [FontSizeNode]) throws {
        guard !nodes.isEmpty else {
            Logger.info("No font size nodes to export", category: .ai)
            return
        }

        let sortedNodes = nodes.sorted(by: { $0.index < $1.index })
        let jsonArray = sortedNodes.map { node -> [String: Any] in
            ["key": node.key, "fontString": node.fontString, "index": node.index]
        }

        let jsonData = try JSONSerialization.data(withJSONObject: jsonArray, options: [.prettyPrinted, .sortedKeys])
        let file = layout.root.appendingPathComponent("fontsizenodes.json")
        try jsonData.write(to: file)

        Logger.info("Exported \(nodes.count) font size nodes", category: .ai)
    }

    // MARK: - Export: Title Sets

    func exportTitleSets(_ titleSets: [TitleSetRecord]) throws {
        guard !titleSets.isEmpty else {
            Logger.info("No title sets to export", category: .ai)
            return
        }

        var lines: [String] = ["# Title Sets Library", ""]
        for (index, record) in titleSets.enumerated() {
            lines.append("\(index + 1). \(record.displayString)")
        }

        let file = layout.root.appendingPathComponent("title_sets.txt")
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)

        Logger.info("Exported \(titleSets.count) title sets", category: .ai)
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

// MARK: - Workspace Render Info

/// Initial render metadata seeded into the workspace at session start
/// (`render_info.json`). `pageCount` is nil when the initial render's page
/// count could not be determined — an honest "unavailable" marker; a count is
/// never fabricated.
struct WorkspaceRenderInfo: Codable, Equatable {
    let pageCount: Int?
    let status: String

    static func rendered(pageCount: Int) -> WorkspaceRenderInfo {
        WorkspaceRenderInfo(pageCount: pageCount, status: "rendered")
    }

    static let unavailable = WorkspaceRenderInfo(pageCount: nil, status: "unavailable")
}
