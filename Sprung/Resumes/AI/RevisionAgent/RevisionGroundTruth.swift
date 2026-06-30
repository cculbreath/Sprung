import Foundation

// MARK: - Ground Truth

/// Read-only verification surface over the workspace. Everything here derives
/// from bytes on disk — the pristine export snapshots and the current treenode
/// files — never from the model's own claims about what it changed. Used for the
/// ground-truth diff, proposal before-preview verification, the coherence-pass
/// resume rendering, and the grounding-pass evidence corpus.
@MainActor
struct RevisionGroundTruth {

    let layout: RevisionWorkspaceLayout

    // MARK: - Snapshot Diff

    /// Compute the ground-truth diff between the pristine export snapshots and
    /// the current workspace treenode files: every editable node whose value
    /// the agent changed, added, or deleted. This is REALITY — derived from
    /// bytes on disk, never from the model's own claims about what it did.
    func computeWorkspaceDiff() throws -> RevisionWorkspaceDiff {
        let snapshotNodes = try flattenNodeFiles(in: layout.snapshots)
        let currentNodes = try flattenNodeFiles(in: layout.treenodes)

        var entries: [RevisionNodeDiff] = []
        let slugs = Set(snapshotNodes.keys).union(currentNodes.keys)

        for slug in slugs.sorted() {
            let snapshot = snapshotNodes[slug] ?? []
            let current = currentNodes[slug] ?? []
            let snapshotByID = Dictionary(snapshot.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let currentIDs = Set(current.map(\.id))

            for node in current {
                if let original = snapshotByID[node.id] {
                    if original.value != node.value {
                        entries.append(RevisionNodeDiff(
                            kind: .modified,
                            sectionSlug: slug,
                            nodePath: node.path,
                            nodeId: node.id,
                            oldValue: original.value,
                            newValue: node.value
                        ))
                    }
                } else if !node.value.isEmpty {
                    entries.append(RevisionNodeDiff(
                        kind: .added,
                        sectionSlug: slug,
                        nodePath: node.path,
                        nodeId: node.id,
                        oldValue: nil,
                        newValue: node.value
                    ))
                }
            }

            for node in snapshot where !currentIDs.contains(node.id) && !node.value.isEmpty {
                entries.append(RevisionNodeDiff(
                    kind: .removed,
                    sectionSlug: slug,
                    nodePath: node.path,
                    nodeId: node.id,
                    oldValue: node.value,
                    newValue: nil
                ))
            }
        }

        return RevisionWorkspaceDiff(entries: entries)
    }

    /// Parse every treenode JSON file in a directory into flat node lists,
    /// keyed by section slug. Unreadable files are skipped with a log —
    /// diffing is advisory and must never abort a completion.
    private func flattenNodeFiles(in directory: URL) throws -> [String: [WorkspaceNodeSnapshot]] {
        let fileURLs = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var result: [String: [WorkspaceNodeSnapshot]] = [:]
        for fileURL in fileURLs {
            let slug = fileURL.deletingPathExtension().lastPathComponent
            do {
                let data = try Data(contentsOf: fileURL)
                guard let nodes = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                    Logger.warning("Diff: '\(fileURL.lastPathComponent)' is not a node array — skipped", category: .ai)
                    continue
                }
                var flat: [WorkspaceNodeSnapshot] = []
                Self.flatten(nodes: nodes, parentPath: slug, into: &flat)
                result[slug] = flat
            } catch {
                Logger.warning("Diff: could not read '\(fileURL.lastPathComponent)': \(error.localizedDescription)", category: .ai)
            }
        }
        return result
    }

    private static func flatten(
        nodes: [[String: Any]],
        parentPath: String,
        into result: inout [WorkspaceNodeSnapshot]
    ) {
        for (index, node) in nodes.enumerated() {
            let id = node["id"] as? String ?? ""
            let name = node["name"] as? String ?? ""
            let value = node["value"] as? String ?? ""
            let segment = name.isEmpty ? "[\(index)]" : name
            let path = "\(parentPath) › \(segment)"
            if !id.isEmpty {
                result.append(WorkspaceNodeSnapshot(id: id, name: name, value: value, path: path))
            }
            if let children = node["children"] as? [[String: Any]] {
                flatten(nodes: children, parentPath: path, into: &result)
            }
        }
    }

    // MARK: - Proposal Verification

