//
//  PipelineView.swift
//  Sprung
//
//  Kanban-style pipeline view for job applications.
//  Shows applications organized by status stages.
//

import SwiftUI

struct PipelineView: View {
    let coordinator: DiscoveryCoordinator

    @Environment(KnowledgeCardStore.self) private var knowledgeCardStore
    @Environment(CandidateDossierStore.self) private var candidateDossierStore
    @Environment(CoverRefStore.self) private var coverRefStore
    @Environment(ApplicantProfileStore.self) private var applicantProfileStore

    @State private var showingAddLead = false
    @State private var showingJobSearch = false
    @State private var isChooseBestActive = false
    @State private var isChoosingBest = false
    @State private var showingScoutModal = false
    /// First-run gate: the Scout button presents the existing Discovery
    /// onboarding wizard (never a new capture flow) when preferences are
    /// missing, then continues to the run modal.
    @State private var showingScoutOnboarding = false
    @State private var showingScoutReport = false
    /// True between a run-modal launch and its completion — only manually
    /// launched runs auto-present the report sheet (auto-runs surface through
    /// the status pill and the modal's last-run line instead).
    @State private var scoutManualRunInFlight = false
    /// Terminal history (Rejected/Withdrawn) stays off the working board unless
    /// the user opts in.
    @AppStorage("pipelineShowClosedColumns") private var showClosedColumns = false

    private var identifiedCount: Int {
        coordinator.jobAppStore.jobApps(forStatus: .new).count
    }

    private var visibleStatuses: [Statuses] {
        Statuses.pipelineStatuses.filter { showClosedColumns || ($0 != .rejected && $0 != .withdrawn) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Module header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Application Pipeline")
                        .font(.headline)
                    Text("Kanban board for job applications")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    scoutButton

                    chooseBestButton

                    Button {
                        showingAddLead = true
                    } label: {
                        Label("Add Lead", systemImage: "plus")
                    }

                    overflowMenu
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.windowBackgroundColor))
            .overlay(alignment: .bottom) {
                Divider()
            }

