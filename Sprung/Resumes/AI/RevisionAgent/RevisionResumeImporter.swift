import Foundation
import SwiftData

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

// MARK: - Resume Importer

/// Reads the agent's revised workspace files and rebuilds a new `Resume` by
/// deep-cloning the original tree and applying the revised values, additions,
/// reorderings, and omission-deletions — the riskiest leg of the revision data
/// plane. Operates on a guaranteed `RevisionWorkspaceLayout`; the editable-node
/// authorization (`RevisionExportManifest`) is passed in explicitly so a build
/// can never silently run against missing export state.
@MainActor
struct RevisionResumeImporter {

    let layout: RevisionWorkspaceLayout

    // MARK: - Import: Revised Font Sizes

    /// Read fontsizenodes.json from the workspace and return parsed entries.
    func importRevisedFontSizes() throws -> [[String: Any]]? {
        let file = layout.root.appendingPathComponent("fontsizenodes.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }

        let data = try Data(contentsOf: file)
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }

        return array.isEmpty ? nil : array
    }

    // MARK: - Import: Revised TreeNodes

    /// Read all treenode JSON files from the workspace.
    /// Returns a dictionary keyed by section slug (each an array of node
    /// dictionaries) plus a report capturing any unreadable/malformed sections.
    /// Unreadable or malformed sections are skipped, never aborting the import.
    func importRevisedTreeNodes() throws -> (nodes: [String: [[String: Any]]], report: RevisionImportReport) {
        let treenodesDir = layout.treenodes
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

        Logger.info("Imported revised treenodes from \(result.count) sections", category: .ai)
        return (result, report)
    }

    // MARK: - Build New Resume

    /// Create a new Resume by cloning the original and applying revised treenode
    /// values and font sizes. Returns the new resume and a report listing every
    /// discrepancy encountered (seeded with `baseReport` from the treenode read).
    func buildNewResume(
        from original: Resume,
        revisedNodes: [String: [[String: Any]]],
        revisedFontSizes: [[String: Any]]? = nil,
        export: RevisionExportManifest,
        baseReport: RevisionImportReport = RevisionImportReport(),
        context: ModelContext
    ) throws -> (resume: Resume, report: RevisionImportReport) {
        guard let jobApp = original.jobApp else {
            throw RevisionWorkspaceError.invalidResumeData("The original resume is no longer linked to a job application")
        }
        guard let originalRoot = original.rootNode else {
            throw RevisionWorkspaceError.invalidResumeData("The original resume has no content tree")
        }

        var report = baseReport

        // Re-derive editability from the live resume NOW so mid-session status
        // toggles in the main window are honored at import time.
        var currentEditableIDs: Set<String> = []
        recordCurrentEditableIDs(node: originalRoot, inheritedEditable: false, into: &currentEditableIDs)

        // Pristine export snapshots, used to detect mid-session manual edits.
        let snapshotValues = loadSnapshotValues()

        let newResume = Resume(
            jobApp: jobApp,
            template: original.template
        )
        newResume.provenance = .aiRevised
        newResume.label = "\(original.template?.name ?? "Resume") — AI revised"
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
            guard let sectionOriginalID = export.sectionSlugToNodeID[slug],
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
                editableNodeIDs: export.editableNodeIDs,
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

        if !report.isEmpty {
            Logger.warning("RevisionAgent import discrepancies:\n\(report.summaryText)", category: .ai)
        }

        return (newResume, report)
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
        let snapshotsDir = layout.snapshots
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
        editableNodeIDs: Set<String>,
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
                editableNodeIDs: editableNodeIDs,
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
}
