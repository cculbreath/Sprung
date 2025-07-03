//
//  ResumeUpdateNode.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/9/24.
//

import Foundation
import PDFKit
import AppKit
import SwiftUI
import SwiftData

struct ProposedRevisionNode: Codable, Equatable {
    var id: String = ""
    var oldValue: String = ""
    var newValue: String = ""
    var valueChanged: Bool = false
    var isTitleNode: Bool = false
    var why: String = ""
    var treePath: String = ""

    // `value` has been removed. `treePath` is retained so the model can
    // provide a hierarchical hint when an ID match is ambiguous.

    // Default initializer
    init() {}
    
    /// Get the original text for this revision node, with fallback logic
    /// Moved from ReviewView for better encapsulation
    func originalText(using updateNodes: [[String: Any]]) -> String {
        let trimmedOld = oldValue.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Debug logging to help diagnose the issue
        Logger.debug("🔍 ProposedRevisionNode.originalText - ID: \(id), isTitleNode: \(isTitleNode), oldValue: '\(oldValue)'")

        if !trimmedOld.isEmpty {
            Logger.debug("✅ Using oldValue: '\(trimmedOld)'")
            return trimmedOld
        }

        // Find the matching node in updateNodes by ID and isTitleNode flag
        if let dict = updateNodes.first(where: { 
            ($0["id"] as? String) == id && 
            ($0["isTitleNode"] as? Bool) == isTitleNode 
        }) {
            Logger.debug("🎯 Found matching updateNode: \(dict)")
            // Always use the "value" field from updateNodes - this contains the correct content
            // whether it's a title node (name) or content node (value)
            if let fieldValue = (dict["value"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !fieldValue.isEmpty {
                Logger.debug("✅ Using updateNode value: '\(fieldValue)'")
                return fieldValue
            }
        } else {
            Logger.debug("❌ No matching updateNode found for ID: \(id), isTitleNode: \(isTitleNode)")
            // List all available updateNodes for debugging
            for (index, node) in updateNodes.enumerated() {
                let nodeId = node["id"] as? String ?? "nil"
                let nodeIsTitleNode = node["isTitleNode"] as? Bool ?? false
                let nodeValue = node["value"] as? String ?? "nil"
                Logger.debug("  updateNode[\(index)]: id=\(nodeId), isTitleNode=\(nodeIsTitleNode), value='\(nodeValue.prefix(50))...'")
            }
        }
        
        Logger.debug("⚠️ Fallback to '(no text)'")
        return "(no text)"
    }
    
    /// Create a FeedbackNode from this ProposedRevisionNode
    func createFeedbackNode() -> FeedbackNode {
        return FeedbackNode(
            id: id,
            originalValue: oldValue,
            proposedRevision: newValue,
            actionRequested: .unevaluated,
            reviewerComments: "",
            isTitleNode: isTitleNode
        )
    }
    
    // Dictionary initializer for creating from [String: Any]
    init(from dict: [String: Any]) {
        // Map common keys with fallbacks
        if let id = dict["id"] as? String {
            self.id = id
        } else if let id = dict["ID"] as? String {
            self.id = id
        } else {
            self.id = UUID().uuidString
        }
        
        // Old value with fallbacks
        if let oldValue = dict["oldValue"] as? String {
            self.oldValue = oldValue
        } else if let oldValue = dict["old_value"] as? String {
            self.oldValue = oldValue
        } else if let oldValue = dict["original"] as? String {
            self.oldValue = oldValue
        }
        
        // New value with fallbacks
        if let newValue = dict["newValue"] as? String {
            self.newValue = newValue
        } else if let newValue = dict["new_value"] as? String {
            self.newValue = newValue
        } else if let newValue = dict["value"] as? String {
            self.newValue = newValue
        } else if let newValue = dict["revision"] as? String {
            self.newValue = newValue
        }
        
        // Value changed
        if let valueChanged = dict["valueChanged"] as? Bool {
            self.valueChanged = valueChanged
        } else if let valueChanged = dict["value_changed"] as? Bool {
            self.valueChanged = valueChanged
        } else if let valueChanged = dict["changed"] as? Bool {
            self.valueChanged = valueChanged
        } else {
            self.valueChanged = self.oldValue != self.newValue
        }
        
        // Why/explanation
        if let why = dict["why"] as? String {
            self.why = why
        } else if let why = dict["explanation"] as? String {
            self.why = why
        } else if let why = dict["reasoning"] as? String {
            self.why = why
        } else if let why = dict["reason"] as? String {
            self.why = why
        } else {
            self.why = "No explanation provided"
        }
        
        // Is title node
        if let isTitleNode = dict["isTitleNode"] as? Bool {
            self.isTitleNode = isTitleNode
        } else if let isTitleNode = dict["is_title_node"] as? Bool {
            self.isTitleNode = isTitleNode
        } else if let isTitleNode = dict["isTitle"] as? Bool {
            self.isTitleNode = isTitleNode
        }
        
        // Tree path
        if let treePath = dict["treePath"] as? String {
            self.treePath = treePath
        } else if let treePath = dict["tree_path"] as? String {
            self.treePath = treePath
        } else if let treePath = dict["path"] as? String {
            self.treePath = treePath
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case oldValue
        case newValue
        case valueChanged
        case isTitleNode
        case why
        case treePath
    }

    // Custom decoder so that the struct stays compatible with older
    // responses that may *not* include `treePath`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        oldValue = try container.decodeIfPresent(String.self, forKey: .oldValue) ?? ""
        newValue = try container.decodeIfPresent(String.self, forKey: .newValue) ?? ""
        valueChanged = try container.decodeIfPresent(Bool.self, forKey: .valueChanged) ?? false
        isTitleNode = try container.decodeIfPresent(Bool.self, forKey: .isTitleNode) ?? false
        why = try container.decodeIfPresent(String.self, forKey: .why) ?? ""
        treePath = try container.decodeIfPresent(String.self, forKey: .treePath) ?? ""
    }
    // Encodable synthesis is fine.
}

struct RevisionsContainer: Codable, StructuredOutput {
    var revArray: [ProposedRevisionNode]
    
    /// Custom coding keys to handle case variations from different LLM responses
    enum CodingKeys: String, CodingKey {
        case revArray = "revArray"
        case RevArray = "RevArray"  // Handle uppercase variant
    }
    
    /// Custom decoder to handle both revArray and RevArray keys
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Try lowercase first, then uppercase
        if let array = try? container.decode([ProposedRevisionNode].self, forKey: .revArray) {
            self.revArray = array
        } else if let array = try? container.decode([ProposedRevisionNode].self, forKey: .RevArray) {
            self.revArray = array
        } else {
            throw DecodingError.keyNotFound(CodingKeys.revArray, 
                DecodingError.Context(codingPath: decoder.codingPath, 
                                    debugDescription: "Neither 'revArray' nor 'RevArray' found in response"))
        }
    }
    
    /// Custom encoder to always use lowercase revArray
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(revArray, forKey: .revArray)
    }
    
