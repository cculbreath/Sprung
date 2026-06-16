import Foundation

// MARK: - Workspace Layout

/// Filesystem layout of one revision session's workspace. Created by
/// `ResumeRevisionWorkspaceService` (the lifecycle owner) and handed to each
/// worker (`RevisionMaterialExporter` / `RevisionResumeImporter` /
/// `RevisionGroundTruth`), so the workers never carry the "is the workspace
/// created yet?" optionality — they operate on a guaranteed, non-optional layout.
struct RevisionWorkspaceLayout {
    /// Per-session workspace directory the agent's tools are rooted at
    /// (`revision-workspace/<UUID>/`).
    let root: URL

    /// Ground-truth snapshot directory: a per-session SIBLING
    /// (`revision-workspace/snapshots-<UUID>/`) whose name deliberately does not
    /// extend the session directory name, so it is unreachable by every agent
    /// tool (read/glob/grep validate paths with a `hasPrefix(root)` check; the
    /// write tool with a path-component prefix check). These files stay
    /// byte-identical to the export and are the ground truth for diffs, proposal
    /// verification, and mid-session-edit detection.
    let snapshots: URL

    var treenodes: URL { root.appendingPathComponent("treenodes") }
    var knowledgeCards: URL { root.appendingPathComponent("knowledge_cards") }
    var writingSamples: URL { root.appendingPathComponent("writing_samples") }
    var manifest: URL { root.appendingPathComponent("manifest.txt") }
}

// MARK: - Export → Import Contract

/// The export→import contract. Produced when modifiable treenodes are exported
/// (`RevisionMaterialExporter.exportModifiableTreeNodes`); REQUIRED to build the
/// revised resume (`RevisionResumeImporter.buildNewResume`).
///
/// This was previously scattered private instance state on the workspace service
/// (`sectionSlugToNodeID` + `editableNodeIDs`) that the import path silently
/// depended on — calling build without a prior export produced wrong output with
/// no signal. Making it an explicit value forces export-before-build and lets the
/// importer be exercised in isolation.
struct RevisionExportManifest {
    /// Maps exported file slug → original section node id, so import resolves
    /// sections robustly even when two section names sanitize identically.
    let sectionSlugToNodeID: [String: String]

    /// IDs of nodes that were marked editable at export time — the only nodes the
    /// agent was actually handed. Import additionally re-derives editability from
    /// the live resume to honor mid-session status toggles.
    let editableNodeIDs: Set<String>
}

// MARK: - Errors

enum RevisionWorkspaceError: Error, LocalizedError {
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