    /// Verify each proposed change's before-preview against the ACTUAL
    /// workspace content. The proposal card must show reality, not the model's
    /// claims — a mismatch surfaces the real content alongside the claim.
    /// Both the current files and the pristine snapshot count as ground truth
    /// for the "before" claim (an already-applied edit's before lives in the
    /// snapshot; the unreviewed-write check at completion catches premature
    /// writes separately).
    func verifyProposedChanges(_ changes: [ProposeChangesTool.ChangeDetail]) -> [ChangeProposal.BeforeVerification] {
        let nodesBySlug: [String: [WorkspaceNodeSnapshot]]
        do {
            nodesBySlug = try flattenNodeFiles(in: layout.treenodes)
        } catch {
            Logger.error("Proposal verification: could not read the revision workspace treenodes: \(error.localizedDescription)", category: .ai)
            ToastCenter.shared.show(.error("Could not read the revision workspace — proposal checks may be unreliable."))
            nodesBySlug = [:]
        }
        let snapshotValues: [String]
        do {
            let flattened = try flattenNodeFiles(in: layout.snapshots)
            snapshotValues = flattened.values.flatMap { $0 }.map(\.value).filter { !$0.isEmpty }
        } catch {
            Logger.error("Proposal verification: could not read the revision workspace snapshots: \(error.localizedDescription)", category: .ai)
            ToastCenter.shared.show(.error("Could not read the revision workspace — proposal checks may be unreliable."))
            snapshotValues = []
        }
        let allValues = nodesBySlug.values.flatMap { $0 }.map(\.value).filter { !$0.isEmpty } + snapshotValues
        let allNormalized = Set(allValues.map(Self.normalizedForMatch))

        return changes.map { change in
            guard let before = change.beforePreview, !Self.normalizedForMatch(before).isEmpty else {
                return .notApplicable
            }
            if Self.matches(before: before, against: allNormalized, fullValues: allValues) {
                return .verified
            }
            // Mismatch: provide the actual content of the best-guess section.
            let slugGuess = Self.normalizedForMatch(change.section).replacingOccurrences(of: " ", with: "_")
            let sectionNodes = nodesBySlug.first { key, _ in
                key == slugGuess || key.contains(slugGuess) || slugGuess.contains(key)
            }?.value ?? []
            let actual = sectionNodes.map(\.value).filter { !$0.isEmpty }.prefix(8)
            return .mismatch(actualContent: Array(actual))
        }
    }

    /// True when the model's before-preview is found in the actual content:
    /// exact node-value match, every preview line matching a node value (list
    /// bundles render as multi-line previews), or containment either way.
    private static func matches(before: String, against normalizedValues: Set<String>, fullValues: [String]) -> Bool {
        let normalized = normalizedForMatch(before)
        if normalizedValues.contains(normalized) { return true }

        // Line-wise: every non-empty preview line matches some node value.
        let lines = before.components(separatedBy: .newlines)
            .map { line -> String in
                var trimmed = line.trimmingCharacters(in: .whitespaces)
                while let first = trimmed.first, "-•*".contains(first) {
                    trimmed = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                }
                return normalizedForMatch(trimmed)
            }
            .filter { !$0.isEmpty }
        if lines.count > 1, lines.allSatisfy({ normalizedValues.contains($0) }) { return true }

        // Containment either way (guarded against trivially short strings).
        if normalized.count >= 24 {
            for value in fullValues {
                let normalizedValue = normalizedForMatch(value)
                if normalizedValue.contains(normalized) || (normalizedValue.count >= 24 && normalized.contains(normalizedValue)) {
                    return true
                }
            }
        }
        return false
    }

