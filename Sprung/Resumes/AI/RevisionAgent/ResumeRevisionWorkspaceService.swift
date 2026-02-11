import Foundation
import SwiftData

/// Manages an ephemeral filesystem workspace for the resume revision agent.
/// Pattern: CardMergeWorkspaceService — create → export → agent loop → import → delete.
@MainActor
final class ResumeRevisionWorkspaceService {

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private let decoder = JSONDecoder()

    /// Workspace directory path
    private(set) var workspacePath: URL?

    /// IDs of nodes that were marked editable at export time.
    /// Used to enforce that only AI-selected nodes are modified on import.
    private(set) var editableNodeIDs: Set<String> = []

    // MARK: - Computed Paths

    private var treenodesPath: URL? { workspacePath?.appendingPathComponent("treenodes") }
    private var knowledgeCardsPath: URL? { workspacePath?.appendingPathComponent("knowledge_cards") }
    private var writingSamplesPath: URL? { workspacePath?.appendingPathComponent("writing_samples") }
    private var manifestPath: URL? { workspacePath?.appendingPathComponent("manifest.txt") }

    // MARK: - Workspace Lifecycle

    /// Creates a fresh workspace directory, removing any existing one.
    func createWorkspace() throws -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let sprungDir = appSupport.appendingPathComponent("Sprung")
        let workspace = sprungDir.appendingPathComponent("revision-workspace")

        if FileManager.default.fileExists(atPath: workspace.path) {
            try FileManager.default.removeItem(at: workspace)
            Logger.info("Removed existing revision workspace", category: .ai)
        }

        // Create subdirectories
        for subdir in ["treenodes", "knowledge_cards", "writing_samples"] {
            let dir = workspace.appendingPathComponent(subdir)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        workspacePath = workspace
        Logger.info("Created revision workspace at \(workspace.path)", category: .ai)
        return workspace
    }

    /// Deletes the workspace directory and all contents.
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

        let slug = resume.template?.slug ?? "default"
        let pdfData = try await pdfGenerator.generatePDF(for: resume, template: slug)
        let pdfFile = workspace.appendingPathComponent("resume.pdf")
        try pdfData.write(to: pdfFile)

