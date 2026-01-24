//
//  ResumeSectionDropdown.swift
//  Sprung
//
//  Section picker for navigating between resume sections.
//  Shows AI indicator when the selected section has AI configuration.
//

import SwiftUI

/// Information about a resume section for the dropdown
struct SectionInfo: Identifiable {
    var id: String { name }
    let name: String
    let displayLabel: String
    let node: TreeNode
}

/// Section dropdown with AI indicator
struct ResumeSectionDropdown: View {
    let sections: [SectionInfo]
    @Binding var selectedSection: String

    var body: some View {
        HStack(spacing: 8) {
            Picker("Section", selection: $selectedSection) {
                ForEach(sections) { section in
                    Text(section.displayLabel)
                        .tag(section.name)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 200)

            // AI indicator for the selected section
            if let selectedSectionInfo = sections.first(where: { $0.name == selectedSection }),
               sectionHasAIConfig(selectedSectionInfo.node) {
                AIModeIndicator(
                    mode: detectAIMode(for: selectedSectionInfo.node),
                    pathPattern: nil,
                    isPerEntry: selectedSectionInfo.node.enumeratedAttributes?.isEmpty == false
                )
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Check if a section node has any AI configuration
    private func sectionHasAIConfig(_ node: TreeNode) -> Bool {
        // Check collection-level config
        if node.bundledAttributes?.isEmpty == false ||
           node.enumeratedAttributes?.isEmpty == false {
            return true
        }
        // Check if any children have AI status
        if node.aiStatusChildren > 0 {
            return true
        }
        return false
    }

    /// Detect the primary AI mode for a section node
    private func detectAIMode(for node: TreeNode) -> AIReviewMode {
        if node.bundledAttributes?.isEmpty == false {
            return .bundle
        } else if node.enumeratedAttributes?.isEmpty == false {
            return .iterate
        } else if node.aiStatusChildren > 0 {
            return .containsSolo
        }
        return .off
    }
}
