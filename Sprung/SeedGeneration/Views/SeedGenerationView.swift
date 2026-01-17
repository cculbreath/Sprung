//
//  SeedGenerationView.swift
//  Sprung
//
//  Main container view for the Seed Generation Module.
//

import SwiftUI

/// Selection for the sidebar
enum SeedGenerationSelection: Hashable {
    case titleSets
    case section(ExperienceSectionKey)
    case reviewQueue
}

/// Main view for the Seed Generation Module
struct SeedGenerationView: View {
    @State var orchestrator: SeedGenerationOrchestrator

    @Environment(ExperienceDefaultsStore.self) private var defaultsStore
    @Environment(TitleSetStore.self) private var titleSetStore
    @Environment(LLMFacade.self) private var llmFacade

    @State private var selectedItem: SeedGenerationSelection?
    @State private var hasApplied = false
    @State private var isGeneratingProjects = false
    @State private var hasStartedGeneration = false
    @State private var hasAcknowledgedProjectProposals = false

    /// Number of project proposals awaiting user decision
    private var pendingProjectProposalCount: Int {
        guard let proposals = orchestrator.projectProposals else { return 0 }
        return proposals.filter { !$0.isApproved }.count
    }

    /// Whether there are approved projects that need content generated
    private var hasApprovedProjectsNeedingContent: Bool {
        guard let proposals = orchestrator.projectProposals else { return false }
        let approvedCount = proposals.filter { $0.isApproved }.count
        // Check if any approved projects are missing from the review queue
        let projectTasksInQueue = orchestrator.reviewQueue.items.filter { $0.task.section == .projects }.count
        return approvedCount > 0 && projectTasksInQueue < approvedCount
    }

    /// Whether title sets exist and generation can proceed
    private var hasTitleSets: Bool {
        titleSetStore.hasTitleSets
    }

    /// Number of title sets available
    private var titleSetCount: Int {
        titleSetStore.titleSetCount
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            if !hasTitleSets {
                titleSetsRequiredBanner
            } else if !hasStartedGeneration {
                titleSetsReadyBanner
            } else if pendingProjectProposalCount > 0 && !hasAcknowledgedProjectProposals {
                projectProposalsBanner
            } else if pendingProjectProposalCount == 0 && hasApprovedProjectsNeedingContent {
                generateProjectsBanner
            }
            mainContent
            Divider()
            SeedGenerationStatusBar(tracker: orchestrator.activityTracker)
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            // Auto-select title sets if none exist
            if !hasTitleSets {
                selectedItem = .titleSets
            }
        }
        .onChange(of: hasTitleSets) { _, newValue in
            // When title sets become available, keep showing the ready banner
            // User needs to click Continue to start generation
        }
        .onChange(of: orchestrator.projectProposals?.count) { _, _ in
            // Reset acknowledgment when new proposals arrive so banner shows
            hasAcknowledgedProjectProposals = false
        }
    }

    // MARK: - Title Sets Banners

    private var titleSetsRequiredBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("Title Sets Required")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Create professional identity title sets before generating content. These define how you present yourself (e.g., \"Physicist · Developer · Educator\").")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                selectedItem = .titleSets
            } label: {
                Label("Create Title Sets", systemImage: "person.crop.rectangle.stack")
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding()
        .background(.orange.opacity(0.1))
    }

    private var titleSetsReadyBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(titleSetCount) title set\(titleSetCount == 1 ? "" : "s") ready")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Your professional identity is defined. Continue to generate experience content.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task {
                    hasStartedGeneration = true
                    await orchestrator.startGeneration()
                }
            } label: {
                Label("Continue to Generation", systemImage: "arrow.right.circle")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding()
        .background(.green.opacity(0.1))
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

    // MARK: - Project Banners

    private var projectProposalsBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.yellow)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(pendingProjectProposalCount) project proposal\(pendingProjectProposalCount == 1 ? "" : "s") to review")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("AI discovered potential projects from your experience. Review and approve before generating content.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                selectedItem = .section(.projects)
            } label: {
                Label("Review Projects", systemImage: "arrow.right.circle")
            }
            .buttonStyle(.borderedProminent)
            .tint(.yellow)
        }
        .padding()
        .background(.yellow.opacity(0.1))
    }

    private var generateProjectsBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .foregroundStyle(.blue)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("Ready to generate project content")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Generate descriptions and highlights for your approved projects.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task {
                    isGeneratingProjects = true
                    await orchestrator.generateApprovedProjects()
                    isGeneratingProjects = false
                }
            } label: {
                if isGeneratingProjects {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Generate Content", systemImage: "wand.and.stars")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isGeneratingProjects)
        }
        .padding()
        .background(.blue.opacity(0.1))
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
            // Title Sets section - always shown at top
            Section("Professional Identity") {
                Label {
                    HStack {
                        Text("Title Sets")
                        Spacer()
                        if hasTitleSets {
                            Text("\(titleSetCount)")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.cyan, in: Capsule())
                                .foregroundStyle(.white)
                        } else {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                } icon: {
                    Image(systemName: "person.crop.rectangle.stack")
                        .foregroundStyle(hasTitleSets ? .cyan : .orange)
                }
                .tag(SeedGenerationSelection.titleSets)
            }

            // Generation Progress - only show if generation has started
            if hasStartedGeneration {
                Section("Generation Progress") {
                    ForEach(orchestrator.sectionProgress) { progress in
                        SectionProgressRow(progress: progress)
                            .tag(SeedGenerationSelection.section(progress.section))
                    }
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
        case .titleSets:
            TitleSetsBrowserTab(
                titleSetStore: titleSetStore,
                llmFacade: llmFacade,
                skills: orchestrator.context?.skills ?? []
            )
        case .reviewQueue:
            ReviewQueueView(queue: orchestrator.reviewQueue)
        case .section(let section):
            sectionDetailView(for: section)
        case nil:
            if !hasTitleSets {
                // Default to title sets if none exist
                TitleSetsBrowserTab(
                    titleSetStore: titleSetStore,
                    llmFacade: llmFacade,
                    skills: orchestrator.context?.skills ?? []
                )
            } else if orchestrator.reviewQueue.hasPendingItems {
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
                .onAppear {
                    hasAcknowledgedProjectProposals = true
                }
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
