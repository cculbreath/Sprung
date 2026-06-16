import Foundation
import SwiftData

/// Owns the ephemeral filesystem workspace for the resume revision agent and
/// coordinates the create → export → agent loop → import → delete lifecycle.
///
/// The heavy lifting lives in three focused workers, each operating on a
/// guaranteed `RevisionWorkspaceLayout`:
/// - `RevisionMaterialExporter` — renders the model graph into workspace files
///   and produces the export→import contract (`RevisionExportManifest`).
/// - `RevisionResumeImporter` — reads the agent's revised files and rebuilds a
///   new `Resume` (the riskiest leg), authorized by that contract.
/// - `RevisionGroundTruth` — read-only diff / proposal verification / coherence
///   rendering / grounding corpus, all derived from bytes on disk.
///
/// This type holds the session state those workers need (the layout, the export
/// contract, the most-recent import report) so the agent sees one stable surface.
@MainActor
final class ResumeRevisionWorkspaceService {

    /// Base directory override for tests. When nil, the default Application
    /// Support location is used.
    private let baseDirectoryOverride: URL?

    /// Filesystem layout for the current session; nil until `createWorkspace()`.
    private(set) var layout: RevisionWorkspaceLayout?

    /// The export→import contract captured at `exportModifiableTreeNodes`;
    /// required by `buildNewResume`.
    private var exportManifest: RevisionExportManifest?

    /// Report from `importRevisedTreeNodes`, threaded into the following
    /// `buildNewResume` so malformed-section skips survive into the final report.
    private var pendingImportReport: RevisionImportReport?

    /// Report describing discrepancies from the most recent import/build.
    private(set) var lastImportReport: RevisionImportReport?

    /// Workspace directory path (per-session: revision-workspace/<UUID>/).
    var workspacePath: URL? { layout?.root }

    init(baseDirectory: URL? = nil) {
        self.baseDirectoryOverride = baseDirectory
    }

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
                throw RevisionWorkspaceError.workspaceCreationFailed("Could not locate the Application Support directory")
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
                throw RevisionWorkspaceError.workspaceCreationFailed(
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

        let sessionID = UUID().uuidString
        let session = baseDir.appendingPathComponent(sessionID, isDirectory: true)
        for subdir in ["treenodes", "knowledge_cards", "writing_samples"] {
            let dir = session.appendingPathComponent(subdir)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // Ground-truth snapshots live in a SIBLING directory whose name does
        // not extend the session path, so no agent tool (rooted at the session
        // directory) can read or write them. Swept with everything else in the
        // base directory at the next session's startup.
        let snapshots = baseDir.appendingPathComponent("snapshots-\(sessionID)", isDirectory: true)
        try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)

        let layout = RevisionWorkspaceLayout(root: session, snapshots: snapshots)
        self.layout = layout
        self.exportManifest = nil
        self.pendingImportReport = nil
        self.lastImportReport = nil
        Logger.info("Created revision workspace at \(session.path)", category: .ai)
        return session
    }

    /// Deletes only the current session directory (and its snapshot sibling).
    /// Tolerates already-missing directories; never touches sibling sessions.
    func deleteWorkspace() throws {
        guard let layout else { return }

        if FileManager.default.fileExists(atPath: layout.snapshots.path) {
            try? FileManager.default.removeItem(at: layout.snapshots)
        }

        if FileManager.default.fileExists(atPath: layout.root.path) {
            try FileManager.default.removeItem(at: layout.root)
            Logger.info("Deleted revision workspace", category: .ai)
        }

        self.layout = nil
    }

    // MARK: - Worker Accessors

    private func requireExporter() throws -> RevisionMaterialExporter {
        guard let layout else { throw RevisionWorkspaceError.workspaceNotCreated }
        return RevisionMaterialExporter(layout: layout)
    }

    private func requireGroundTruth() throws -> RevisionGroundTruth {
        guard let layout else { throw RevisionWorkspaceError.workspaceNotCreated }
        return RevisionGroundTruth(layout: layout)
    }

    private func requireImporter() throws -> RevisionResumeImporter {
        guard let layout else { throw RevisionWorkspaceError.workspaceNotCreated }
        return RevisionResumeImporter(layout: layout)
    }

