//
//  ResumeDetailView.swift
//  Sprung
//
//  Panel-based resume TreeNode editor with section dropdown,
//  bottom drawers, and AI action controls.
//
import SwiftData
import SwiftUI

/// Tree-editor panel showing resume nodes with section dropdown navigation.
/// AI and styling controls are in collapsible bottom drawers.
struct ResumeDetailView: View {
    // External navigation bindings
    @Binding var tab: TabList
    @Binding var sheets: AppSheets
    @Binding var clarifyingQuestions: [ClarifyingQuestion]
    @Binding var showCreateResumeSheet: Bool

    // View-model (owns UI state)
    @State private var vm: ResumeDetailVM

    // Popover state
    @State private var showNodeGroupPhasePopover = false

    // Persisted UI state
    @AppStorage("resumeEditorSelectedSection") private var selectedSection: String = "work"
    @AppStorage("resumeEditorAIDrawerExpanded") private var isAIDrawerExpanded: Bool = true
    @AppStorage("resumeEditorStylingDrawerExpanded") private var isStylingDrawerExpanded: Bool = false

    // MARK: - Init

    private var externalIsWide: Binding<Bool>?

    init(
        resume: Resume,
        tab: Binding<TabList>,
        isWide: Binding<Bool>,
        sheets: Binding<AppSheets>,
        clarifyingQuestions: Binding<[ClarifyingQuestion]>,
        showCreateResumeSheet: Binding<Bool>,
        exportCoordinator: ResumeExportCoordinator
    ) {
        _tab = tab
        _sheets = sheets
        _clarifyingQuestions = clarifyingQuestions
        _showCreateResumeSheet = showCreateResumeSheet
        _vm = State(wrappedValue: ResumeDetailVM(resume: resume, exportCoordinator: exportCoordinator))
        externalIsWide = isWide
    }

    // MARK: - Body

    /// Node names that are never shown as content (always handled separately).
    /// The "styling" node is handled by the Styling drawer, not as a section.
    private static let alwaysHiddenNodes: Set<String> = ["styling"]

