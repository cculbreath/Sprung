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

    /// Node names that are not user content (handled separately or flattened)
    private static let nonContentNodes: Set<String> = ["styling", "template", "custom"]

    var body: some View {
        @Bindable var vm = vm // enable Observation bindings

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

                    // Template section (when "template" is selected)
                    if selectedSection == "template" {
                        templateSectionContent
                    }
                }
                .padding(.top, 8)
            }

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
        .environment(vm)
        .onAppear {
            if let ext = externalIsWide {
                vm.isWide = ext.wrappedValue
            }
            // Validate selected section exists
            if !contentSections.contains(where: { $0.name == selectedSection }) {
                if let firstSection = contentSections.first {
                    selectedSection = firstSection.name
                }
            }
        }
        .onChange(of: externalIsWide?.wrappedValue) { _, newVal in
            if let newVal { vm.isWide = newVal }
        }
    }

    // MARK: - Computed Properties

    /// All content sections available for the dropdown
    private var contentSections: [SectionInfo] {
        guard let root = vm.rootNode else { return [] }

        var sections: [SectionInfo] = []

        // Content nodes (excluding non-content)
        let contentNodes = root.orderedChildren.filter { !Self.nonContentNodes.contains($0.name) }
        for node in contentNodes {
            sections.append(SectionInfo(
                name: node.name,
                displayLabel: node.displayLabel,
                node: node
            ))
        }

        // Custom fields flattened to top level
        if let customNode = root.orderedChildren.first(where: { $0.name == "custom" }),
           !customNode.orderedChildren.isEmpty {
            for customChild in customNode.orderedChildren {
                sections.append(SectionInfo(
                    name: "custom_\(customChild.name)",
                    displayLabel: customChild.displayLabel,
                    node: customChild
                ))
            }
        }

        // Template section if it exists
        if let templateNode = root.orderedChildren.first(where: { $0.name == "template" }),
           !templateNode.orderedChildren.isEmpty {
            sections.append(SectionInfo(
                name: "template",
                displayLabel: "Template",
                node: templateNode
            ))
        }

        return sections
    }

    /// The currently selected section node
    private var selectedSectionNode: TreeNode? {
        // Check for custom_ prefix
        if selectedSection.hasPrefix("custom_") {
            let customName = String(selectedSection.dropFirst("custom_".count))
            if let customNode = vm.rootNode?.orderedChildren.first(where: { $0.name == "custom" }) {
                return customNode.orderedChildren.first { $0.name == customName }
            }
        }

        // Regular section lookup
        return vm.rootNode?.orderedChildren.first { $0.name == selectedSection }
    }

    // MARK: - Section Content Views

    /// Render the content of a section as scrollable cards (always expanded, no disclosure triangles)
    @ViewBuilder
    private func sectionContentView(_ sectionNode: TreeNode) -> some View {
        // For sections with children (like work, skills), show children as cards
        if !sectionNode.orderedChildren.isEmpty {
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
        } else {
            // Section is a leaf (like summary) - show editor directly in a card
            LeafSectionCardView(node: sectionNode)
                .padding(.horizontal, 8)
        }
    }

    /// Template section content
    @ViewBuilder
    private var templateSectionContent: some View {
        if let templateNode = vm.rootNode?.orderedChildren.first(where: { $0.name == "template" }) {
            LazyVStack(spacing: 8) {
                ForEach(templateNode.orderedChildren, id: \.id) { childNode in
                    if childNode.orderedChildren.isEmpty {
                        LeafEntryCardView(node: childNode, siblings: templateNode.orderedChildren)
                    } else {
                        ResumeEntryCardView(node: childNode, depthOffset: 1)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Leaf Entry Card

/// Card view for a single leaf entry (e.g., a job title string)
private struct LeafEntryCardView: View {
    let node: TreeNode
    let siblings: [TreeNode]
    @Environment(ResumeDetailVM.self) private var vm: ResumeDetailVM

    private var hasAIConfig: Bool {
        node.status == .aiToReplace
    }

    var body: some View {
        DraggableNodeWrapper(node: node, siblings: siblings) {
            HStack(spacing: 12) {
                NodeLeafView(node: node)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if hasAIConfig {
                    AIModeIndicator(mode: .solo, pathPattern: nil, isPerEntry: false)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(hasAIConfig ? Color.orange.opacity(0.05) : Color(.windowBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(hasAIConfig ? Color.orange.opacity(0.3) : Color.primary.opacity(0.1), lineWidth: 1)
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
    @Environment(ResumeDetailVM.self) private var vm: ResumeDetailVM

    private var hasAIConfig: Bool {
        node.status == .aiToReplace
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(node.displayLabel)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if hasAIConfig {
                    AIModeIndicator(mode: .solo, pathPattern: nil, isPerEntry: false)
                }
            }

            Divider()

            NodeLeafView(node: node)
        }
        .padding(12)
        .background(hasAIConfig ? Color.orange.opacity(0.05) : Color(.windowBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(hasAIConfig ? Color.orange.opacity(0.3) : Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

