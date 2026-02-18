//
//  ExperienceDefaultsToTree+TemplateFields.swift
//  Sprung
//
//  Builds the styling and template subtrees from manifest defaults.
//  Font sizes (styling.fontSizes) and section labels (template.sectionLabels)
//  are template-configuration nodes, not resume content.
//

import Foundation

@MainActor
extension ExperienceDefaultsToTree {

    // MARK: - Editable Template Fields

    /// Build editable template fields from manifest defaults.
    ///
    /// Creates two top-level nodes:
    /// - "styling": Contains fontSizes (special-cased, used by FontSizePanelView)
    /// - "template": Contains manifest-defined fields like sectionLabels (rendered generically)
    ///
    /// These are stored in TreeNode for editing and merged into context at render time.
    func buildEditableTemplateFields(parent: TreeNode) {
        // Build styling node with fontSizes (special-cased for FontSizePanelView)
        buildStylingNode(parent: parent)

        // Build template node with manifest-defined fields (rendered generically)
        buildTemplateNode(parent: parent)
    }

    /// Build the styling node containing fontSizes.
    /// FontSizes is special-cased because it has a dedicated panel (FontSizePanelView).
    private func buildStylingNode(parent: TreeNode) {
        guard let stylingSection = manifest.section(for: "styling"),
              let defaultContext = stylingSection.defaultContextValue() as? [String: Any],
              let fontSizes = defaultContext["fontSizes"] as? [String: String],
              !fontSizes.isEmpty else { return }

        // Find or create styling node
        var stylingNode = parent.children?.first(where: { $0.name == "styling" })
        if stylingNode == nil {
            stylingNode = parent.addChild(TreeNode(
                name: "styling",
                value: "",
                inEditor: true,
                status: .isNotLeaf,
                resume: resume
            ))
        }

        // Build fontSizes under styling
        if let styling = stylingNode {
            let fontSizesNode = styling.addChild(TreeNode(
                name: "fontSizes",
                value: "",
                inEditor: true,
                status: .isNotLeaf,
                resume: resume
            ))
            fontSizesNode.editorLabel = "Font Sizes"

            for (key, value) in fontSizes.sorted(by: { $0.key < $1.key }) {
                _ = fontSizesNode.addChild(TreeNode(
                    name: key,
                    value: value,
                    inEditor: true,
                    status: .saved,
                    resume: resume
                ))
            }
        }
    }

    /// Build the template node containing manifest-defined fields.
    /// These are rendered generically in the view (no hardcoded field names).
    private func buildTemplateNode(parent: TreeNode) {
        var templateNode: TreeNode?

        // Add sectionLabels if available
        if let labels = manifest.sectionVisibilityLabels, !labels.isEmpty {
            // Create template node on demand
            if templateNode == nil {
                templateNode = parent.addChild(TreeNode(
                    name: "template",
                    value: "",
                    inEditor: true,
                    status: .isNotLeaf,
                    resume: resume
                ))
                templateNode?.editorLabel = "Template"
            }

            let sectionLabelsNode = templateNode!.addChild(TreeNode(
                name: "sectionLabels",
                value: "",
                inEditor: true,
                status: .isNotLeaf,
                resume: resume
            ))
            sectionLabelsNode.editorLabel = "Section Labels"

            for (key, value) in labels.sorted(by: { $0.key < $1.key }) {
                _ = sectionLabelsNode.addChild(TreeNode(
                    name: key,
                    value: value,
                    inEditor: true,
                    status: .saved,
                    resume: resume
                ))
            }
        }

        // Future manifest-defined fields can be added here
    }
}
