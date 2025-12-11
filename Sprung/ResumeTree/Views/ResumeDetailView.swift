//
//  ResumeDetailView.swift
//  Sprung
//
//
import SwiftData
import SwiftUI
/// Tree-editor panel showing resume nodes and the optional font-size panel.
/// It no longer mutates the model directly; all actions are routed through
/// `ResumeDetailVM`.
struct ResumeDetailView: View {
    // External navigation bindings
    @Binding var tab: TabList
    // View-model (owns UI state)
    @State private var vm: ResumeDetailVM
    // MARK: – Init ---------------------------------------------------------
    private var externalIsWide: Binding<Bool>?
    init(
        resume: Resume,
        tab: Binding<TabList>,
        isWide: Binding<Bool>,
        exportCoordinator: ResumeExportCoordinator
    ) {
        _tab = tab
        _vm = State(wrappedValue: ResumeDetailVM(resume: resume, exportCoordinator: exportCoordinator))
        externalIsWide = isWide
    }
    // MARK: – Body ---------------------------------------------------------

    /// Node names that are not user content (handled separately or flattened)
    private static let nonContentNodes: Set<String> = ["styling", "template", "custom"]

    var body: some View {
        @Bindable var vm = vm // enable Observation bindings
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let root = vm.rootNode {
                    // Content section - user data nodes + custom fields (flattened)
                    let contentNodes = root.orderedChildren.filter { !Self.nonContentNodes.contains($0.name) }
                    let customNodes = root.orderedChildren.first(where: { $0.name == "custom" })?.orderedChildren ?? []
                    let allContentNodes = contentNodes + customNodes

                    if !allContentNodes.isEmpty {
                        Text("Content")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 10)
                            .padding(.top, 12)
                        ForEach(allContentNodes, id: \.id) { viewNode in
                            topLevelNodeView(viewNode)
                        }
                    }

                    // Template section - manifest-defined fields (rendered generically)
                    if let templateNode = root.orderedChildren.first(where: { $0.name == "template" }),
                       !templateNode.orderedChildren.isEmpty {
                        Text("Template")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 10)
                            .padding(.top, 16)
                        ForEach(templateNode.orderedChildren, id: \.id) { childNode in
                            topLevelNodeView(childNode)
                        }
                    }
                }

                // Styling section - special-cased panels
                let hasStylePanels = vm.hasFontSizeNodes || vm.hasSectionVisibilityOptions
                if hasStylePanels {
                    Text("Styling")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 10)
                        .padding(.top, 16)
                    VStack(alignment: .leading, spacing: 8) {
                        if vm.hasFontSizeNodes {
                            FontSizePanelView()
                                .padding(.horizontal, 10)
                        }
                        if vm.hasSectionVisibilityOptions {
                            SectionVisibilityPanelView()
                                .padding(.horizontal, 10)
                        }
                    }
                }
            }
        }
        // Provide the view-model to the subtree via environment so that
        // NodeWithChildrenView can access it for add-child actions.
        .environment(vm)
        .onAppear {
            if let ext = externalIsWide {
                vm.isWide = ext.wrappedValue
            }
        }
        .onChange(of: externalIsWide?.wrappedValue) { _, newVal in
            if let newVal { vm.isWide = newVal }
        }
    }
    @ViewBuilder
    private func topLevelNodeView(_ node: TreeNode) -> some View {
        if node.orderedChildren.isEmpty == false {
            NodeWithChildrenView(node: node)
        } else {
            RootLeafDisclosureView(node: node)
        }
    }
}
// MARK: - Root-Level Leaf Disclosure ---------------------------------------
private struct RootLeafDisclosureView: View {
    let node: TreeNode
    @Environment(ResumeDetailVM.self) private var vm: ResumeDetailVM
    private var expansionBinding: Binding<Bool> {
        Binding(
            get: { vm.isExpanded(node) },
            set: { _ in vm.toggleExpansion(for: node) }
        )
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                ToggleChevronView(isExpanded: expansionBinding)
                AlignedTextRow(
                    leadingText: node.displayLabel,
                    trailingText: nil,
                    nodeStatus: node.status
                )
                Spacer(minLength: 8)
                StatusBadgeView(node: node, isExpanded: vm.isExpanded(node))
            }
            .padding(.horizontal, 10)
            .padding(.leading, CGFloat(node.depth * 20))
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .onTapGesture {
                vm.toggleExpansion(for: node)
            }
            if vm.isExpanded(node) {
                Divider()
                NodeLeafView(node: node)
                    .padding(.leading, CGFloat(node.depth) * 20)
                    .padding(.vertical, 4)
           }
        }
    }
}