    /// Validate the revisions container
    /// - Returns: True if valid, false otherwise
    func validate() -> Bool {
        // Check if we have any revisions
        guard !revArray.isEmpty else {
            return false
        }
        
        // Basic validation of revision nodes
        for revision in revArray {
            if revision.id.isEmpty || revision.oldValue.isEmpty || revision.newValue.isEmpty {
                return false
            }
        }
        
        return true
    }
}

enum PostReviewAction: String, Codable {
    case accepted = "No action required. Revision Accepted."
    case acceptedWithChanges = "No action required. Revision Accepted with reviewer changes."
    case noChange = "No action required. Original value retained as recommended."
    case restored = "No action Required. Revision rejected and original value restored."
    case revise =
        "Action Required: Please update your submission to incorporate the reviewer comments."
    case rewriteNoComment = "Action Required: Revsion rejected without comment, please try again."
    case mandatedChangeNoComment = "Action Required:  Proposal to maintain original value rejected without comment. Please propose a  revised value for this field."
    case mandatedChange =
        "Action Required: Proposal to maintain original value rejected. Please propose a  revised value for this field and incorporate reviewer comments"
    case unevaluated = "Unevaluated"
}

@Observable class FeedbackNode {
    var id: String
    var originalValue: String
    var proposedRevision: String = ""
    var actionRequested: PostReviewAction = .unevaluated
    var reviewerComments: String = ""
    var isTitleNode: Bool = false
    
