//
//  NodeWithChildrenView.swift
//  Sprung
//
//
import SwiftData
import SwiftUI
struct NodeWithChildrenView: View {
    let node: TreeNode
    /// Depth offset to subtract when calculating indentation (for flattened container children)
    var depthOffset: Int = 0
    @Environment(ResumeDetailVM.self) private var vm: ResumeDetailVM

    /// Whether this node's children should display as chips
    private var displayAsChips: Bool {
        // Check explicit schema setting first
        if node.schemaInputKind == .chips {
            return true
        }
        // Fallback: keywords containers in skills section should display as chips
        // This handles existing trees created before manifest was updated
        let nodeName = node.name.lowercased()
        if nodeName == "keywords" {
            // Check if we're inside a skills section by looking at ancestors
            if let grandparent = node.parent?.parent {
                let sectionName = grandparent.name.lowercased()
                if sectionName == "skills" || sectionName.contains("skill") {
                    return true
                }
            }
        }
        return false
    }

    /// Source key for chip browsing (explicit or inferred)
    private var chipSourceKey: String? {
        if let explicit = node.schemaSourceKey {
            return explicit
        }
        // Infer skillBank for keywords in skills section
        if displayAsChips && node.name.lowercased() == "keywords" {
            return "skillBank"
        }
        return nil
    }

    /// Matched skill IDs from job context (for chip highlighting)
    private var matchedSkillIds: Set<UUID> {
        guard let requirements = node.resume.jobApp?.extractedRequirements else {
            return []
        }
        return Set(requirements.matchedSkillIds.compactMap { UUID(uuidString: $0) })
    }

    var body: some View {
        DraggableNodeWrapper(node: node, siblings: getSiblings()) {
            VStack(alignment: .leading) {
                // Header combines the chevron, title, add button, and status badge.
                NodeHeaderView(
                    node: node,
                    depthOffset: depthOffset,
                    addChildAction: { vm.addChild(to: node) }
                )
                // Show child nodes when expanded.
                if vm.isExpanded(node) {
                    NodeChildrenListView(
                        children: node.orderedChildren,
                        depthOffset: depthOffset,
                        displayAsChips: displayAsChips,
                        parentNode: node,
                        sourceKey: chipSourceKey,
                        matchedSkillIds: matchedSkillIds
                    )
                }
            }
        }
    }
    private func getSiblings() -> [TreeNode] {
        return node.parent?.orderedChildren ?? []
    }
}
