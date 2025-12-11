//
//  ResumeUpdateNode.swift
//  Sprung
//
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

    // MARK: - Array Payload Support (for list nodes like keywords, highlights)

    /// Node type: scalar (single value) or list (array of values)
    var nodeType: NodeType = .scalar

    /// Array values for list nodes (nil for scalar nodes)
    var oldValueArray: [String]?
    var newValueArray: [String]?

    /// Per-item feedback for list nodes (populated when user rejects/comments on individual items)
    var itemFeedback: [ItemFeedback]?

    // MARK: - Convenience Accessors

    /// Get all old values (works for both scalar and list nodes)
    var oldValues: [String] {
        if nodeType == .list {
            return oldValueArray ?? []
        } else {
            return oldValue.isEmpty ? [] : [oldValue]
        }
    }

    /// Get all new values (works for both scalar and list nodes)
    var newValues: [String] {
        if nodeType == .list {
            return newValueArray ?? []
        } else {
            return newValue.isEmpty ? [] : [newValue]
        }
    }

    /// Check if this is a list node
    var isList: Bool {
        nodeType == .list
    }

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
    enum CodingKeys: String, CodingKey {
        case id
        case oldValue
        case newValue
        case valueChanged
        case isTitleNode
        case why
        case treePath
        case nodeType
        case oldValueArray
        case newValueArray
        case itemFeedback
    }

    // Custom decoder so that the struct stays compatible with older
    // responses that may *not* include `treePath` or array fields.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        oldValue = try container.decodeIfPresent(String.self, forKey: .oldValue) ?? ""
        newValue = try container.decodeIfPresent(String.self, forKey: .newValue) ?? ""
        valueChanged = try container.decodeIfPresent(Bool.self, forKey: .valueChanged) ?? false
        isTitleNode = try container.decodeIfPresent(Bool.self, forKey: .isTitleNode) ?? false
        why = try container.decodeIfPresent(String.self, forKey: .why) ?? ""
        treePath = try container.decodeIfPresent(String.self, forKey: .treePath) ?? ""

        // Array payload fields (default to scalar mode for backwards compatibility)
        nodeType = try container.decodeIfPresent(NodeType.self, forKey: .nodeType) ?? .scalar
        oldValueArray = try container.decodeIfPresent([String].self, forKey: .oldValueArray)
        newValueArray = try container.decodeIfPresent([String].self, forKey: .newValueArray)
        itemFeedback = try container.decodeIfPresent([ItemFeedback].self, forKey: .itemFeedback)
    }

    // Encodable synthesis is fine.
}
struct RevisionsContainer: Codable {
    var revArray: [ProposedRevisionNode]

    /// Memberwise initializer for direct construction
    init(revArray: [ProposedRevisionNode]) {
        self.revArray = revArray
    }

