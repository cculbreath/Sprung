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
    private func savePhaseAssignment(groupId: String, phase: Int) {
        var assignments = resume.phaseAssignments
        assignments[groupId] = phase
        resume.phaseAssignments = assignments
        Logger.debug("📋 Saved phase assignment: \(groupId) → Phase \(phase)")
    }

    /// Load node groups from the resume tree based on configured AI attributes.
    /// Uses the new `bundledAttributes` and `enumeratedAttributes` properties on collection nodes.
    private func loadNodeGroups() {
        guard let rootNode = resume.rootNode else { return }

        var groups: [NodeGroup] = []
        let savedAssignments = resume.phaseAssignments

        // Traverse sections to find collections with AI attributes configured
        for sectionNode in rootNode.orderedChildren {
            let sectionName = sectionNode.name.isEmpty ? sectionNode.value : sectionNode.name
            guard !sectionName.isEmpty else { continue }

            // Check for bundled attributes (Together mode)
            if let bundled = sectionNode.bundledAttributes {
                for attrName in bundled {
                    let groupKey = "\(sectionName)-\(attrName)"
                    let phase = savedAssignments[groupKey] ?? 2
                    groups.append(NodeGroup(
                        id: groupKey,
                        sectionName: sectionName,
                        attributeName: attrName,
                        phase: phase
                    ))
                }
            }

            // Check for enumerated attributes (Separately mode)
            if let enumerated = sectionNode.enumeratedAttributes {
                for attrName in enumerated {
                    let groupKey = "\(sectionName)-\(attrName)"
                    // Skip if already added from bundled (shouldn't happen but safety check)
                    guard !groups.contains(where: { $0.id == groupKey }) else { continue }
                    let phase = savedAssignments[groupKey] ?? 2
                    groups.append(NodeGroup(
                        id: groupKey,
                        sectionName: sectionName,
                        attributeName: attrName,
                        phase: phase
                    ))
                }
            }
        }

        // Sort by section, then attribute
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
