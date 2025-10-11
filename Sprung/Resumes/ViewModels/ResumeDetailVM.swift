//
//  ResumeDetailVM.swift
//  Sprung
//
//  Created by Christopher Culbreath on 4/17/25.
//

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
    private let exportCoordinator: ResumeExportCoordinator

    init(resume: Resume, resStore: ResStore, exportCoordinator: ResumeExportCoordinator) {
        self.resume = resume
        self.resStore = resStore
        self.exportCoordinator = exportCoordinator
    }

    // MARK: - Intents -------------------------------------------------------

    /// Adds a new child node to the given parent. If the parent's existing children
    /// already include both non-empty names and values (i.e. compound entries),
    /// the new node is initialized with placeholder name and value so it renders
    /// in the two-field editor; otherwise it defaults to a single-value entry.
    func addChild(to parent: TreeNode) {
        // Determine if this parent uses both name & value fields in its children
        let usesNameValue = parent.orderedChildren.contains { !$0.name.isEmpty && !$0.value.isEmpty }
        // Set up default placeholders
        let newName: String
        let newValue: String
        if usesNameValue {
            newName = "New Name"
            newValue = "New Value"
        } else {
            newName = ""
            newValue = "New Child"
        }
        let newNode = TreeNode(
            name: newName,
            value: newValue,
            inEditor: true,
            status: .saved,
            resume: resume
        )
        parent.addChild(newNode)
    }

    /// Re‑exports the resume JSON → PDF via the debounce mechanism.
    func refreshPDF() {
        exportCoordinator.debounceExport(resume: resume)
    }

    // MARK: - Editing -------------------------------------------------------

    private(set) var editingNodeID: String?
    var tempName: String = ""
    var tempValue: String = ""
    var validationError: String?

    func startEditing(node: TreeNode) {
        editingNodeID = node.id
        tempName = node.name
        tempValue = node.value
        validationError = nil
    }

    func cancelEditing() {
        editingNodeID = nil
        validationError = nil
    }

    /// Save edits currently in `tempName` / `tempValue` back to the node and
    /// refresh the PDF.
    func saveEdits() {
        guard let id = editingNodeID, let node = resume.nodes.first(where: { $0.id == id }) else { return }

        if let error = validate(node: node, proposedName: tempName, proposedValue: tempValue) {
            validationError = error
            return
        }

        if node.parent?.name == "section-labels" {
            resume.keyLabels[node.name] = tempValue
            node.value = tempValue
        } else {
            node.name = tempName
            node.value = tempValue
        }

        editingNodeID = nil
        validationError = nil

        // Trigger PDF export and view refresh
        refreshPDF()
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
    }
    
    // MARK: - Bulk Operations ---------------------------------------------
    
    /// Set all child nodes to AI status (.aiToReplace)
    func setAllChildrenToAI(for parent: TreeNode) {
        for child in parent.orderedChildren {
            child.status = .aiToReplace
        }
        refreshPDF()
    }
    
    /// Set all child nodes to saved status (.saved)
    func setAllChildrenToNone(for parent: TreeNode) {
        for child in parent.orderedChildren {
            child.status = .saved
        }
        refreshPDF()
    }

    // MARK: - Validation -------------------------------------------------

    private func validate(node: TreeNode, proposedName: String, proposedValue: String) -> String? {
        let trimmed = proposedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if node.schemaRequired && trimmed.isEmpty {
            return node.schemaValidationMessage ?? "This field is required."
        }

        guard let rule = node.schemaValidationRule else { return nil }

        switch rule {
        case "minLength":
            if let min = node.schemaValidationMin,
               Double(trimmed.count) < min {
                return node.schemaValidationMessage ?? "Please provide more detail."
            }
        case "regex":
            if let pattern = node.schemaValidationPattern,
               let regex = try? NSRegularExpression(pattern: pattern),
               regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) == nil {
                return node.schemaValidationMessage ?? "Value does not match the expected format."
            }
        case "email":
            let pattern = node.schemaValidationPattern ?? "^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) == nil {
                return node.schemaValidationMessage ?? "Enter a valid email address."
            }
        case "url":
            guard let url = URL(string: trimmed), url.scheme != nil else {
                return node.schemaValidationMessage ?? "Enter a valid URL."
            }
        case "phone":
            let pattern = node.schemaValidationPattern ?? "^[0-9+()\\-\\s]{7,}$"
            if let regex = try? NSRegularExpression(pattern: pattern),
               regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) == nil {
                return node.schemaValidationMessage ?? "Enter a valid phone number."
            }
        case "enumeration":
            if !node.schemaValidationOptions.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                return node.schemaValidationMessage ?? "Value must match one of the allowed options."
            }
        default:
            break
        }

        return nil
    }
}
