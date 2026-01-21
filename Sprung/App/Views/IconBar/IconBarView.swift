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

    private let collapsedWidth: CGFloat = 52
    private let expandedWidth: CGFloat = 200

    var body: some View {
        VStack(spacing: 0) {
            // Module icons
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(AppModule.allCases) { module in
                        IconBarItem(
                            module: module,
                            isSelected: navigation.selectedModule == module,
                            isExpanded: navigation.isIconBarExpanded
                        )
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
        .frame(width: navigation.isIconBarExpanded ? expandedWidth : collapsedWidth)
        .background(Color(.windowBackgroundColor))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color(.separatorColor))
                .frame(width: 1)
        }
    }
}
