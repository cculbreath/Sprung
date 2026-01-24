//
//  ResumeEditorDrawers.swift
//  Sprung
//
//  Bottom drawer components for the resume editor panel.
//  Contains AI action drawer (default open) and styling drawer (default closed).
//

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

                    // Revnode count badge
                    if revnodeCount > 0 {
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

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 12) {
                    // AI action buttons row
                    HStack(spacing: 12) {
                        ResumeCustomizeButton(selectedTab: $selectedTab)
                        ClarifyingQuestionsButton(
                            selectedTab: $selectedTab,
                            clarifyingQuestions: $clarifyingQuestions,
                            sheets: $sheets
                        )
                        Button {
                            sheets.showResumeReview = true
                        } label: {
                            Label("Optimize", systemImage: "character.magnify")
                                .font(.system(size: 14, weight: .light))
                        }
                        .buttonStyle(.automatic)
                        .help("AI Resume Review")
                        .disabled(jobAppStore.selectedApp?.selectedRes == nil)
                    }

                    Divider()

                    // Footer row with phase assignments and create resume
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

                        Button {
                            showCreateResumeSheet = true
                        } label: {
                            Label("Create Resume", systemImage: "doc.badge.plus")
                                .font(.system(size: 14, weight: .light))
                        }
                        .buttonStyle(.automatic)
                        .help("Create a new resume for this job application")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 0))
    }
}

// MARK: - Styling Drawer

/// Bottom drawer containing font size and section visibility panels
struct ResumeStylingDrawer: View {
    @Binding var isExpanded: Bool
    @Environment(ResumeDetailVM.self) private var vm: ResumeDetailVM

    var body: some View {
        VStack(spacing: 0) {
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

                    Text("Styling & Template")
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
        }
    }
}
