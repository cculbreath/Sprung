//
//  SeedGenerationView.swift
//  Sprung
//
//  Main container view for the Seed Generation Module.
//

import SwiftUI

/// Selection for the sidebar
enum SeedGenerationSelection: Hashable {
    case section(ExperienceSectionKey)
    case reviewQueue
}

/// Main view for the Seed Generation Module
struct SeedGenerationView: View {
    @State var orchestrator: SeedGenerationOrchestrator

    @Environment(ExperienceDefaultsStore.self) private var defaultsStore

    @State private var selectedItem: SeedGenerationSelection?
    @State private var hasApplied = false

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            mainContent
            Divider()
            SeedGenerationStatusBar(tracker: orchestrator.activityTracker)
        }
        .frame(minWidth: 800, minHeight: 600)
        .task {
            await orchestrator.startGeneration()
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Experience Defaults Generator")
                    .font(.headline)
                Text("Review and approve generated content, then apply to your defaults")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if hasApplied {
                Label("Applied", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline)
            }

            Button {
                applyToDefaults()
            } label: {
                Label("Apply to Defaults", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .disabled(orchestrator.reviewQueue.approvedItems.isEmpty || hasApplied)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private func applyToDefaults() {
        var defaults = defaultsStore.currentDefaults()
        orchestrator.applyApprovedContent(to: &defaults)
        defaultsStore.save(defaults)  // Actually save the modified defaults
        defaultsStore.markSeedCreated()
        hasApplied = true
        Logger.info("🌱 Applied \(orchestrator.reviewQueue.approvedItems.count) items to defaults and marked seedCreated", category: .ai)
    }

    // MARK: - Main Content

    private var mainContent: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedItem) {
            Section("Generation Progress") {
                ForEach(orchestrator.sectionProgress) { progress in
                    SectionProgressRow(progress: progress)
                        .tag(SeedGenerationSelection.section(progress.section))
                }
            }

            if orchestrator.reviewQueue.hasPendingItems {
                Section {
                    Label {
                        HStack {
                            Text("Review Queue")
                            Spacer()
                            Text("\(orchestrator.reviewQueue.pendingCount)")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.blue, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    } icon: {
                        Image(systemName: "tray.full.fill")
                    }
                    .tag(SeedGenerationSelection.reviewQueue)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 220)
    }

    // MARK: - Detail View

    @ViewBuilder
    private var detailView: some View {
        switch selectedItem {
        case .reviewQueue:
            ReviewQueueView(queue: orchestrator.reviewQueue)
        case .section(let section):
            sectionDetailView(for: section)
        case nil:
            if orchestrator.reviewQueue.hasPendingItems {
                ReviewQueueView(queue: orchestrator.reviewQueue)
            } else {
                welcomeView
            }
        }
    }

    @ViewBuilder
    private func sectionDetailView(for section: ExperienceSectionKey) -> some View {
        switch section {
        case .projects:
            if let proposals = orchestrator.projectProposals, !proposals.isEmpty {
                ProjectCurationView(
                    proposals: proposals,
                    onApprove: { orchestrator.approveProject($0) },
                    onReject: { orchestrator.rejectProject($0) }
                )
            } else {
                sectionPlaceholder(for: section)
            }

        case .skills:
            if let groups = orchestrator.generatedSkillGroups {
                SkillsGroupingView(groups: groups)
            } else {
                sectionPlaceholder(for: section)
            }

        case .custom:
            CustomSectionDetailView(
                titleSets: orchestrator.generatedTitleSets,
                objective: orchestrator.generatedObjective
            )

        default:
            sectionPlaceholder(for: section)
        }
    }

    private func sectionPlaceholder(for section: ExperienceSectionKey) -> some View {
        ContentUnavailableView {
            Label(section.rawValue.capitalized, systemImage: sectionIcon(for: section))
        } description: {
            Text("Content will appear here after generation.")
        }
    }

    private var welcomeView: some View {
        ContentUnavailableView {
            Label("Seed Generation", systemImage: "wand.and.stars")
        } description: {
            Text("Select a section from the sidebar to view progress, or wait for items to appear in the review queue.")
        }
    }

    // MARK: - Helpers

    private func sectionIcon(for section: ExperienceSectionKey) -> String {
        switch section {
        case .work: return "briefcase.fill"
        case .education: return "graduationcap.fill"
        case .volunteer: return "heart.fill"
        case .projects: return "hammer.fill"
        case .skills: return "star.fill"
        case .awards: return "trophy.fill"
        case .certificates: return "rosette"
        case .publications: return "book.fill"
        case .languages: return "globe"
        case .interests: return "leaf.fill"
        case .references: return "person.2.fill"
        case .custom: return "doc.fill"
        }
    }
}

// MARK: - Section Progress Row

struct SectionProgressRow: View {
    let progress: SeedGenerationOrchestrator.SectionProgress

    var body: some View {
        HStack {
            statusIcon
            Text(progress.section.rawValue.capitalized)
            Spacer()
            progressText
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch progress.status {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
        case .running:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var progressText: some View {
        if progress.totalTasks > 0 {
            Text("\(progress.completedTasks)/\(progress.totalTasks)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

// MARK: - Custom Section Detail View

struct CustomSectionDetailView: View {
    let titleSets: [TitleSet]?
    let objective: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let sets = titleSets, !sets.isEmpty {
                    titleSetsSection(sets)
                }

                if let summary = objective, !summary.isEmpty {
                    objectiveSection(summary)
                }

                if titleSets == nil && objective == nil {
                    ContentUnavailableView {
                        Label("Custom Content", systemImage: "doc.fill")
                    } description: {
                        Text("Title options and professional summary will appear here after generation.")
                    }
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func titleSetsSection(_ sets: [TitleSet]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Professional Title Options", systemImage: "person.text.rectangle")
                .font(.headline)

            Text("Generated title combinations for your resume header. Select your favorites in the review queue.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(sets) { set in
                HStack(spacing: 8) {
                    ForEach(set.titles, id: \.self) { title in
                        Text(title)
                            .font(.callout)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                    Spacer()
                    Text(set.emphasis.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func objectiveSection(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Professional Summary", systemImage: "text.alignleft")
                .font(.headline)

            Text(summary)
                .font(.body)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}
