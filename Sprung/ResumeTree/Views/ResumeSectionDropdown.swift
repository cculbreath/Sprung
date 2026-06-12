//
//  ResumeSectionDropdown.swift
//  Sprung
//
//  Section picker for navigating between resume sections.
//  Shows AI configuration button (icon) for sections that support AI review.
//

import AppKit
import SwiftUI

/// Information about a resume section for the dropdown
struct SectionInfo: Identifiable {
    var id: String { name }
    let name: String
    let displayLabel: String
    let node: TreeNode
}

/// Section dropdown with AI indicator and navigation buttons
struct ResumeSectionDropdown: View {
    let sections: [SectionInfo]
    @Binding var selectedSection: String

    private var currentIndex: Int {
        sections.firstIndex(where: { $0.name == selectedSection }) ?? 0
    }

    private var canGoPrevious: Bool {
        currentIndex > 0
    }

    private var canGoNext: Bool {
        currentIndex < sections.count - 1
    }

    private var selectedSectionNode: TreeNode? {
        sections.first(where: { $0.name == selectedSection })?.node
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Navigation row
            ZStack {
                // Centered: nav buttons + picker
                HStack(spacing: 8) {
                    Button {
                        if canGoPrevious {
                            selectedSection = sections[currentIndex - 1].name
                        }
                    } label: {
                        Image(systemName: "chevron.backward.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(canGoPrevious ? .secondary : .quaternary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canGoPrevious)
                    .help("Previous section")

                    SectionPickerButton(
                        sections: sections,
                        selectedSection: $selectedSection
                    )

                    Button {
                        if canGoNext {
                            selectedSection = sections[currentIndex + 1].name
                        }
                    } label: {
                        Image(systemName: "chevron.forward.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(canGoNext ? .secondary : .quaternary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canGoNext)
                    .help("Next section")
                }

                // Left-aligned: section-level AI icon
                HStack {
                    if let node = selectedSectionNode, sectionSupportsAIConfig(node) {
                        SectionAIModeMenu(node: node)
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    private func sectionSupportsAIConfig(_ node: TreeNode) -> Bool {
        node.parent != nil && !node.orderedChildren.isEmpty
    }
}

// MARK: - Section AI Mode Menu

/// Section-level AI toggle: include the whole section's contents in AI revision,
/// or not. Single editable axis — there is no bundle vs. iterate distinction.
private struct SectionAIModeMenu: View {
    let node: TreeNode

    private var iconMode: AIIconMode {
        AIIconModeResolver.detectSingleMode(for: node)
    }

    var body: some View {
        AIIconNativeMenuButton(mode: iconMode, showDropIndicator: true) {
            let menu = NSMenu()
            menu.addItem(ActionMenuItem(
                "Include this section in AI revision",
                checked: node.status == .aiToReplace
            ) {
                // Leaving the editable state sweeps orphaned descendant
                // opt-outs automatically (TreeNode.status setter).
                if node.status == .aiToReplace {
                    node.status = .saved
                } else {
                    node.status = .aiToReplace
                }
            })
            return menu
        }
    }
}

// MARK: - Section Picker Button

/// Custom section picker using popover for full layout control (trailing icons)
private struct SectionPickerButton: View {
    let sections: [SectionInfo]
    @Binding var selectedSection: String
    @State private var showingPicker = false

    private var selectedLabel: String {
        sections.first(where: { $0.name == selectedSection })?.displayLabel ?? "Select"
    }

    /// The widest label text among all sections
    private var widestLabel: String {
        sections.max(by: { $0.displayLabel.count < $1.displayLabel.count })?.displayLabel ?? "Select"
    }

    var body: some View {
        Button {
            showingPicker.toggle()
        } label: {
            ZStack {
                // Invisible widest label to set fixed width
                Text(widestLabel)
                    .fontWeight(.medium)
                    .opacity(0)

                // Visible selected label
                Text(selectedLabel)
                    .fontWeight(.medium)
            }
            .overlay(alignment: .trailing) {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .offset(x: 12)
            }
            .padding(.horizontal, 8)
            .padding(.trailing, 12) // room for chevron
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.05))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sections) { section in
                    Button {
                        selectedSection = section.name
                        showingPicker = false
                    } label: {
                        HStack(spacing: 8) {
                            // Checkmark for selected
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(section.name == selectedSection ? .primary : .clear)
                                .frame(width: 14)

                            Text(section.displayLabel)
                                .font(.system(size: 13))

                            Spacer(minLength: 20)

                            // AI status icon (trailing)
                            if sectionHasAIConfig(section.node) {
                                sectionIconImage(AIIconModeResolver.detectSingleMode(for: section.node))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .background(section.name == selectedSection ? Color.accentColor.opacity(0.1) : Color.clear)
                    }
                    .buttonStyle(.plain)

                    if section.id != sections.last?.id {
                        Divider()
                            .padding(.horizontal, 8)
                    }
                }
            }
            .padding(.vertical, 6)
            .frame(minWidth: 180)
        }
    }

    private func sectionHasAIConfig(_ node: TreeNode) -> Bool {
        node.status == .aiToReplace || node.aiStatusChildren > 0
    }

    private func sectionIconImage(_ mode: AIIconMode) -> some View {
        AIIconImage(mode: mode, size: 11)
    }
}
