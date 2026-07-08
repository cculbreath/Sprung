//
//  ResumeEditorDrawers.swift
//  Sprung
//
//  Bottom drawer components for the resume editor panel.
//  Contains the styling drawer (default closed).
//

import AppKit
import SwiftUI

// MARK: - Styling Drawer

/// Bottom drawer containing font size and section visibility panels
/// Resizable height persisted to AppStorage
struct ResumeStylingDrawer: View {
    @Binding var isExpanded: Bool
    @Environment(ResumeDetailVM.self) private var vm: ResumeDetailVM
    @AppStorage("stylingDrawerHeight") private var drawerHeight: Double = 180

    private let minHeight: CGFloat = 100
    private let maxHeight: CGFloat = 400

    var body: some View {
        VStack(spacing: 0) {
            // Resize handle (only when expanded)
            if isExpanded {
                ResizeHandle(height: Binding(
                    get: { drawerHeight },
                    set: { drawerHeight = $0 }
                ), minHeight: minHeight, maxHeight: maxHeight)
                    .transition(.opacity)
            }

            DrawerSectionHeader(title: "Styling", isExpanded: $isExpanded)

            if isExpanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if vm.hasFontSizeNodes {
                            FontSizePanelView()
                        }
                        if vm.hasSectionVisibilityOptions {
                            SectionVisibilityPanelView()
                        }

                        Divider()
                        Button {
                            NotificationCenter.default.post(
                                name: .navigateToModule, object: nil,
                                userInfo: ["module": AppModule.references.rawValue]
                            )
                            NotificationCenter.default.post(
                                name: .navigateToReferencesTab, object: nil,
                                userInfo: ["tab": "Templates"]
                            )
                        } label: {
                            Label("Manage Templates…", systemImage: "doc.richtext")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.link)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .frame(height: drawerHeight)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .clipped()
        .glassEffect(.regular, in: .rect(cornerRadius: 0))
    }
}

// MARK: - Drawer Section Header

/// Shared header component for collapsible drawer sections.
/// Apple-style treatment: uppercase, tracked, subtle background tint.
struct DrawerSectionHeader: View {
    let title: String
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Top separator
            Rectangle()
                .fill(Color(.separatorColor))
                .frame(height: 1)

            // Disclosure header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)

                    Text(title.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.06))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Bottom separator (visible when expanded to distinguish header from content)
            if isExpanded {
                Rectangle()
                    .fill(Color(.separatorColor))
                    .frame(height: 1)
            }
        }
    }
}

// MARK: - Resize Handle

/// Draggable handle for resizing drawer height
private struct ResizeHandle: View {
    @Binding var height: Double
    let minHeight: CGFloat
    let maxHeight: CGFloat

    @State private var isDragging = false

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 8)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .fill(isDragging ? Color.accentColor : Color.secondary.opacity(0.4))
                    .frame(width: 36, height: 4)
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        // Dragging up increases height (negative translation)
                        let newHeight = height - value.translation.height
                        height = min(maxHeight, max(minHeight, newHeight))
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
    }
}
