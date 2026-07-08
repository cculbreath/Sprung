//
//  IconBarView.swift
//  Sprung
//
//  Vertical icon bar for module navigation.
//

import SwiftUI

/// Vertical icon bar for module navigation
struct IconBarView: View {
    @Environment(ModuleNavigationService.self) private var navigation

    // Static so the layout (UnifiedAppLayout) can add the live icon-bar width
    // to the active module's minimum when computing the window floor.
    static let collapsedWidth: CGFloat = 52
    static let expandedWidth: CGFloat = 200

    var body: some View {
        VStack(spacing: 0) {
            // Module icons
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(AppModule.iconBarSections.enumerated()), id: \.offset) { sectionIndex, section in
                        if sectionIndex > 0 {
                            Divider()
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                        }
                        ForEach(section) { module in
                            IconBarItem(
                                module: module,
                                isSelected: navigation.selectedModule == module,
                                isExpanded: navigation.isIconBarExpanded
                            )
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            Spacer()

            Divider()
                .padding(.horizontal, 8)

            // Expand/collapse toggle
            IconBarExpandToggle(isExpanded: navigation.isIconBarExpanded)
        }
        .frame(width: navigation.isIconBarExpanded ? Self.expandedWidth : Self.collapsedWidth)
        .background(Color(.windowBackgroundColor))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color(.separatorColor))
                .frame(width: 1)
        }
    }
}
