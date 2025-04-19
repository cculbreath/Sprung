import Foundation
import Observation

/// View‑model for the resume editor panel (node tree + font panel).
/// Encapsulates UI‑specific state so SwiftUI views no longer mutate the model
/// layer directly.
@Observable
@MainActor
final class ResumeDetailVM {
    // MARK: - Input ---------------------------------------------------------

    private(set) var resume: Resume

    // MARK: - UI State ------------------------------------------------------

    /// Width toggle previously handled by the view hierarchy.
    var isWide: Bool = false

    /// Triggers a view refresh when nodes change order / values.
    var refresher: Bool = false

    /// Whether the optional font‑size panel should be shown. This setting is
    /// mirrored from the underlying model but owned by the view‑model so that
    /// the view no longer touches the model layer directly.
    var includeFonts: Bool {
        get { resume.includeFonts }
        set { resume.includeFonts = newValue }
    }

    // Tracks which group nodes are expanded in the UI.
    private var expandedIDs: Set<String> = []

    /// Computed convenience access to the resume’s root node.
    var rootNode: TreeNode? { resume.rootNode }

    // MARK: - Dependencies --------------------------------------------------

    private let resStore: ResStore

    init(resume: Resume, resStore: ResStore) {
        self.resume = resume
        self.resStore = resStore
    }

    // MARK: - Intents -------------------------------------------------------

    /// Adds an empty child node to the given parent.
    func addChild(to parent: TreeNode) {
        let newNode = TreeNode(
            name: "",
            value: "New Child",
            inEditor: true,
            status: .saved,
            resume: resume
        )
        // Editing state is now tracked solely in the view‑model.
        parent.addChild(newNode)
        refresher.toggle()
    }

    /// Persists the current tree structure back to the database and triggers
    /// a PDF refresh.
    func saveTree() {
        if let root = resume.rootNode {
            resStore.updateResumeTree(resume: resume, rootNode: root)
        }
    }

    /// Re‑exports the resume JSON → PDF via the debounce mechanism.
    func refreshPDF() { resume.debounceExport() }

    // MARK: - Editing -------------------------------------------------------

    private(set) var editingNodeID: String?
    var tempName: String = ""
    var tempValue: String = ""

    func startEditing(node: TreeNode) {
        editingNodeID = node.id
        tempName = node.name
        tempValue = node.value
    }

    func cancelEditing() {
        editingNodeID = nil
    }

    /// Save edits currently in `tempName` / `tempValue` back to the node and
    /// refresh the PDF.
    func saveEdits() {
        guard let id = editingNodeID, let node = resume.nodes.first(where: { $0.id == id }) else { return }

        node.name = tempName
        node.value = tempValue

        editingNodeID = nil

        // Trigger PDF export and view refresh
        refreshPDF()
        refresher.toggle()
    }

    // MARK: - Expansion state ---------------------------------------------

    func isExpanded(_ node: TreeNode) -> Bool {
        if node.parent == nil { return true } // Root always expanded
        return expandedIDs.contains(node.id)
    }

    func toggleExpansion(for node: TreeNode) {
        if expandedIDs.contains(node.id) {
            expandedIDs.remove(node.id)
        } else {
            expandedIDs.insert(node.id)
        }
        refresher.toggle() // trigger a UI update
    }
}
