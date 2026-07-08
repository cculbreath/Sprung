//
//  JobTitlesPanelView.swift
//  Sprung
//
//  Bespoke editor panel for the custom.jobTitles section.
//  Shows inline title-word editors and a button to open the
//  Reference Browser's Title Sets tab.
//

import SwiftUI

struct JobTitlesPanelView: View {
    let sectionNode: TreeNode
    @Binding var sheets: AppSheets

    @Environment(ResumeDetailVM.self) private var vm

    // MARK: - Computed

    /// The 4 title-word children (ordered by index).
    private var titleChildren: [TreeNode] {
        sectionNode.orderedChildren
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Current titles editor
            currentTitlesCard

            // Browse button
            browseButton
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Current Titles

    private var currentTitlesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Titles")
                .scaledFont(size: 11, weight: .semibold)

            Divider()

            ForEach(titleChildren, id: \.id) { child in
                NodeLeafView(node: child)
            }

            if sectionNode.allowsChildAddition {
                Button(action: { vm.addChild(to: sectionNode) }) {
                    Label("Add Title", systemImage: "plus")
                        .scaledFont(size: 11)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
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

    // MARK: - Browse Button

    private var browseButton: some View {
        Button {
            NotificationCenter.default.post(name: .navigateToModule, object: nil, userInfo: ["module": AppModule.references.rawValue])
            NotificationCenter.default.post(name: .navigateToReferencesTab, object: nil, userInfo: ["tab": "Titles"])
        } label: {
            Label("Browse Title Sets", systemImage: "text.magnifyingglass")
        }
        .buttonStyle(.bordered)
        .padding(.top, 4)
    }
}
