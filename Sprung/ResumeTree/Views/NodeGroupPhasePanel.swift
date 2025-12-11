//
//  NodeGroupPhasePanel.swift
//  Sprung
//
//  Auxiliary panel showing all AI-enabled node groups with phase toggles.
//  Allows users to assign attributes to Phase 1 or Phase 2 for multi-phase review.
//

import SwiftUI
import SwiftData

/// Represents a node group created via attribute picker
struct NodeGroup: Identifiable {
    let id: String  // Collection node ID
    let sectionName: String  // e.g., "Skills", "Work"
    let attributeName: String  // e.g., "name", "highlights", "keywords"
    var phase: Int  // 1 or 2

    var displayName: String {
        "\(sectionName) → \(attributeName)"
    }
}

struct NodeGroupPhasePanel: View {
    let resume: Resume
    @State private var nodeGroups: [NodeGroup] = []
    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header with toggle
            HStack {
                ToggleChevronView(isExpanded: $isExpanded)
                Text("AI Customization Node Groups")
                    .foregroundColor(.secondary)
                    .fontWeight(.regular)
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation { isExpanded.toggle() }
            }
            .padding(.leading, 20)
            .padding(.vertical, 5)

            if isExpanded {
                if nodeGroups.isEmpty {
                    Text("No node groups configured")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 28)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach($nodeGroups) { $group in
                            HStack {
                                Text(group.displayName)
                                    .font(.subheadline)

                                Spacer()

                                // Phase toggle: 1 | 2
                                PhaseToggle(phase: $group.phase)
                            }
                        }
                    }
                    .padding(.leading, 28)
                    .padding(.trailing, 12)
                    .padding(.top, 4)
                }
            }
        }
        .padding(.trailing, 12)
        .onAppear {
            loadNodeGroups()
        }
    }

    /// Load node groups from the resume tree
    private func loadNodeGroups() {
        guard let rootNode = resume.rootNode else { return }

        var groups: [NodeGroup] = []

        // Find all collection nodes with group selections
        for sectionNode in rootNode.orderedChildren {
            let selectedAttrs = sectionNode.selectedGroupAttributes
            if !selectedAttrs.isEmpty {
                // This section has group selections
                for attr in selectedAttrs {
                    let group = NodeGroup(
                        id: "\(sectionNode.id)-\(attr.name)",
                        sectionName: sectionNode.name.isEmpty ? sectionNode.value : sectionNode.name,
                        attributeName: attr.name,
                        phase: getPhase(for: sectionNode.id, attribute: attr.name) ?? (attr.mode == .bundle ? 1 : 2)
                    )
                    groups.append(group)
                }
            }

            // Also check child nodes (e.g., skills -> categories -> keywords)
            for childNode in sectionNode.orderedChildren {
                let childAttrs = childNode.selectedGroupAttributes
                if !childAttrs.isEmpty {
                    for attr in childAttrs {
                        let group = NodeGroup(
                            id: "\(childNode.id)-\(attr.name)",
                            sectionName: sectionNode.name.isEmpty ? sectionNode.value : sectionNode.name,
                            attributeName: attr.name,
                            phase: getPhase(for: childNode.id, attribute: attr.name) ?? (attr.mode == .bundle ? 1 : 2)
                        )
                        groups.append(group)
                    }
                }
            }
        }

        nodeGroups = groups
    }

    /// Get the configured phase for a node group (from manifest or user override)
    private func getPhase(for nodeId: String, attribute: String) -> Int? {
        // Try to get phase from manifest reviewPhases config
        guard let template = resume.template,
              let manifest = TemplateManifestLoader.manifest(for: template),
              let reviewPhases = manifest.reviewPhases else {
            return nil
        }

        // Find matching phase config
        for (_, phases) in reviewPhases {
            for phaseConfig in phases {
                if phaseConfig.field.contains(attribute) {
                    return phaseConfig.phase
                }
            }
        }

        return nil
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
