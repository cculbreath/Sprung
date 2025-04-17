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
        newNode.isEditing = true
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
}