        Logger.info("Exported resume PDF (\(pdfData.count) bytes)", category: .ai)
    }

    // MARK: - Export: Modifiable TreeNodes

    /// Export AI-modifiable treenode subtrees to the workspace as per-section JSON files.
    /// Returns a manifest describing exported sections and target page count.
    func exportModifiableTreeNodes(from resume: Resume) throws -> WorkspaceManifest {
        guard let treenodesDir = treenodesPath else {
            throw WorkspaceError.workspaceNotCreated
        }

        guard let root = resume.rootNode else {
            throw WorkspaceError.invalidResumeData("Resume has no root node")
        }

        var sectionMeta: [WorkspaceManifest.SectionInfo] = []

        editableNodeIDs = []

        // Walk top-level section children of root
        for section in root.orderedChildren {
            let editableRoots = collectEditableRoots(from: section)
            guard !editableRoots.isEmpty else { continue }

            let sectionName = section.name.isEmpty ? section.displayLabel : section.name
            let sanitized = sectionName.lowercased()
                .replacingOccurrences(of: " ", with: "_")
                .filter { $0.isLetter || $0.isNumber || $0 == "_" }

            // Serialize only the editable subtrees
            let nodeArray = editableRoots.map { $0.toRevisionDictionary() }
            let jsonData = try JSONSerialization.data(withJSONObject: nodeArray, options: [.prettyPrinted, .sortedKeys])
            let filePath = treenodesDir.appendingPathComponent("\(sanitized).json")
            try jsonData.write(to: filePath)

            sectionMeta.append(WorkspaceManifest.SectionInfo(
                name: sectionName,
                file: "treenodes/\(sanitized).json",
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

    /// Find the AI-editable root nodes within a section (nodes with `.aiToReplace` status).
    /// Only these subtrees are exported — non-editable nodes are excluded entirely.
    /// Records all editable node IDs for import-time enforcement.
    private func collectEditableRoots(from section: TreeNode) -> [TreeNode] {
        var roots: [TreeNode] = []
        findEditableRoots(node: section, result: &roots)
        guard !roots.isEmpty else { return [] }
        // Record all editable IDs (roots + their entire subtrees)
        for root in roots {
            recordEditableIDs(node: root)
        }
        return roots
    }

    /// Walk the tree to find nodes directly marked `.aiToReplace` — these are the editable subtree roots.
    private func findEditableRoots(node: TreeNode, result: inout [TreeNode]) {
        if node.status == .aiToReplace {
            result.append(node)
            return // Don't recurse further — entire subtree is editable
        }
        for child in node.orderedChildren {
            findEditableRoots(node: child, result: &result)
        }
    }

    /// Record a node and all its descendants as editable.
    private func recordEditableIDs(node: TreeNode) {
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
        try text.write(to: file, atomically: true, encoding: .utf8)
        Logger.info("Exported job description (\(text.count) chars)", category: .ai)
    }

    // MARK: - Export: Knowledge Cards

    func exportKnowledgeCards(_ cards: [KnowledgeCard]) throws {
        guard let cardsDir = knowledgeCardsPath, let workspace = workspacePath else {
            throw WorkspaceError.workspaceNotCreated
        }

        for card in cards {
            let cardFile = cardsDir.appendingPathComponent("\(card.id.uuidString).txt")
            let cardData = try encoder.encode(card)
            try cardData.write(to: cardFile)
        }

        // Write overview
        var overviewLines: [String] = ["# Knowledge Cards Overview", ""]
        for card in cards {
            let type = card.cardType?.displayName ?? "General"
            let org = card.organization ?? ""
            let dates = card.dateRange ?? ""
            let preview = String(card.narrative.prefix(200))
            overviewLines.append("## \(card.title)")
            overviewLines.append("- ID: \(card.id.uuidString)")
            overviewLines.append("- Type: \(type)")
            if !org.isEmpty { overviewLines.append("- Organization: \(org)") }
            if !dates.isEmpty { overviewLines.append("- Date Range: \(dates)") }
            overviewLines.append("- Narrative: \(preview)...")
            overviewLines.append("")
        }

        let overviewFile = workspace.appendingPathComponent("knowledge_cards_overview.txt")
        try overviewLines.joined(separator: "\n").write(to: overviewFile, atomically: true, encoding: .utf8)

        Logger.info("Exported \(cards.count) knowledge cards", category: .ai)
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

    // MARK: - Export: Writing Samples

    func exportWritingSamples(_ coverRefs: [CoverRef]) throws {
        guard let samplesDir = writingSamplesPath else {
            throw WorkspaceError.workspaceNotCreated
        }

        let samples = coverRefs.filter { $0.type == .writingSample }
        for sample in samples {
            let slugName = sample.name.lowercased()
                .replacingOccurrences(of: " ", with: "-")
                .filter { $0.isLetter || $0.isNumber || $0 == "-" }
            let file = samplesDir.appendingPathComponent("\(slugName).txt")
            try sample.content.write(to: file, atomically: true, encoding: .utf8)
        }

        Logger.info("Exported \(samples.count) writing samples", category: .ai)
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
    /// Returns a dictionary keyed by section name, each containing an array of node dictionaries.
    func importRevisedTreeNodes() throws -> [String: [[String: Any]]] {
        guard let treenodesDir = treenodesPath else {
            throw WorkspaceError.workspaceNotCreated
        }

        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: treenodesDir,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }

        var result: [String: [[String: Any]]] = [:]

        for fileURL in fileURLs {
            let sectionName = fileURL.deletingPathExtension().lastPathComponent
            let data = try Data(contentsOf: fileURL)
            guard let nodes = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                Logger.warning("Failed to parse treenode file: \(fileURL.lastPathComponent)", category: .ai)
                continue
            }

            // Validate required fields
            let requiredFields: Set<String> = ["id", "name", "value", "myIndex", "children"]
            for (index, node) in nodes.enumerated() {
                let keys = Set(node.keys)
                let missing = requiredFields.subtracting(keys)
                if !missing.isEmpty {
                    throw WorkspaceError.invalidNodeData(
                        "Section '\(sectionName)' node \(index) missing: \(missing.sorted().joined(separator: ", "))"
                    )
                }
            }

            result[sectionName] = nodes
        }

        Logger.info("Imported revised treenodes from \(result.count) sections", category: .ai)
        return result
    }

    // MARK: - Build New Resume

    /// Create a new Resume by cloning the original and applying revised treenode values and font sizes.
    func buildNewResume(
        from original: Resume,
        revisedNodes: [String: [[String: Any]]],
        revisedFontSizes: [[String: Any]]? = nil,
        context: ModelContext
    ) -> Resume {
        let newResume = Resume(
            jobApp: original.jobApp!,
            enabledSources: original.enabledSources,
            template: original.template
        )
        context.insert(newResume)

        // Deep-clone the original tree
        guard let originalRoot = original.rootNode else { return newResume }
        let clonedRoot = deepCloneTreeNode(originalRoot, for: newResume, context: context)
        newResume.rootNode = clonedRoot

        // Apply revised values
        for (sectionName, nodes) in revisedNodes {
            // Find matching section in cloned tree
            guard let sectionNode = clonedRoot.orderedChildren.first(where: {
                let name = $0.name.isEmpty ? $0.displayLabel : $0.name
                return name.lowercased().replacingOccurrences(of: " ", with: "_")
                    .filter({ $0.isLetter || $0.isNumber || $0 == "_" }) == sectionName
            }) else {
                Logger.warning("Section '\(sectionName)' not found in cloned tree", category: .ai)
                continue
            }

            applyRevisedNodes(nodes, to: sectionNode, resume: newResume, context: context)
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
        newResume.phaseAssignments = original.phaseAssignments
        newResume.importedEditorKeys = original.importedEditorKeys

        return newResume
    }

    /// Deep-clone a TreeNode tree for a new resume.
    private func deepCloneTreeNode(_ node: TreeNode, for resume: Resume, context: ModelContext) -> TreeNode {
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
        clone.id = node.id
        clone.myIndex = node.myIndex
        clone.editorLabel = node.editorLabel
        clone.copySchemaMetadata(from: node)
        clone.bundledAttributes = node.bundledAttributes
        clone.enumeratedAttributes = node.enumeratedAttributes
        context.insert(clone)

        for child in node.orderedChildren {
            let childClone = deepCloneTreeNode(child, for: resume, context: context)
            clone.addChild(childClone)
        }

        return clone
    }

    /// Apply revised node dictionaries to a section node in the cloned tree.
    /// Only modifies nodes whose IDs are in `editableNodeIDs` (or new nodes added by the agent).
    private func applyRevisedNodes(
        _ revisions: [[String: Any]],
        to sectionNode: TreeNode,
        resume: Resume,
        context: ModelContext
    ) {
        for revision in revisions {
            guard let nodeId = revision["id"] as? String else { continue }

            if nodeId.hasPrefix("new-") {
                // New node — create and add (allowed: agent may add content)
                let newNode = createTreeNodeFromDictionary(revision, resume: resume, context: context)
                sectionNode.addChild(newNode)
            } else if let existing = findNodeById(nodeId, in: sectionNode) {
                // Only apply value changes to editable nodes
                let isEditable = editableNodeIDs.contains(nodeId)
                if isEditable {
                    if let value = revision["value"] as? String {
                        existing.value = value
                    }
                    if let myIndex = revision["myIndex"] as? Int {
                        existing.myIndex = myIndex
                    }
                    if let isTitleNode = revision["isTitleNode"] as? Bool {
                        existing.isTitleNode = isTitleNode
                    }
                } else {
                    Logger.debug("RevisionAgent: Skipped edit to non-editable node '\(nodeId)' (\(existing.name))", category: .ai)
                }
                // Always recurse into children — some children may be editable even if parent isn't
                if let children = revision["children"] as? [[String: Any]] {
                    applyRevisedNodes(children, to: existing, resume: resume, context: context)
                }
            }
        }
    }

    /// Create a TreeNode from a revision dictionary (for new nodes).
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
        if let id = dict["id"] as? String {
            node.id = id
        }
        node.myIndex = dict["myIndex"] as? Int ?? 0
        context.insert(node)

        if let children = dict["children"] as? [[String: Any]] {
            for childDict in children {
                let child = createTreeNodeFromDictionary(childDict, resume: resume, context: context)
                node.addChild(child)
            }
        }

        return node
    }

    /// Find a node by ID in a subtree.
    private func findNodeById(_ id: String, in node: TreeNode) -> TreeNode? {
        if node.id == id { return node }
        for child in node.orderedChildren {
            if let found = findNodeById(id, in: child) {
                return found
            }
        }
        return nil
    }

    // MARK: - Errors

    enum WorkspaceError: Error, LocalizedError {
        case workspaceNotCreated
        case invalidResumeData(String)
        case invalidNodeData(String)

        var errorDescription: String? {
            switch self {
            case .workspaceNotCreated:
                return "Workspace has not been created"
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
