// Sprung/ResumeTree/Models/TreeNodeModel.swift
import Foundation
import SwiftData
enum LeafStatus: String, Codable, Hashable {
    case isEditing
    case aiToReplace
    case disabled = "leafDisabled"
    case saved = "leafValueSaved"
    case isNotLeaf = "nodeIsNotLeaf"
}
@Model class TreeNode: Identifiable {
    var id = UUID().uuidString
    var name: String = ""
    var value: String
    var includeInEditor: Bool = false
    var myIndex: Int = -1 // Represents order within its parent's children array
    @Relationship(deleteRule: .cascade) var children: [TreeNode]? = nil
    @Relationship(deleteRule: .cascade) var viewChildren: [TreeNode]? = nil
    weak var parent: TreeNode?
    var label: String { return resume.label(name) } // Assumes resume.label handles missing keys
    var editorLabel: String?
    /// Returns the effective display label: editorLabel if set, otherwise falls back to label
    var displayLabel: String {
        return editorLabel ?? label
    }
    @Relationship(deleteRule: .noAction) var resume: Resume
    var status: LeafStatus
    var depth: Int = 0
    /// Presentation depth derived from `viewChildren` hierarchy.
    var viewDepth: Int = 0
    // Schema metadata (optional, derived from manifest descriptors)
    var schemaKey: String?
    var schemaInputKindRaw: String?
    var schemaRequired: Bool = false
    var schemaRepeatable: Bool = false
    var schemaPlaceholder: String?
    var schemaTitleTemplate: String?
    var schemaValidationRule: String?
    var schemaValidationMessage: String?
    var schemaValidationPattern: String?
    var schemaValidationMin: Double?
    var schemaValidationMax: Double?
    @Attribute(.externalStorage)
    private var schemaValidationOptionsData: Data?
    var schemaValidationOptions: [String] {
        get {
            guard let schemaValidationOptionsData,
                  let decoded = try? JSONDecoder().decode([String].self, from: schemaValidationOptionsData) else {
                return []
            }
            return decoded
        }
        set {
            schemaValidationOptionsData = try? JSONEncoder().encode(newValue)
        }
    }
    var schemaSourceKey: String?
    /// Indicates whether the manifest allows adding/removing child entries for this node.
    var schemaAllowsChildMutation: Bool = false
    /// Indicates whether this node can be deleted by the user per manifest metadata.
    var schemaAllowsNodeDeletion: Bool = false
    /// When true, the node is hidden in the editor but its children should be surfaced as if they belonged to the parent.
    var editorTransparent: Bool = false
    // This property should be explicitly set when a node is created or its role changes.
    // It's not reliably computable based on name/value alone.
    // For the "Fix Overflow" feature, we will pass this to the LLM and expect it back.
    var isTitleNode: Bool = false
    var hasChildren: Bool {
        return !(children?.isEmpty ?? true)
    }
    var schemaInputKind: TemplateManifest.Section.FieldDescriptor.InputKind? {
        schemaInputKindRaw.flatMap { TemplateManifest.Section.FieldDescriptor.InputKind(rawValue: $0) }
    }
    var orderedChildren: [TreeNode] {
        (children ?? []).sorted { $0.myIndex < $1.myIndex }
    }
    var orderedViewChildren: [TreeNode] {
        (viewChildren ?? []).sorted { $0.myIndex < $1.myIndex }
    }
    var aiStatusChildren: Int {
        var count = 0
        if status == .aiToReplace {
            count += 1
        }
        if let children = children {
            for child in children {
                count += child.aiStatusChildren
            }
        }
        return count
    }
    init(
        name: String, value: String = "", children: [TreeNode]? = nil,
        parent: TreeNode? = nil, inEditor: Bool, status: LeafStatus = LeafStatus.disabled,
        resume: Resume, isTitleNode: Bool = false // Added isTitleNode to initializer
    ) {
        self.name = name
        self.value = value
        self.children = children
        self.parent = parent
        self.status = status
        includeInEditor = inEditor
        depth = parent.map { $0.depth + 1 } ?? 0
        viewDepth = parent.map { $0.viewDepth + 1 } ?? 0
        self.resume = resume
        self.isTitleNode = isTitleNode // Initialize isTitleNode
    }
    @discardableResult
    func addChild(_ child: TreeNode) -> TreeNode {
        if children == nil {
            children = []
        }
        child.parent = self
        child.myIndex = (children?.count ?? 0)
        child.depth = depth + 1
        child.viewDepth = viewDepth + 1
        if editorTransparent {
            child.depth = depth
            child.viewDepth = viewDepth
        }
        children?.append(child)
        return child
    }
    static func traverseAndExportNodes(node: TreeNode, currentPath _: String = "")
        -> [[String: Any]]
    {
        var result: [[String: Any]] = []
        let newPath = node.buildTreePath() // Use the instance method
        // Export node if it's marked for AI replacement OR if it's a title node (even if not for replacement, LLM might need context)
        // For "Fix Overflow", we are specifically interested in nodes from the "Skills & Expertise" section,
        // which will be filtered by the caller (extractSkillsForLLM in ResumeReviewService).
        // This function is more general for AI updates.
        if node.status == .aiToReplace {
            // First, handle title node content if present (name field)
            if !node.name.isEmpty { // Always export name field as a title node if it's not empty
                let titleNodeData: [String: Any] = [
                    "id": node.id,
                    "value": node.name, // Exporting node.name as "value" for the LLM
                    "name": node.name, // Also include the actual name field for context
                    "tree_path": newPath, // Path to this node
                    "isTitleNode": true, // Explicitly mark as title node
                ]
                result.append(titleNodeData)
            }
            // Then, handle value node content if present
            if !node.value.isEmpty { // Always export value field as a content node if it's not empty
                let valueNodeData: [String: Any] = [
                    "id": node.id,
                    "value": node.value, // Exporting node.value
                    "name": node.name, // Include name for context/reference
                    "tree_path": newPath,
                    "isTitleNode": false, // Explicitly mark as not a title node
                ]
                result.append(valueNodeData)
            }
        }
        // Force load children to ensure SwiftData loads the relationship
        let childNodes = node.children ?? []
        for child in childNodes {
            // Pass the child's full path for its children's context
            result.append(contentsOf: traverseAndExportNodes(node: child, currentPath: newPath))
        }
        return result
    }
    static func deleteTreeNode(node: TreeNode, context: ModelContext) {
        guard node.allowsDeletion else {
            Logger.warning("🚫 Prevented deletion of node '\(node.name)' without manifest permission.")
            return
        }
        for child in node.children ?? [] {
            deleteTreeNode(node: child, context: context)
        }
        if let parent = node.parent, let index = parent.children?.firstIndex(of: node) {
            parent.children?.remove(at: index)
        }
        context.delete(node)
        // Note: save() is not called here to allow for batch operations
    }
    /// Builds the hierarchical path string for this node.
    /// Example: "Resume > Skills and Expertise > Software > Swift"
    func buildTreePath() -> String {
        var pathComponents: [String] = []
        var currentNode: TreeNode? = self
        while let node = currentNode {
            var componentName = "Unnamed Node"
            if !node.name.isEmpty {
                componentName = node.name
            } else if !node.value.isEmpty {
                componentName = String(node.value.prefix(20)) + (node.value.count > 20 ? "..." : "")
            }
            if node.parent == nil && node.name.lowercased() == "root" { // Check for root specifically
                componentName = "Resume"
            }
            pathComponents.insert(componentName, at: 0)
            currentNode = node.parent
        }
        return pathComponents.joined(separator: " > ")
    }
}
extension TreeNode {
    func applyDescriptor(_ descriptor: TemplateManifest.Section.FieldDescriptor?) {
        schemaKey = descriptor?.key
        schemaInputKindRaw = descriptor?.input?.rawValue
        schemaRequired = descriptor?.required ?? false
        schemaRepeatable = descriptor?.repeatable ?? false
        schemaPlaceholder = descriptor?.placeholder
        schemaTitleTemplate = descriptor?.titleTemplate
        schemaAllowsChildMutation = descriptor?.allowsManualMutations ?? false
        schemaAllowsNodeDeletion = descriptor?.allowsManualMutations ?? false
        if let validation = descriptor?.validation {
            schemaValidationRule = validation.rule.rawValue
            schemaValidationMessage = validation.message
            schemaValidationPattern = validation.pattern
            schemaValidationMin = validation.min
            schemaValidationMax = validation.max
            schemaValidationOptions = validation.options ?? []
        } else {
            schemaValidationRule = nil
            schemaValidationMessage = nil
            schemaValidationPattern = nil
            schemaValidationMin = nil
            schemaValidationMax = nil
            schemaValidationOptions = []
        }
    }
}
// MARK: - Schema convenience -------------------------------------------------
extension TreeNode {
    func copySchemaMetadata(from source: TreeNode) {
        schemaKey = source.schemaKey
        schemaInputKindRaw = source.schemaInputKindRaw
        schemaRequired = source.schemaRequired
        schemaRepeatable = source.schemaRepeatable
        schemaPlaceholder = source.schemaPlaceholder
        schemaTitleTemplate = source.schemaTitleTemplate
        schemaValidationRule = source.schemaValidationRule
        schemaValidationMessage = source.schemaValidationMessage
        schemaValidationPattern = source.schemaValidationPattern
        schemaValidationMin = source.schemaValidationMin
        schemaValidationMax = source.schemaValidationMax
        schemaValidationOptions = source.schemaValidationOptions
        schemaSourceKey = source.schemaSourceKey
        schemaAllowsChildMutation = source.schemaAllowsChildMutation
        schemaAllowsNodeDeletion = source.schemaAllowsNodeDeletion
    }
    func makeTemplateClone(for resume: Resume) -> TreeNode {
        let baseName: String
        if let titleTemplate = schemaTitleTemplate, titleTemplate.isEmpty == false {
            baseName = "New Item"
        } else if let placeholder = schemaPlaceholder, placeholder.isEmpty == false {
            baseName = placeholder
        } else if name.isEmpty == false {
            baseName = "New \(name)"
        } else {
            baseName = name
        }
        let clone = TreeNode(
            name: baseName,
            value: "",
            children: nil,
            parent: nil,
            inEditor: includeInEditor,
            status: .saved,
            resume: resume,
            isTitleNode: isTitleNode
        )
        clone.editorTransparent = editorTransparent
        clone.copySchemaMetadata(from: self)
        if !hasChildren {
            if let placeholder = schemaPlaceholder, placeholder.isEmpty == false {
                clone.value = placeholder
            } else {
                clone.value = ""
            }
        }
        for child in orderedChildren {
            let childClone = child.makeTemplateClone(for: resume)
            clone.addChild(childClone)
        }
        return clone
    }
    /// Determines whether the node's label ("name") should be editable in the UI.
    /// Manifest-backed nodes typically provide explicit titles, so we hide the name field
    /// unless the node lacks schema metadata.
    var allowsInlineNameEditing: Bool {
        if parent?.name == "section-labels" { return false }
        if schemaTitleTemplate != nil { return false }
        if schemaInputKind != nil { return false }
        if schemaKey != nil { return false }
        if parent?.schemaInputKind != nil { return false }
        if parent?.schemaTitleTemplate != nil { return false }
        if let parentKey = parent?.schemaKey, !parentKey.isEmpty { return false }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        return true
    }
    var allowsChildAddition: Bool {
        schemaAllowsChildMutation
    }
    var allowsDeletion: Bool {
        schemaAllowsNodeDeletion || (parent?.schemaAllowsChildMutation ?? false)
    }
}
// MARK: - JSON Conversion Extension
extension TreeNode {
    /// Convert TreeNode to JSON string representation
    func toJSONString() -> String? {
        do {
            let nodeDict = toDictionary()
            let jsonData = try JSONSerialization.data(withJSONObject: nodeDict, options: [.prettyPrinted])
            return String(data: jsonData, encoding: .utf8)
        } catch {
            Logger.error("Failed to convert TreeNode to JSON: \(error)")
            return nil
        }
    }
    /// Convert TreeNode to dictionary for JSON serialization
    private func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "name": name,
            "value": value,
            "includeInEditor": includeInEditor,
            "myIndex": myIndex
        ]
        if let children = children, !children.isEmpty {
            dict["children"] = children.map { $0.toDictionary() }
        }
        return dict
    }
}