    var body: some View {
        @Bindable var vm = vm // enable Observation bindings

        ZStack {
            VStack(spacing: 0) {
                // Section dropdown at top
                ResumeSectionDropdown(
                    sections: contentSections,
                    selectedSection: $selectedSection
                )

                Divider()

                // Main content - ONLY selected section
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if let sectionNode = selectedSectionNode {
                            sectionContentView(sectionNode)
                        } else if let firstSection = contentSections.first {
                            // Fallback to first section if selected section not found
                            sectionContentView(firstSection.node)
                                .onAppear {
                                    selectedSection = firstSection.name
                                }
                        }
                    }
                    .padding(.top, 8)
                }
                .id(selectedSection)

                Spacer(minLength: 0)

                // Bottom drawers
                let hasStylePanels = vm.hasFontSizeNodes || vm.hasSectionVisibilityOptions
                if hasStylePanels {
                    ResumeStylingDrawer(isExpanded: $isStylingDrawerExpanded)
                }

                ResumeAIDrawer(
                    isExpanded: $isAIDrawerExpanded,
                    selectedTab: $tab,
                    sheets: $sheets,
                    clarifyingQuestions: $clarifyingQuestions,
                    showCreateResumeSheet: $showCreateResumeSheet,
                    revnodeCount: vm.rootNode?.revnodeCount ?? 0,
                    showPhaseAssignments: $showNodeGroupPhasePopover,
                    resume: vm.resume
                )
            }

        }
        .environment(vm)
        .onAppear {
            if let ext = externalIsWide {
                vm.isWide = ext.wrappedValue
            }
            ensureValidSelection()
        }
        .onChange(of: externalIsWide?.wrappedValue) { _, newVal in
            if let newVal { vm.isWide = newVal }
        }
    }

    // MARK: - Computed Properties

    /// All content sections available for the dropdown.
    /// Uses manifest's `transparentKeys` to determine which containers' children
    /// should be promoted to top level (e.g., custom.jobTitles becomes a section).
    private var contentSections: [SectionInfo] {
        guard let root = vm.rootNode else { return [] }

        var sections: [SectionInfo] = []
        let transparentKeys = vm.transparentKeys

        for node in root.orderedChildren {
            // Skip always-hidden nodes (styling is in the drawer)
            if Self.alwaysHiddenNodes.contains(node.name) {
                continue
            }

            // If this is a transparent container, promote its children instead
            if transparentKeys.contains(node.name) {
                for child in node.orderedChildren {
                    sections.append(SectionInfo(
                        name: "\(node.name)_\(child.name)",
                        displayLabel: child.displayLabel,
                        node: child
                    ))
                }
            } else {
                // Regular section - add directly
                sections.append(SectionInfo(
                    name: node.name,
                    displayLabel: node.displayLabel,
                    node: node
                ))
            }
        }

        return sections
    }

    /// The currently selected section node.
    /// Handles both regular sections and promoted children from transparent containers.
    private var selectedSectionNode: TreeNode? {
        guard let root = vm.rootNode else { return nil }

        // Check if selection is a promoted child (format: "containerName_childName")
        for transparentKey in vm.transparentKeys {
            let prefix = "\(transparentKey)_"
            if selectedSection.hasPrefix(prefix) {
                let childName = String(selectedSection.dropFirst(prefix.count))
                if let container = root.orderedChildren.first(where: { $0.name == transparentKey }) {
                    return container.orderedChildren.first { $0.name == childName }
                }
            }
        }

        // Regular section lookup
        return root.orderedChildren.first { $0.name == selectedSection }
    }

    // MARK: - Section Content Views

    /// Render the content of a section as scrollable cards (always expanded, no disclosure triangles)
    @ViewBuilder
    private func sectionContentView(_ sectionNode: TreeNode) -> some View {
        // Check for bespoke editor panel first
        if let panel = vm.editorPanel(for: selectedSection) {
            editorPanelView(panel, sectionNode: sectionNode)
        } else if !sectionNode.orderedChildren.isEmpty {
            // Check for single-entry section with matching name (avoid redundant labels)
            if isSingleEntrySection(sectionNode) {
                // Show single entry's content directly without card header
                SingleEntrySectionView(sectionNode: sectionNode)
                    .padding(.horizontal, 8)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(sectionNode.orderedChildren, id: \.id) { childNode in
                        if childNode.orderedChildren.isEmpty {
                            // Leaf entry - show as card with single value
                            LeafEntryCardView(node: childNode, siblings: sectionNode.orderedChildren)
                        } else {
                            // Container entry - show as card with all fields visible
                            ResumeEntryCardView(node: childNode, depthOffset: 1)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        } else {
            // Section is a leaf (like summary) - show editor directly in a card
            LeafSectionCardView(node: sectionNode)
                .padding(.horizontal, 8)
        }
    }

    /// Route a named editor panel to its concrete view.
    @ViewBuilder
    private func editorPanelView(_ panelName: String, sectionNode: TreeNode) -> some View {
        switch panelName {
        case "jobTitlesPanel":
            JobTitlesPanelView(sectionNode: sectionNode, sheets: $sheets)
        default:
            // Unknown panel — fall back to generic rendering
            if !sectionNode.orderedChildren.isEmpty {
                LazyVStack(spacing: 8) {
                    ForEach(sectionNode.orderedChildren, id: \.id) { childNode in
                        if childNode.orderedChildren.isEmpty {
                            LeafEntryCardView(node: childNode, siblings: sectionNode.orderedChildren)
                        } else {
                            ResumeEntryCardView(node: childNode, depthOffset: 1)
                        }
                    }
                }
                .padding(.horizontal, 4)
            } else {
                LeafSectionCardView(node: sectionNode)
                    .padding(.horizontal, 8)
            }
        }
    }

    /// Check if this section has only one entry that would create redundant labeling
    private func isSingleEntrySection(_ sectionNode: TreeNode) -> Bool {
        guard sectionNode.orderedChildren.count == 1,
              let onlyChild = sectionNode.orderedChildren.first else { return false }

        // If the child's title matches the section's label, it's redundant
        let sectionLabel = sectionNode.displayLabel.lowercased()
        let childTitle = onlyChild.computedTitle.lowercased()

        // Also check if child has only one field with matching name
        if onlyChild.orderedChildren.count == 1 {
            let fieldName = onlyChild.orderedChildren.first?.name.lowercased() ?? ""
            let fieldMatches = sectionNode.name.lowercased().contains(fieldName) ||
                               fieldName.contains(sectionNode.name.lowercased())
            if fieldMatches { return true }
        }

        return sectionLabel == childTitle ||
               sectionLabel.contains(childTitle) ||
               childTitle.contains(sectionLabel)
    }

    /// Ensures the selected section is valid; if not, selects the first available section.
    private func ensureValidSelection() {
        let validNames = Set(contentSections.map(\.name))
        if !validNames.contains(selectedSection) {
            // Use first content section from manifest, or fall back to first available
            if let first = vm.firstContentSection, validNames.contains(first) {
                selectedSection = first
            } else if let first = contentSections.first?.name {
                selectedSection = first
            }
        }
    }
}

// MARK: - Leaf Entry Card

/// Card view for a single leaf entry (e.g., a job title string)
private struct LeafEntryCardView: View {
    let node: TreeNode
    let siblings: [TreeNode]

    var body: some View {
        DraggableNodeWrapper(node: node, siblings: siblings) {
            // NodeLeafView already shows the AI status icon - don't duplicate
            NodeLeafView(node: node)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.windowBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Leaf Section Card

/// Card view for a section that is itself a leaf (like summary)
private struct LeafSectionCardView: View {
    let node: TreeNode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(node.displayLabel)
                .font(.subheadline.weight(.semibold))

            Divider()

            // NodeLeafView shows both the AI icon and the editable content
            NodeLeafView(node: node)
        }
        .padding(12)
        .background(Color(.windowBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Single Entry Section View

/// Card view for a section with only one entry that would otherwise have redundant labels
/// Shows the entry's content directly without card header or redundant field labels
private struct SingleEntrySectionView: View {
    let sectionNode: TreeNode
    @Environment(ResumeDetailVM.self) private var vm: ResumeDetailVM

    private var entryNode: TreeNode? {
        sectionNode.orderedChildren.first
    }

    private var hasAIConfig: Bool {
        entryNode?.status == .aiToReplace
    }

    /// Get content nodes - show all children, let NodeLeafView handle display
    private var contentNodes: [TreeNode] {
        guard let entry = entryNode else { return [] }
        // Return all children - no filtering needed
        // NodeLeafView handles showing name/value appropriately
        return entry.orderedChildren
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Show content nodes directly
            ForEach(contentNodes, id: \.id) { node in
                if node.orderedChildren.isEmpty {
                    // Leaf value - show without label since section name covers it
                    NodeLeafView(node: node)
                } else {
                    // Container - show with label
                    VStack(alignment: .leading, spacing: 4) {
                        Text(node.displayLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(node.orderedChildren, id: \.id) { child in
                            NodeLeafView(node: child)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.windowBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}