    // MARK: - Export

    func exportResumePDF(resume: Resume, pdfGenerator: NativePDFGenerator) async throws {
        try await requireExporter().exportResumePDF(resume: resume, pdfGenerator: pdfGenerator)
    }

    /// Export AI-modifiable treenode subtrees and capture the export→import
    /// contract for the subsequent `buildNewResume`.
    func exportModifiableTreeNodes(from resume: Resume) throws -> WorkspaceManifest {
        let result = try requireExporter().exportModifiableTreeNodes(from: resume)
        self.exportManifest = result.export
        return result.manifest
    }

    func exportJobDescription(_ text: String) throws {
        try requireExporter().exportJobDescription(text)
    }

    func exportJobMetadata(for jobApp: JobApp) throws {
        try requireExporter().exportJobMetadata(for: jobApp)
    }

    @discardableResult
    func exportJobRequirements(_ requirements: ExtractedRequirements?) throws -> Bool {
        try requireExporter().exportJobRequirements(requirements)
    }

    func exportKnowledgeCards(_ cards: [KnowledgeCard], relevantCardIds: [String]?) throws {
        try requireExporter().exportKnowledgeCards(cards, relevantCardIds: relevantCardIds)
    }

    func exportSkillBank(_ skills: [Skill]) throws {
        try requireExporter().exportSkillBank(skills)
    }

    @discardableResult
    func exportVoiceMaterials(_ coverRefs: [CoverRef]) throws -> RevisionMaterialExporter.VoiceExportSummary {
        try requireExporter().exportVoiceMaterials(coverRefs)
    }

    func exportFontSizeNodes(_ nodes: [FontSizeNode]) throws {
        try requireExporter().exportFontSizeNodes(nodes)
    }

    func exportTitleSets(_ titleSets: [TitleSetRecord]) throws {
        try requireExporter().exportTitleSets(titleSets)
    }

    // MARK: - Import / Build

    func importRevisedFontSizes() throws -> [[String: Any]]? {
        try requireImporter().importRevisedFontSizes()
    }

    func importRevisedTreeNodes() throws -> [String: [[String: Any]]] {
        let (nodes, report) = try requireImporter().importRevisedTreeNodes()
        self.pendingImportReport = report
        return nodes
    }

    /// Create a new Resume by cloning the original and applying revised treenode
    /// values and font sizes. Populates `lastImportReport`. Requires a prior
    /// `exportModifiableTreeNodes` (the export→import contract).
    func buildNewResume(
        from original: Resume,
        revisedNodes: [String: [[String: Any]]],
        revisedFontSizes: [[String: Any]]? = nil,
        context: ModelContext
    ) throws -> Resume {
        guard let exportManifest else { throw RevisionWorkspaceError.workspaceNotCreated }
        let baseReport = pendingImportReport ?? RevisionImportReport()
        pendingImportReport = nil

        let (newResume, report) = try requireImporter().buildNewResume(
            from: original,
            revisedNodes: revisedNodes,
            revisedFontSizes: revisedFontSizes,
            export: exportManifest,
            baseReport: baseReport,
            context: context
        )
        self.lastImportReport = report
        return newResume
    }

    // MARK: - Ground Truth

    func computeWorkspaceDiff() throws -> RevisionWorkspaceDiff {
        try requireGroundTruth().computeWorkspaceDiff()
    }

    func verifyProposedChanges(_ changes: [ProposeChangesTool.ChangeDetail]) -> [ChangeProposal.BeforeVerification] {
        guard let groundTruth = try? requireGroundTruth() else {
            return changes.map { _ in .notApplicable }
        }
        return groundTruth.verifyProposedChanges(changes)
    }

    func renderCurrentResumeText() throws -> String {
        try requireGroundTruth().renderCurrentResumeText()
    }

    func readGroundingCorpus(maxCharacters: Int = 120_000) -> (corpus: String, wasTruncated: Bool) {
        guard let groundTruth = try? requireGroundTruth() else { return ("", false) }
        return groundTruth.readGroundingCorpus(maxCharacters: maxCharacters)
    }
}