    init(
        id: String = "",
        originalValue: String = "",
        proposedRevision: String = "",
        actionRequested: PostReviewAction = .unevaluated,
        reviewerComments: String = "",
        isTitleNode: Bool = false
    ) {
        self.id = id
        self.originalValue = originalValue
        self.proposedRevision = proposedRevision
        self.actionRequested = actionRequested
        self.reviewerComments = reviewerComments
        self.isTitleNode = isTitleNode
    }
    
    /// Check if this feedback node requires AI resubmission
    var requiresAIResubmission: Bool {
        let aiActions: Set<PostReviewAction> = [
            .revise, .mandatedChange, .mandatedChangeNoComment, .rewriteNoComment
        ]
        return aiActions.contains(actionRequested)
    }
    
    /// Check if this feedback node should be applied to the resume
    var shouldBeApplied: Bool {
        return actionRequested == .accepted || actionRequested == .acceptedWithChanges
    }
    
    /// Apply this feedback node's changes to a resume tree node
    func applyToResume(_ resume: Resume) {
        guard shouldBeApplied else { return }
        
        if let treeNode = resume.nodes.first(where: { $0.id == id }) {
            // Apply the change based on whether it's a title node or value node
            if isTitleNode {
                treeNode.name = proposedRevision
                treeNode.isTitleNode = true
            } else {
                treeNode.value = proposedRevision
            }
            Logger.debug("✅ Applied change to node \(id): \(actionRequested.rawValue)")
        } else {
            Logger.debug("⚠️ Could not find TreeNode with ID: \(id) to apply changes")
        }
    }
    
    /// Handle the action for saveAndNext workflow
    func processAction(_ action: PostReviewAction) {
        self.actionRequested = action
        
        switch action {
        case .restored:
            self.proposedRevision = self.originalValue
        case .acceptedWithChanges:
            // proposedRevision should already be set by user editing
            break
        default:
            // For other actions, proposedRevision stays as is
            break
        }
    }
}

extension FeedbackNode: Encodable {
    enum CodingKeys: String, CodingKey {
        case id
        case originalValue
        case proposedRevision
        case actionRequested
        case reviewerComments
        case isTitleNode
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(originalValue, forKey: .originalValue)
        try container.encode(proposedRevision, forKey: .proposedRevision)
        try container.encode(actionRequested, forKey: .actionRequested)
        try container.encode(reviewerComments, forKey: .reviewerComments)
        try container.encode(isTitleNode, forKey: .isTitleNode)
    }
}

func fbToJson(_ feedbackNodes: [FeedbackNode]) -> String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted // Optional: makes the JSON output more readable
    do {
        let jsonData = try encoder.encode(feedbackNodes)
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        } else {
            return nil
        }
    } catch {
        return nil
    }
}

// MARK: - Collection Extensions for Review Workflow Logic

extension Array where Element == FeedbackNode {
    
