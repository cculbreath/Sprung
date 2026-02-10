//
//  JobTitlesPanelView.swift
//  Sprung
//
//  Bespoke editor panel for the custom.jobTitles section.
//  Shows inline title-word editors, approved title sets,
//  and a button to open the Reference Browser's Title Sets tab.
//

import SwiftUI

struct JobTitlesPanelView: View {
    let sectionNode: TreeNode
    @Binding var sheets: AppSheets

    @Environment(ResumeDetailVM.self) private var vm
    @Environment(InferenceGuidanceStore.self) private var guidanceStore
    @Environment(TitleSetStore.self) private var titleSetStore

    // MARK: - Computed

    /// The 4 title-word children (ordered by index).
    private var titleChildren: [TreeNode] {
        sectionNode.orderedChildren
    }

    /// Favorited title sets from inference guidance.
    private var approvedSets: [TitleSet] {
        guidanceStore.favoriteTitleSets()
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Current titles editor
            currentTitlesCard

            // Approved title sets
            if !approvedSets.isEmpty {
                approvedSetsCard
            }

            // Browse button
            browseButton
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Current Titles

    private var currentTitlesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Titles")
                .font(.subheadline.weight(.semibold))

            Divider()

            ForEach(titleChildren, id: \.id) { child in
                NodeLeafView(node: child)
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

    // MARK: - Approved Title Sets

    private var approvedSetsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Approved Title Sets")
                .font(.subheadline.weight(.semibold))

            Divider()

            ForEach(approvedSets) { titleSet in
                Button {
                    applyTitleSet(titleSet)
                } label: {
                    HStack {
                        Text(titleSet.displayString)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer()

                        Image(systemName: "arrow.right.circle")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
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

    // MARK: - Actions

    /// Apply a title set's 4 titles to the 4 child nodes.
    private func applyTitleSet(_ titleSet: TitleSet) {
        let children = titleChildren
        for (index, title) in titleSet.titles.prefix(children.count).enumerated() {
            children[index].value = title
        }
        vm.refreshPDF()
        syncBackToTitleSetStore()
    }

    /// Save current title words back to TitleSetStore.
    private func syncBackToTitleSetStore() {
        let words = titleChildren.map { TitleWord(text: $0.value) }
        guard words.contains(where: { !$0.text.isEmpty }) else { return }
        let record = TitleSetRecord(words: words)
        titleSetStore.add(record)
    }
}
