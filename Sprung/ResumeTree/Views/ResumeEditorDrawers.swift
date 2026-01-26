//
//  ResumeEditorDrawers.swift
//  Sprung
//
//  Bottom drawer components for the resume editor panel.
//  Contains AI action drawer (default open) and styling drawer (default closed).
//

import AppKit
import SwiftUI

// MARK: - AI Action Drawer

/// Bottom drawer containing AI action buttons, revnode count, and phase assignments
struct ResumeAIDrawer: View {
    @Binding var isExpanded: Bool
    @Binding var selectedTab: TabList
    @Binding var sheets: AppSheets
    @Binding var clarifyingQuestions: [ClarifyingQuestion]
    @Binding var showCreateResumeSheet: Bool
    let revnodeCount: Int
    @Binding var showPhaseAssignments: Bool
    let resume: Resume?

    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore

    var body: some View {
        VStack(spacing: 0) {
            // Top separator
            Rectangle()
                .fill(Color.primary.opacity(0.2))
                .frame(height: 1)
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: -1)

            // Disclosure header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Text("AI Actions")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    Spacer()

                    // Revnode count (right aligned with label)
                    if revnodeCount > 0 {
                        HStack(spacing: 4) {
                            Text("Review Items:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 3) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 9))
                                Text("\(revnodeCount)")
                                    .font(.caption2.weight(.medium))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 10) {
                    // AI action buttons row (compact size)
                    HStack(spacing: 8) {
                        ResumeCustomizeButton(selectedTab: $selectedTab)
                            .controlSize(.small)
                        ClarifyingQuestionsButton(
                            selectedTab: $selectedTab,
                            clarifyingQuestions: $clarifyingQuestions,
                            sheets: $sheets
                        )
                        .controlSize(.small)
                        Button {
                            sheets.showResumeReview = true
                        } label: {
                            Label("Optimize", systemImage: "character.magnify")
                                .font(.system(size: 12))
                        }
                        .controlSize(.small)
                        .buttonStyle(.automatic)
                        .help("AI Resume Review")
                        .disabled(jobAppStore.selectedApp?.selectedRes == nil)

                        Spacer()
                    }

                    Divider()

                    // Footer row with phase assignments
                    HStack {
                        Button(action: { showPhaseAssignments.toggle() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "list.number")
                                Text("Phase Assignments")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showPhaseAssignments, arrowEdge: .top) {
                            if let resume = resume {
                                NodeGroupPhasePanelPopover(resume: resume)
                            }
                        }

                        Spacer()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .clipped()
        .glassEffect(.regular, in: .rect(cornerRadius: 0))
    }
}

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

            // Top separator
            Rectangle()
                .fill(Color.primary.opacity(0.15))
                .frame(height: 1)

            // Disclosure header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Text("Styling")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if vm.hasFontSizeNodes {
                            FontSizePanelView()
                        }
                        if vm.hasSectionVisibilityOptions {
                            SectionVisibilityPanelView()
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
                .frame(height: drawerHeight)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .clipped()
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