    /// Case- and whitespace-insensitive normalization for ground-truth matching.
    static func normalizedForMatch(_ text: String) -> String {
        text.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    // MARK: - Verification Inputs

    /// Render the CURRENT revised editable content as readable text for the
    /// coherence pass. Only editable content lives in the workspace; locked
    /// content is visible to the verifier via the conversation's resume PDF.
    func renderCurrentResumeText() throws -> String {
        let nodeFiles = try FileManager.default.contentsOfDirectory(at: layout.treenodes, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var lines: [String] = []
        for fileURL in nodeFiles {
            let slug = fileURL.deletingPathExtension().lastPathComponent
            let nodes: [[String: Any]]
            do {
                let data = try Data(contentsOf: fileURL)
                guard let parsed = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                    Logger.warning("Coherence pass: '\(fileURL.lastPathComponent)' is not a node array — skipped", category: .ai)
                    continue
                }
                nodes = parsed
            } catch {
                Logger.error("Coherence pass: could not read '\(fileURL.lastPathComponent)' — resume audit ran on partial content: \(error.localizedDescription)", category: .ai)
                ToastCenter.shared.show(.error("Part of the resume could not be read — the coherence check ran on incomplete content."))
                continue
            }
            lines.append("## \(slug)")
            Self.renderNodes(nodes, indent: 0, into: &lines)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func renderNodes(_ nodes: [[String: Any]], indent: Int, into lines: inout [String]) {
        let prefix = String(repeating: "  ", count: indent)
        for node in nodes {
            let name = node["name"] as? String ?? ""
            let value = node["value"] as? String ?? ""
            if !name.isEmpty && !value.isEmpty {
                lines.append("\(prefix)\(name): \(value)")
            } else if !value.isEmpty {
                lines.append("\(prefix)- \(value)")
            } else if !name.isEmpty {
                lines.append("\(prefix)\(name):")
            }
            if let children = node["children"] as? [[String: Any]], !children.isEmpty {
                renderNodes(children, indent: indent + 1, into: &lines)
            }
        }
    }

    /// Assemble the evidence corpus for the grounding verification pass from
    /// the SAME files the agent was shown: every exported knowledge card plus
    /// the skill bank. Capped so a pathological card library cannot blow up
    /// the verification request; truncation is noted inline for the model AND
    /// returned to the caller, so the completion card can disclose that the
    /// audit ran on partial evidence (which can produce false "unsupported"
    /// flags).
    func readGroundingCorpus(maxCharacters: Int = 120_000) -> (corpus: String, wasTruncated: Bool) {
        let cardsDir = layout.knowledgeCards

        var sections: [String] = []
        var remaining = maxCharacters
        var wasTruncated = false

        func append(_ text: String) {
            guard !text.isEmpty else { return }
            guard remaining > 0 else {
                wasTruncated = true
                return
            }
            if text.count <= remaining {
                sections.append(text)
                remaining -= text.count
            } else {
                sections.append(String(text.prefix(remaining)) + "\n[... truncated for length ...]")
                remaining = 0
                wasTruncated = true
            }
        }

        do {
            let skillBank = try String(contentsOf: layout.root.appendingPathComponent("skill_bank.txt"), encoding: .utf8)
            append(skillBank)
        } catch {
            Logger.error("Grounding pass: could not read the skill bank — fabrication detection ran with reduced evidence: \(error.localizedDescription)", category: .ai)
            ToastCenter.shared.show(.error("Could not read the skill bank — the grounding check ran on partial evidence."))
        }

        let cardFiles: [URL]
        do {
            cardFiles = try FileManager.default.contentsOfDirectory(at: cardsDir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "txt" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            Logger.error("Grounding pass: could not read the knowledge-card corpus — fabrication detection ran with reduced evidence: \(error.localizedDescription)", category: .ai)
            ToastCenter.shared.show(.error("Could not read the knowledge-card evidence — the grounding check ran on partial evidence."))
            cardFiles = []
        }
        for cardFile in cardFiles {
            guard remaining > 0 else {
                sections.append("[... additional knowledge cards omitted for length ...]")
                wasTruncated = true
                break
            }
            do {
                let card = try String(contentsOf: cardFile, encoding: .utf8)
                append(card)
            } catch {
                Logger.error("Grounding pass: could not read knowledge card '\(cardFile.lastPathComponent)' — omitted from the grounding evidence: \(error.localizedDescription)", category: .ai)
            }
        }

        return (sections.joined(separator: "\n\n---\n\n"), wasTruncated)
    }
}

// MARK: - Ground-Truth Diff Types

/// A flattened treenode read from a workspace or snapshot JSON file.
struct WorkspaceNodeSnapshot {
    let id: String
    let name: String
    let value: String
    /// Human-readable location, e.g. "work › [0] › highlights › [2]".
    let path: String
}

/// One ground-truth difference between the export snapshot and the current
/// workspace state.
struct RevisionNodeDiff: Identifiable {
    enum Kind: String {
        case modified
        case added
        case removed
    }

    let id = UUID()
    let kind: Kind
    let sectionSlug: String
    let nodePath: String
    let nodeId: String
    let oldValue: String?
    let newValue: String?
}

/// The full ground-truth diff for a session: every editable node the agent
/// actually changed, added, or removed in the workspace.
struct RevisionWorkspaceDiff {
    let entries: [RevisionNodeDiff]
    var isEmpty: Bool { entries.isEmpty }
}
