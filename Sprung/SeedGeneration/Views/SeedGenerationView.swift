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
    @State private var hasStartedGeneration = false
    @State private var generationOptions = GenerationOptions.load()

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
                generationSetupPanel
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

    private var generationSetupPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(titleSetCount) title set\(titleSetCount == 1 ? "" : "s") ready")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Set generation limits, then continue to generate experience content.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task {
                        hasStartedGeneration = true
                        await orchestrator.startGeneration(options: generationOptions)
                    }
                } label: {
                    Label("Continue to Generation", systemImage: "arrow.right.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }

            HStack(spacing: 24) {
                optionStepper(
                    label: "Bullets per entry",
                    value: $generationOptions.maxHighlightsPerEntry,
                    range: 2...6,
                    step: 1
                )
                optionStepper(
                    label: "Target lines per bullet",
                    value: $generationOptions.targetBulletLines,
                    range: 1...4,
                    step: 1
                )
                optionStepper(
                    label: "Skill categories",
                    value: $generationOptions.skillCategoryCount,
                    range: 2...8,
                    step: 1
                )
                optionStepper(
                    label: "Max skills per category",
                    value: $generationOptions.maxSkillsPerCategory,
                    range: 3...12,
                    step: 1
                )
                Spacer()
            }
        }
        .padding()
        .background(.green.opacity(0.1))
    }

    private func optionStepper(
        label: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Stepper(value: value, in: range, step: step) {
                Text("\(value.wrappedValue)")
                    .font(.callout)
                    .monospacedDigit()
                    .frame(minWidth: 24, alignment: .trailing)
            }
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
            reviewQueueView(section: nil)
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
                reviewQueueView(section: nil)
            } else {
                welcomeView
            }
        }
    }

    /// Shared review-list construction so section views and the global
    /// queue stay behaviorally identical.
    private func reviewQueueView(section: ExperienceSectionKey?) -> ReviewQueueView {
        ReviewQueueView(
            queue: orchestrator.reviewQueue,
            section: section,
            targetBulletLines: orchestrator.options.targetBulletLines,
            onLineTargetChange: { newTarget in
                var options = orchestrator.options
                options.targetBulletLines = newTarget
                orchestrator.updateOptions(options)
                generationOptions = options
            }
        )
    }

    /// Section detail: every generated item for the section — pending and
    /// reviewed — with the same actions as the global review queue.
    @ViewBuilder
    private func sectionDetailView(for section: ExperienceSectionKey) -> some View {
        if orchestrator.reviewQueue.items.contains(where: { $0.task.section == section }) {
            reviewQueueView(section: section)
        } else {
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