    /// Apply all accepted changes to the resume
    /// Moved from ReviewView for better encapsulation
    func applyAcceptedChanges(to resume: Resume) {
        Logger.debug("✅ Applying accepted changes to resume")
        
        let acceptedNodes = filter { $0.shouldBeApplied }
        for node in acceptedNodes {
            node.applyToResume(resume)
        }
        
        // After applying all changes, check for nodes that should be deleted
        // Delete any TreeNodes where both name and value are empty
        let nodesToDelete = resume.nodes.filter { treeNode in
            let nameIsEmpty = treeNode.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let valueIsEmpty = treeNode.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return nameIsEmpty && valueIsEmpty
        }
        
        if !nodesToDelete.isEmpty {
            Logger.debug("🗑️ Deleting \(nodesToDelete.count) empty nodes")
            for nodeToDelete in nodesToDelete {
                if let context = resume.modelContext {
                    TreeNode.deleteTreeNode(node: nodeToDelete, context: context)
                }
            }
        }
        
        // Trigger PDF refresh
        resume.debounceExport()
        Logger.debug("✅ Applied \(acceptedNodes.count) accepted changes")
    }
    
    /// Get nodes that require AI resubmission
    var nodesRequiringAIResubmission: [FeedbackNode] {
        return filter { $0.requiresAIResubmission }
    }
    
    /// Log feedback statistics (moved from ReviewView)
    func logFeedbackStatistics() {
        Logger.debug("\n===== FEEDBACK NODE STATISTICS =====")
        Logger.debug("Total feedback nodes: \(count)")

        let acceptedCount = filter { $0.actionRequested == .accepted }.count
        let acceptedWithChangesCount = filter { $0.actionRequested == .acceptedWithChanges }.count
        let noChangeCount = filter { $0.actionRequested == .noChange }.count
        let restoredCount = filter { $0.actionRequested == .restored }.count
        let reviseCount = filter { $0.actionRequested == .revise }.count
        let rewriteNoCommentCount = filter { $0.actionRequested == .rewriteNoComment }.count
        let mandatedChangeCount = filter { $0.actionRequested == .mandatedChange }.count
        let mandatedChangeNoCommentCount = filter { $0.actionRequested == .mandatedChangeNoComment }.count

        Logger.debug("Accepted: \(acceptedCount)")
        Logger.debug("Accepted with changes: \(acceptedWithChangesCount)")
        Logger.debug("No change needed: \(noChangeCount)")
        Logger.debug("Restored to original: \(restoredCount)")
        Logger.debug("Revise (with comments): \(reviseCount)")
        Logger.debug("Rewrite (no comments): \(rewriteNoCommentCount)")
        Logger.debug("Mandated change (with comments): \(mandatedChangeCount)")
        Logger.debug("Mandated change (no comments): \(mandatedChangeNoCommentCount)")
        Logger.debug("==================================\n")
    }
    
    /// Log resubmission summary (moved from ReviewView)
    func logResubmissionSummary() {
        Logger.debug("\n===== SUBMITTING REVISION REQUEST =====")
        Logger.debug("Number of nodes to revise: \(count)")

        // Count by feedback type
        let typeCount = reduce(into: [PostReviewAction: Int]()) { counts, node in
            counts[node.actionRequested, default: 0] += 1
        }

        for (action, count) in typeCount.sorted(by: { $0.value > $1.value }) {
            Logger.debug("  - \(action.rawValue): \(count) nodes")
        }

        // List node IDs being submitted
        let nodeIds = map { $0.id }.joined(separator: ", ")
        Logger.debug("Node IDs: \(nodeIds)")
        Logger.debug("========================================\n")
        
        // Log individual nodes
        for (index, node) in enumerated() {
            Logger.debug("Node \(index + 1)/\(count) for revision:")
            Logger.debug("  - ID: \(node.id)")
            Logger.debug("  - Action: \(node.actionRequested.rawValue)")
            Logger.debug("  - Original: \(node.originalValue.prefix(30))\(node.originalValue.count > 30 ? "..." : "")")
            if !node.reviewerComments.isEmpty {
                Logger.debug("  - Comments: \(node.reviewerComments.prefix(50))\(node.reviewerComments.count > 50 ? "..." : "")")
            }
        }
    }
}
