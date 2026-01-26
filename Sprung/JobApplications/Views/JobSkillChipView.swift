//
//  JobSkillChipView.swift
//  Sprung
//
//  Individual skill chip for the skills panel with category-based styling.
//

import SwiftUI

struct JobSkillChipView: View {
    let skill: JobSkillEvidence
    let isActive: Bool
    let onHover: (Bool) -> Void
    let onTap: () -> Void

    @State private var isHovering = false

    // Category-specific active color
    private var activeColor: Color {
        switch skill.category {
        case .matched:
            return .green
        case .recommended:
            return .orange
        case .unmatched:
            return Color(.systemGray)
        }
    }

    var body: some View {
        Text(skill.skillName)
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(chipBackground)
            .foregroundStyle(chipTextColor)
            .clipShape(Capsule())
            .overlay(chipBorder)
            .contentShape(Capsule())
            .onHover { hovering in
                isHovering = hovering
                onHover(hovering)
            }
            .onTapGesture {
                onTap()
            }
    }

    @ViewBuilder
    private var chipBackground: some View {
        if isActive {
            // Use category-specific color when active
            activeColor
        } else {
            switch skill.category {
            case .matched:
                Color.green.opacity(0.12)
            case .recommended:
                Color.orange.opacity(0.12)
            case .unmatched:
                Color(.controlBackgroundColor)
            }
        }
    }

    private var chipTextColor: Color {
        if isActive {
            return .white
        }
        switch skill.category {
        case .matched:
            return .green
        case .recommended:
            return .orange
        case .unmatched:
            return Color(.labelColor)
        }
    }

    private var chipBorder: some View {
        Capsule()
            .strokeBorder(borderColor, lineWidth: isActive ? 2 : 1)
    }

    private var borderColor: Color {
        if isActive {
            return activeColor.opacity(0.8)
        }
        switch skill.category {
        case .matched:
            return Color.green.opacity(0.4)
        case .recommended:
            return Color.orange.opacity(0.4)
        case .unmatched:
            return Color(.separatorColor)
        }
    }
}