    /// Custom coding keys to handle case variations from different LLM responses
    enum CodingKeys: String, CodingKey {
        case revArray = "revArray"
        case revArrayUppercase = "RevArray"  // Handle uppercase variant from LLMs
    }
    /// Custom decoder to handle both revArray and RevArray keys
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Try lowercase first, then uppercase
        if let array = try? container.decode([ProposedRevisionNode].self, forKey: .revArray) {
            self.revArray = array
        } else if let array = try? container.decode([ProposedRevisionNode].self, forKey: .revArrayUppercase) {
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

// MARK: - Generic Manifest-Driven Review Phase Types

/// Actions the LLM can propose for any review item
enum ReviewItemAction: String, Codable {
    case keep       // No changes to this item
    case modify     // Modify the value
    case remove     // Remove this item entirely
    case add        // Add a new item (LLM suggestion)
}

/// User's decision about a review item
enum ReviewUserDecision: String, Codable {
    case pending              // No decision yet
    case accepted             // Accept proposed value (or edited value if editedValue is set)
    case acceptedOriginal     // Revert to original value, mark as done
    case rejected             // Reject without comment, skip this item
    case rejectedWithFeedback // Reject with comment, triggers LLM resubmission
}

/// A node exported for LLM review - generic for any path pattern
struct ExportedReviewNode: Codable, Equatable, Identifiable {
    let id: String              // Node ID from tree (for applying changes), or "bundled-{pattern}" for bundles
    let path: String            // Full path (e.g., "skills.0.name") or pattern (e.g., "skills.*.name")
    let displayName: String     // Human-readable name (e.g., "Programming Languages")
    let value: String           // Current value (for scalar) or concatenated (for container)
    let childValues: [String]?  // For containers, the individual child values
    let childCount: Int         // Count of children (0 for scalars)
    let isBundled: Bool         // True if this is a bundled node from * pattern
    let sourceNodeIds: [String]? // Original node IDs when bundled (for applying changes back)

    var isContainer: Bool { childCount > 0 }

    init(
        id: String,
        path: String,
        displayName: String,
        value: String,
        childValues: [String]? = nil,
        childCount: Int = 0,
        isBundled: Bool = false,
        sourceNodeIds: [String]? = nil
    ) {
        self.id = id
        self.path = path
        self.displayName = displayName
        self.value = value
        self.childValues = childValues
        self.childCount = childCount
        self.isBundled = isBundled
        self.sourceNodeIds = sourceNodeIds
    }
}

/// A single review item from the LLM response - generic for any phase
struct PhaseReviewItem: Codable, Equatable, Identifiable {
    var id: String                          // Maps back to ExportedReviewNode.id
    var displayName: String                 // Human-readable name
    var originalValue: String               // Original value
    var proposedValue: String               // Proposed new value (same as original if keep)
    var action: ReviewItemAction            // What the LLM proposes
    var reason: String                      // Why this change
    var userDecision: ReviewUserDecision    // User's response (not set by LLM)
    var userComment: String                 // User's comment when rejecting (not set by LLM)
    var editedValue: String?                // User's edited value (when editing before accepting)
    var editedChildren: [String]?           // User's edited children (for container items)

    // For containers with children
    var originalChildren: [String]?         // Original child values
    var proposedChildren: [String]?         // Proposed child values

    /// The effective value to apply - considers user edits and decision
    var effectiveValue: String {
        if userDecision == .acceptedOriginal {
            return originalValue
        }
        return editedValue ?? proposedValue
    }

    /// The effective children to apply - considers user edits and decision
    var effectiveChildren: [String]? {
        if userDecision == .acceptedOriginal {
            return originalChildren
        }
        return editedChildren ?? proposedChildren
    }

    enum CodingKeys: String, CodingKey {
        case id, displayName, originalValue, proposedValue, action, reason
        case userDecision, userComment, editedValue, editedChildren
        case originalChildren, proposedChildren
    }

    init(
        id: String,
        displayName: String,
        originalValue: String,
        proposedValue: String,
        action: ReviewItemAction = .keep,
        reason: String = "",
        userDecision: ReviewUserDecision = .pending,
        userComment: String = "",
        editedValue: String? = nil,
        editedChildren: [String]? = nil,
        originalChildren: [String]? = nil,
        proposedChildren: [String]? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.originalValue = originalValue
        self.proposedValue = proposedValue
        self.action = action
        self.reason = reason
        self.userDecision = userDecision
        self.userComment = userComment
        self.editedValue = editedValue
        self.editedChildren = editedChildren
        self.originalChildren = originalChildren
        self.proposedChildren = proposedChildren
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        originalValue = try container.decode(String.self, forKey: .originalValue)
        proposedValue = try container.decode(String.self, forKey: .proposedValue)
        action = try container.decode(ReviewItemAction.self, forKey: .action)
        reason = try container.decode(String.self, forKey: .reason)
        // User fields default - not set by LLM
        userDecision = try container.decodeIfPresent(ReviewUserDecision.self, forKey: .userDecision) ?? .pending
        userComment = try container.decodeIfPresent(String.self, forKey: .userComment) ?? ""
        editedValue = try container.decodeIfPresent(String.self, forKey: .editedValue)
        editedChildren = try container.decodeIfPresent([String].self, forKey: .editedChildren)
        originalChildren = try container.decodeIfPresent([String].self, forKey: .originalChildren)
        proposedChildren = try container.decodeIfPresent([String].self, forKey: .proposedChildren)
    }
}

/// Container for a phase's review results from the LLM
struct PhaseReviewContainer: Codable {
    var section: String              // Section name (e.g., "skills")
    var phaseNumber: Int             // Phase number (1-indexed)
    var fieldPath: String            // Field path pattern (e.g., "skills.*.name")
    var isBundled: Bool              // Whether items were bundled for review
    var items: [PhaseReviewItem]     // Review items

    enum CodingKeys: String, CodingKey {
        case section
        case phaseNumber = "phase"
        case fieldPath = "field"
        case isBundled = "bundled"
        case items
    }
}

/// State for tracking multi-phase review workflow
struct PhaseReviewState {
    var isActive: Bool = false
    var currentSection: String = ""
    var phases: [TemplateManifest.ReviewPhaseConfig] = []
    var currentPhaseIndex: Int = 0
    var currentReview: PhaseReviewContainer?
    var approvedReviews: [PhaseReviewContainer] = []

    // For unbundled phases: track pending items
    var pendingItemIds: [String] = []
    var currentItemIndex: Int = 0

    var currentPhase: TemplateManifest.ReviewPhaseConfig? {
        guard currentPhaseIndex < phases.count else { return nil }
        return phases[currentPhaseIndex]
    }

    var isLastPhase: Bool {
        currentPhaseIndex >= phases.count - 1
    }

    mutating func reset() {
        isActive = false
        currentSection = ""
        phases = []
        currentPhaseIndex = 0
        currentReview = nil
        approvedReviews = []
        pendingItemIds = []
        currentItemIndex = 0
    }
}

/// Node type distinguishes scalar (single value) from list (array of values) nodes
enum NodeType: String, Codable {
    case scalar  // Single string value (existing behavior)
    case list    // Array of string values (keywords, highlights)
}

/// Per-item feedback for list nodes (e.g., work highlights, skill keywords)
struct ItemFeedback: Codable, Equatable, Identifiable {
    var id: Int { index }  // Use index as ID for Identifiable
    var index: Int
    var status: ItemStatus = .pending
    var comment: String = ""

    enum ItemStatus: String, Codable {
        case pending
        case accepted
        case rejected
        case rejectedWithComment
    }
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
            // Apply the change based on whether this feedback is for title or value
            if isTitleNode {
                // This feedback is for the title/name field
                treeNode.name = proposedRevision
                // Don't modify treeNode.isTitleNode - that's a structural property
            } else {
                // This feedback is for the value field
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
// MARK: - Collection Extensions for Review Workflow Logic
@MainActor
extension Array where Element == FeedbackNode {
    /// Apply all accepted changes to the resume
    /// Moved from ReviewView for better encapsulation
    func applyAcceptedChanges(to resume: Resume, exportCoordinator: ResumeExportCoordinator) {
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
            if let context = resume.modelContext {
                // Ensure deletion happens on main actor for UI coordination
                Task { @MainActor in
                    // Batch delete all empty nodes
                    for nodeToDelete in nodesToDelete {
                        TreeNode.deleteTreeNode(node: nodeToDelete, context: context)
                    }
                    // Save once after all deletions
                    do {
                        try context.save()
                        Logger.debug("✅ Successfully saved context after deleting empty nodes")
                    } catch {
                        Logger.error("❌ Failed to save context after deleting TreeNodes: \(error)")
                    }
                }
            }
        }
        // Trigger PDF refresh
        exportCoordinator.debounceExport(resume: resume)
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
