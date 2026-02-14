//
//  NodeGroupPhasePanel.swift
//  Sprung
//
//  Popover panel showing phase assignments for AI-enabled fields.
//  Phase 1 items are reviewed first, Phase 2 items reviewed in a second round.
//

import SwiftUI
import SwiftData

/// Represents a field's phase assignment for multi-round review
struct NodeGroup: Identifiable {
    let id: String  // Collection node ID
    let sectionName: String  // e.g., "Skills", "Work"
    let attributeName: String  // e.g., "name", "highlights", "keywords"
    var phase: Int  // 1 or 2

    var displayName: String {
        "\(sectionName) → \(attributeName)"
    }
}

/// Popover panel for assigning fields to review phases
struct NodeGroupPhasePanelPopover: View {
    @Bindable var resume: Resume
    @State private var nodeGroups: [NodeGroup] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "list.number")
                    .foregroundColor(.accentColor)
                Text("Phase Assignments")
                    .font(.headline)
            }
            .padding(.bottom, 4)

            Divider()

            if nodeGroups.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up.slash")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No fields configured")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Enable AI on fields using the sparkle button\nto configure phase assignments.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach($nodeGroups) { $group in
                        HStack {
                            // Display as "Section → attribute"
                            Text(group.displayName)
                                .font(.subheadline)

                            Spacer()

                            // Phase toggle: 1 | 2
                            PhaseToggle(phase: Binding(
                                get: { group.phase },
                                set: { newPhase in
                                    group.phase = newPhase
                                    savePhaseAssignment(groupId: group.id, phase: newPhase)
                                }
                            ))
                        }
                        .padding(.vertical, 2)
                    }
                }

                Divider()

                // Legend
                Text("Phase 1 fields are reviewed first, then Phase 2")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(minWidth: 260, maxWidth: 300)
        .onAppear {
            loadNodeGroups()
        }
    }

    /// Save a phase assignment to the resume
    /// Only phase 1 assignments are stored; phase 2 is the default (absence = phase 2)
    private func savePhaseAssignment(groupId: String, phase: Int) {
        var assignments = resume.phaseAssignments
        if phase == 1 {
            assignments[groupId] = 1
        } else {
            assignments.removeValue(forKey: groupId)  // Phase 2 is default, no need to store
        }
        resume.phaseAssignments = assignments
        Logger.debug("📋 Phase assignment: \(groupId) → Phase \(phase)")
    }

    /// Load node groups from the resume tree based on configured AI attributes.
    /// Walks the tree the same way PhaseReviewManager.processNode does so every
    /// RevNode that will be generated also appears here for phase assignment.
    private func loadNodeGroups() {
        guard let rootNode = resume.rootNode else { return }

        var groups: [NodeGroup] = []
        var addedKeys = Set<String>()
        let phase1Keys = Set(resume.phaseAssignments.keys)

        func addGroup(section: String, attr: String, displayAttr: String? = nil) {
            let groupKey = "\(section)-\(attr)"
            guard !addedKeys.contains(groupKey) else { return }
            addedKeys.insert(groupKey)
            let phase = phase1Keys.contains(groupKey) ? 1 : 2
            groups.append(NodeGroup(
                id: groupKey,
                sectionName: section,
                attributeName: displayAttr ?? attr,
                phase: phase
            ))
        }

        func walkNode(_ node: TreeNode, sectionName: String) {
            let nodeName = node.name.isEmpty ? node.value : node.name
            let currentSection = (sectionName.isEmpty ? nodeName : sectionName).capitalized

            // Bundled attributes
            if let bundled = node.bundledAttributes, !bundled.isEmpty {
                let namedAttrs = bundled.filter { $0 != "*" && !$0.hasSuffix("[]") }
                if namedAttrs.count > 1 {
                    // Multi-attribute bundle: show ONE combined entry sharing a phase
                    let combinedDisplay = namedAttrs.joined(separator: " + ")
                    addGroup(section: currentSection, attr: namedAttrs[0], displayAttr: combinedDisplay)
                } else {
                    for attr in bundled {
                        addGroup(section: currentSection, attr: attr)
                    }
                }
            }

            // Enumerated attributes — expand ["*"] for object collections
            if let enumerated = node.enumeratedAttributes, !enumerated.isEmpty {
                if enumerated == ["*"] {
                    let isObjectCollection = node.orderedChildren.first.map { !$0.orderedChildren.isEmpty } ?? false
                    if isObjectCollection {
                        // Object collection: expand wildcard to individual attribute names
                        if let firstEntry = node.orderedChildren.first {
                            for child in firstEntry.orderedChildren {
                                let attrName = child.name.isEmpty ? child.displayLabel : child.name
                                guard !attrName.isEmpty else { continue }
                                addGroup(section: currentSection, attr: attrName)
                            }
                        }
                    } else {
                        // Flat container enumerate
                        addGroup(section: currentSection, attr: "*", displayAttr: "(all items)")
                    }
                } else {
                    for attr in enumerated where attr != "*" {
                        addGroup(section: currentSection, attr: attr)
                    }
                }
            }

            // Solo nodes (aiToReplace with no bundle/enumerate)
            if node.status == .aiToReplace &&
               node.bundledAttributes == nil &&
               node.enumeratedAttributes == nil {
                addGroup(section: currentSection, attr: nodeName)
            }

            // Recurse
            for child in node.orderedChildren {
                walkNode(child, sectionName: currentSection)
            }
        }

        for section in rootNode.orderedChildren {
            walkNode(section, sectionName: "")
        }

        nodeGroups = groups.sorted { ($0.sectionName, $0.attributeName) < ($1.sectionName, $1.attributeName) }
    }
}

/// Simple 1|2 segmented toggle for phase selection
struct PhaseToggle: View {
    @Binding var phase: Int

    var body: some View {
        HStack(spacing: 0) {
            // Phase 1 button
            Button(action: { phase = 1 }) {
                Text("1")
                    .font(.caption.bold())
                    .foregroundColor(phase == 1 ? .white : .secondary)
                    .frame(width: 24, height: 20)
                    .background(phase == 1 ? Color.accentColor : Color.clear)
            }
            .buttonStyle(PlainButtonStyle())

            // Divider
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 1, height: 16)

            // Phase 2 button
            Button(action: { phase = 2 }) {
                Text("2")
                    .font(.caption.bold())
                    .foregroundColor(phase == 2 ? .white : .secondary)
                    .frame(width: 24, height: 20)
                    .background(phase == 2 ? Color.accentColor : Color.clear)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
    }
}
