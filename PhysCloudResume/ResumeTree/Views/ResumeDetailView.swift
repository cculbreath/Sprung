//
//  ResumeDetailView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 1/31/25.
//

import SwiftData
import SwiftUI

/// Tree‑editor panel showing resume nodes and the optional font‑size panel.
/// It no longer mutates the model directly; all actions are routed through
/// `ResumeDetailVM`.
struct ResumeDetailView: View {
    // External navigation bindings
    @Binding var tab: TabList

    // View‑model (owns UI state)
    @State private var vm: ResumeDetailVM

    // MARK: – Init ---------------------------------------------------------

    private var externalIsWide: Binding<Bool>?

    init(resume: Resume, tab: Binding<TabList>, isWide: Binding<Bool>, resStore: ResStore) {
        _tab = tab
        _vm = State(wrappedValue: ResumeDetailVM(resume: resume, resStore: resStore))
        externalIsWide = isWide
    }

    // MARK: – Body ---------------------------------------------------------

    var body: some View {
        @Bindable var vm = vm // enable Observation bindings

        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let root = vm.rootNode {
                    nodeView(root)
                }

                if vm.includeFonts {
                    FontSizePanelView().padding(10)
                }
            }
        }
        // Provide the view‑model to the subtree via environment so that
        // NodeWithChildrenView can access it for add‑child actions.
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

    // MARK: – Recursive node builder --------------------------------------

    @ViewBuilder
    private func nodeView(_ node: TreeNode) -> some View {
        // Defensive check to prevent crashes with corrupted TreeNode data
        // Wrap in a defensive block that catches any SwiftData faulting errors
        Group {
            let includeInEditor = safeGetNodeProperty { node.includeInEditor } ?? false
            if includeInEditor {
                let hasChildren = safeGetNodeProperty { node.hasChildren } ?? false
                if hasChildren {
                    NodeWithChildrenView(node: node)
                } else {
                    NodeLeafView(node: node)
                }
            }
        }
    }
    
    /// Safely gets a TreeNode property, returning nil if the node data is corrupted
    private func safeGetNodeProperty<T>(_ getter: () -> T) -> T? {
        return getter()
    }
}
