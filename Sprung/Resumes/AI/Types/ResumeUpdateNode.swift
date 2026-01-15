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