            filterBar

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(visibleStatuses, id: \.self) { status in
                        PipelineStatusColumn(
                            status: status,
                            leads: coordinator.jobAppStore.jobApps(forStatus: status),
                            onAdvance: { lead in coordinator.jobAppStore.advanceStatus(lead) },
                            onMove: { lead, target in coordinator.jobAppStore.setStatus(lead, to: target) },
                            onSelect: { lead in selectLead(lead) }
                        )
                    }
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("")
        .sheet(isPresented: $showingAddLead) {
            // Leads enter through the same URL-import path as every other job
            // (LLM extraction + background preprocessing). JobAppStore is
            // injected explicitly because the Discovery window does not carry
            // it in its environment.
            NewAppSheetView(isPresented: $showingAddLead)
                .environment(coordinator.jobAppStore)
        }
        .sheet(isPresented: $showingJobSearch) {
            JobSearchSheet(jobAppStore: coordinator.jobAppStore)
        }
        .sheet(isPresented: $showingScoutOnboarding) {
            // First-run prefs capture IS the existing Discovery onboarding
            // wizard — same init args as DailyTasksModuleView. Completing it
            // continues straight into the run modal.
            DiscoveryOnboardingView(
                coordinator: coordinator,
                candidateDossierStore: candidateDossierStore,
                applicantProfileStore: applicantProfileStore
            ) {
                showingScoutOnboarding = false
                showingScoutModal = true
            }
            .overlay(alignment: .topTrailing) {
                // The wizard has no cancel affordance of its own (it normally
                // replaces the Daily view inline); as a sheet it needs one.
                Button("Cancel") { showingScoutOnboarding = false }
                    .keyboardShortcut(.cancelAction)
                    .padding(12)
            }
            .frame(minWidth: 640, idealWidth: 720, minHeight: 560, idealHeight: 640)
        }
        .sheet(isPresented: $showingScoutModal) {
            JobScoutRunModal(coordinator: coordinator) {
                scoutManualRunInFlight = true
            }
        }
        .sheet(isPresented: $showingScoutReport) {
            if let startedAt = coordinator.jobScout.lastReport?.startedAt {
                JobScoutReviewSheet(service: coordinator.jobScout, runStartedAt: startedAt)
            }
        }
        .onChange(of: coordinator.jobScout.isActive) { wasActive, isActive in
            // Auto-present the review sheet when a manually launched run finishes.
            guard wasActive, !isActive, scoutManualRunInFlight else { return }
            scoutManualRunInFlight = false
            if coordinator.jobScout.lastReport != nil {
                showingScoutReport = true
            }
        }
    }

    private var scoutPendingCount: Int {
        JobScoutService.pendingCount(in: coordinator.jobScout.lastReport)
    }

    // MARK: - Overflow & Filters

    /// Secondary, low-frequency actions that don't earn a spot in the L1
    /// header: the per-stage count breakdown and the custom-site board
    /// search. `Summary` stays a static breakdown here rather than a
    /// Board/Summary `ViewModeToggle` — there is no separate Summary view to
    /// switch into, so inventing one is out of scope for this pass.
    private var overflowMenu: some View {
        Menu {
            Menu {
                ForEach(Statuses.pipelineStatuses, id: \.self) { status in
                    let count = coordinator.jobAppStore.jobApps(forStatus: status).count
                    Text("\(status.displayName): \(count)")
                }
            } label: {
                Label("Summary", systemImage: "chart.bar")
            }

            Button {
                showingJobSearch = true
            } label: {
                Label("Search Boards", systemImage: "magnifyingglass")
            }
            .help("Search Dice, ZipRecruiter, or any job site via the custom-site agent, and import results as leads")
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .help("More: stage summary, board search")
    }

    /// L3 filter-bar row: the show-closed-columns toggle promoted out of the
    /// overflow menu into a first-class filter chip.
    private var filterBar: some View {
        HStack(spacing: 8) {
            FilterChip(label: "Closed", isSelected: showClosedColumns) {
                showClosedColumns.toggle()
            }
            .help("Show the Rejected and Withdrawn columns")

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Scout

    private var scoutButton: some View {
        Button {
            if coordinator.needsOnboarding {
                showingScoutOnboarding = true
            } else {
                showingScoutModal = true
            }
        } label: {
            scoutLabel
        }
        .disabled(coordinator.jobScout.isActive)
        .help(
            coordinator.jobScout.isActive
                ? "Scout run in progress"
                : scoutPendingCount > 0
                    ? "Have the Discovery agent scout the job boards — \(scoutPendingCount) recommendation\(scoutPendingCount == 1 ? "" : "s") awaiting your review"
                    : "Have the Discovery agent scout the job boards and recommend leads for your review"
        )
    }

    private var scoutLabel: some View {
        Group {
            if coordinator.jobScout.isActive {
                Label("Scout", systemImage: "sparkle")
                    .symbolEffect(.rotate.byLayer)
            } else {
                Label("Scout", systemImage: "binoculars")
            }
        }
        .overlay(alignment: .topTrailing) {
            if !coordinator.jobScout.isActive, scoutPendingCount > 0 {
                Text("\(scoutPendingCount)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.red))
                    .offset(x: 10, y: -10)
            }
        }
    }

    // MARK: - Choose Best

    private var chooseBestButton: some View {
        Button {
            isChooseBestActive = true
        } label: {
            chooseBestLabel
        }
        .disabled(identifiedCount < 1 || isChoosingBest)
        .help("Select best \(min(5, identifiedCount)) jobs from \(identifiedCount) identified")
        .chooseBestJobsFlow(
            isActive: $isChooseBestActive,
            isProcessing: $isChoosingBest,
            dependencies: ChooseBestJobsFlow.Dependencies(
                jobAppStore: coordinator.jobAppStore,
                knowledgeCardStore: knowledgeCardStore,
                candidateDossierStore: candidateDossierStore,
                coverRefStore: coverRefStore,
                coordinator: coordinator
            )
        )
    }

    private var chooseBestLabel: some View {
        Group {
            if isChoosingBest {
                Label("Choose Best", systemImage: "sparkle")
                    .symbolEffect(.rotate.byLayer)
            } else {
                Label("Choose Best", systemImage: "trophy")
            }
        }
    }

    // MARK: - Actions

    private func selectLead(_ lead: JobApp) {
        // Select the job in the store
        coordinator.jobAppStore.selectedApp = lead

        // Post notification to bring main window to front and select the job
        NotificationCenter.default.post(
            name: .selectJobApp,
            object: nil,
            userInfo: ["jobAppId": lead.id]
        )

        // Activate main app window
        if let mainWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "myApp" || $0.title.isEmpty }) {
            mainWindow.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Job Search Sheet

/// Sheet wrapper around the embeddable `JobSearchView`: adds a dismiss
/// affordance and a workable size for presentation from the kanban header.
private struct JobSearchSheet: View {
    let jobAppStore: JobAppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        JobSearchView(jobAppStore: jobAppStore)
            .overlay(alignment: .topTrailing) {
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .padding(12)
            }
            .frame(minWidth: 760, idealWidth: 860, minHeight: 620, idealHeight: 720)
    }
}

// MARK: - Status Column

struct PipelineStatusColumn: View {
    let status: Statuses
    let leads: [JobApp]
    let onAdvance: (JobApp) -> Void
    let onMove: (JobApp, Statuses) -> Void
    let onSelect: (JobApp) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: status.icon)
                    .foregroundStyle(status.color)
                Text(status.displayName)
                    .font(.headline)
                Spacer()
                Text("\(leads.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(status.color.opacity(0.2))
                    .cornerRadius(8)
            }
            .padding(.horizontal, 12)

            // Cards
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(leads) { lead in
                        PipelineLeadCard(
                            lead: lead,
                            status: status,
                            onAdvance: { onAdvance(lead) },
                            onMove: { target in onMove(lead, target) },
                            onSelect: { onSelect(lead) }
                        )
                    }
                }
            }
        }
        .frame(width: 280)
        .padding(.vertical, 12)
        .background(Color(.windowBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }
}

