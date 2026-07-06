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

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(KnowledgeCardStore.self) private var knowledgeCardStore
    @Environment(CandidateDossierStore.self) private var candidateDossierStore
    @Environment(CoverRefStore.self) private var coverRefStore
    // Optional reads: present in the main window's environment but not the
    // Discovery window's. The Choose Best model picker requires the enabled-LLM
    // store, so its button disables where the store is absent instead of
    // crashing the sheet.
    @Environment(EnabledLLMStore.self) private var enabledLLMStore: EnabledLLMStore?
    @Environment(ReasoningStreamState.self) private var reasoningStream: ReasoningStreamState?

    @State private var showingAddLead = false
    @State private var showingJobSearch = false
    @State private var isChooseBestActive = false
    @State private var isChoosingBest = false
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
                    .help("Search Dice and ZipRecruiter and import results as leads")

                    chooseBestButton

                    Toggle(isOn: $showClosedColumns) {
                        Label("Closed", systemImage: "archivebox")
                    }
                    .toggleStyle(.button)
                    .help("Show the Rejected and Withdrawn columns")

                    Button {
                        showingAddLead = true
                    } label: {
                        Label("Add Lead", systemImage: "plus")
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.windowBackgroundColor))
            .overlay(alignment: .bottom) {
                Divider()
            }

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
    }

    // MARK: - Choose Best

    @ViewBuilder
    private var chooseBestButton: some View {
        if let enabledLLMStore {
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
                    llmFacade: appEnvironment.llmFacade,
                    openRouterService: appEnvironment.openRouterService,
                    enabledLLMStore: enabledLLMStore,
                    reasoningStream: reasoningStream
                )
            )
        } else {
            Button {} label: {
                chooseBestLabel
            }
            .disabled(true)
            .help("Choose Best runs from the Pipeline module in the main window")
        }
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

            // Quick advance (hover); non-linear moves live in the stage menu
            if isHovered && status.canAdvance {
                Button("Advance") {
                    onAdvance()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .transition(.opacity)
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
            moveMenuItems
        }
        .onTapGesture {
            onSelect()
        }
        .padding(.horizontal, 8)
    }

    /// Direct move to any other stage — pipeline reality is non-linear
    /// (lead → interview happens), so every stage is one click away.
    @ViewBuilder
    private var moveMenuItems: some View {
        Section("Move to") {
            ForEach(Statuses.pipelineStatuses.filter { $0 != status }, id: \.self) { target in
                Button {
                    onMove(target)
                } label: {
                    Label(target.displayName, systemImage: target.icon)
                }
            }
        }
    }
}
