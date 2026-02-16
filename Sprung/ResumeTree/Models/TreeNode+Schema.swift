// Sprung/ResumeTree/Models/TreeNode+Schema.swift
// Schema metadata convenience extensions for TreeNode.

import Foundation

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
        schemaSourceKey = descriptor?.sourceKey
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

// MARK: - Schema convenience

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
        if parent?.name == "sectionLabels" { return false }
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