// MARK: - Lead Card

struct PipelineLeadCard: View {
    let lead: JobApp
    let status: Statuses
    let onAdvance: () -> Void
    let onMove: (Statuses) -> Void
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Company and stage menu
            HStack(alignment: .top) {
                Text(lead.companyName)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Menu {
                    advanceMenuItem
                    moveMenuItems
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Move to any stage")
            }

            if !lead.jobPosition.isEmpty {
                Text(lead.jobPosition)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Source info
            HStack {
                if let source = lead.source {
                    Text(source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let days = lead.daysSinceCreated {
                    Text("\(days)d")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Priority indicator
            if lead.priority != .medium {
                HStack {
                    Image(systemName: lead.priority == .high ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .foregroundStyle(lead.priority == .high ? .red : .gray)
                    Text(lead.priority.rawValue)
                        .font(.caption)
                }
            }

            // Persistent advance affordance — faint at rest so the card isn't
            // busy, full-strength on hover. Discoverable without hovering
            // too: the same action is in the ⋯ menu and context menu above.
            if status.canAdvance {
                Button {
                    onAdvance()
                } label: {
                    Label("Advance", systemImage: "arrow.right.circle.fill")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.tintedPill(tint: status.color))
                .opacity(isHovered ? 1 : 0.4)
            }
        }
        .padding(12)
        .contentShape(Rectangle()) // Make entire card clickable
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(status.color.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(status.color.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(radius: isHovered ? 4 : 1)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            advanceMenuItem
            moveMenuItems
        }
        .onTapGesture {
            onSelect()
        }
        .padding(.horizontal, 8)
    }

    /// Persistent-menu route for the advance action (F2 fix) — mirrors the
    /// inline pill button so advancing never depends on hovering. Only
    /// rendered when there's a next stage to advance to.
    @ViewBuilder
    private var advanceMenuItem: some View {
        if let next = status.next {
            Button {
                onAdvance()
            } label: {
                Label("Advance to \(next.displayName)", systemImage: "arrow.right.circle")
            }
            Divider()
        }
    }

    /// Direct move to any other stage — pipeline reality is non-linear
    /// (lead → interview happens), so every stage is one click away. The
    /// next stage is excluded here since `advanceMenuItem` already offers it.
    @ViewBuilder
    private var moveMenuItems: some View {
        Section("Move to") {
            ForEach(Statuses.pipelineStatuses.filter { $0 != status && $0 != status.next }, id: \.self) { target in
                Button {
                    onMove(target)
                } label: {
                    Label(target.displayName, systemImage: target.icon)
                }
            }
        }
    }
}
