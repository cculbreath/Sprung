//
//  PipelineView.swift
//  Sprung
//
//  Kanban-style pipeline view for job applications.
//  Shows applications organized by status stages.
//

import SwiftUI

struct PipelineView: View {
    let coordinator: SearchOpsCoordinator

    @State private var selectedStage: ApplicationStage? = nil
    @State private var showingAddLead = false

    private var stages: [(ApplicationStage, [JobApp])] {
        ApplicationStage.allCases.compactMap { stage in
            let leads = coordinator.jobAppStore.jobApps(forStage: stage)
            guard !leads.isEmpty || stage == .identified else { return nil }
            return (stage, leads)
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(ApplicationStage.allCases, id: \.self) { stage in
                    PipelineStageColumn(
                        stage: stage,
                        leads: coordinator.jobAppStore.jobApps(forStage: stage),
                        onAdvance: { lead in advanceLead(lead) },
                        onReject: { lead in rejectLead(lead) }
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Application Pipeline")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddLead = true
                } label: {
                    Image(systemName: "plus")
                }
            }

            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    ForEach(ApplicationStage.allCases, id: \.self) { stage in
                        let count = coordinator.jobAppStore.jobApps(forStage: stage).count
                        Text("\(stage.rawValue): \(count)")
                    }
                } label: {
                    Label("Summary", systemImage: "chart.bar")
                }
            }
        }
        .sheet(isPresented: $showingAddLead) {
            AddLeadView(coordinator: coordinator)
        }
    }

    private func advanceLead(_ lead: JobApp) {
        coordinator.jobAppStore.advanceStage(lead)
    }

    private func rejectLead(_ lead: JobApp) {
        coordinator.jobAppStore.reject(lead, reason: nil)
    }
}

// MARK: - Stage Column

struct PipelineStageColumn: View {
    let stage: ApplicationStage
    let leads: [JobApp]
    let onAdvance: (JobApp) -> Void
    let onReject: (JobApp) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: stage.icon)
                    .foregroundStyle(stage.color)
                Text(stage.rawValue)
                    .font(.headline)
                Spacer()
                Text("\(leads.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(stage.color.opacity(0.2))
                    .cornerRadius(8)
            }
            .padding(.horizontal, 12)

            // Cards
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(leads) { lead in
                        PipelineLeadCard(
                            lead: lead,
                            stage: stage,
                            onAdvance: { onAdvance(lead) },
                            onReject: { onReject(lead) }
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
    let stage: ApplicationStage
    let onAdvance: () -> Void
    let onReject: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Company and Role
            Text(lead.companyName)
                .font(.headline)
                .lineLimit(1)

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

            // Action buttons (show on hover or always on last card)
            if isHovered && !stage.isTerminal {
                HStack {
                    if stage.canAdvance {
                        Button("Advance") {
                            onAdvance()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }

                    Button("Reject") {
                        onReject()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .transition(.opacity)
            }
        }
        .padding(12)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
        .shadow(radius: isHovered ? 4 : 1)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - Add Lead View

struct AddLeadView: View {
    let coordinator: SearchOpsCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var company = ""
    @State private var role = ""
    @State private var source = ""
    @State private var url = ""
    @State private var notes = ""
    @State private var priority: JobLeadPriority = .medium

    var body: some View {
        VStack(spacing: 20) {
            Text("Add New Lead")
                .font(.title2)
                .fontWeight(.semibold)

            Form {
                TextField("Company", text: $company)
                TextField("Role", text: $role)
                TextField("Source (e.g., LinkedIn, Indeed)", text: $source)
                TextField("Job URL", text: $url)

                Picker("Priority", selection: $priority) {
                    ForEach(JobLeadPriority.allCases, id: \.self) { p in
                        Text(p.rawValue).tag(p)
                    }
                }

                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add Lead") {
                    addLead()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(company.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(width: 400, height: 400)
    }

    private func addLead() {
        let lead = JobApp(
            jobPosition: role,
            jobLocation: "",
            companyName: company,
            companyLinkedinId: "",
            jobPostingTime: "",
            jobDescription: "",
            seniorityLevel: "",
            employmentType: "",
            jobFunction: "",
            industries: "",
            jobApplyLink: "",
            postingURL: url
        )
        lead.priority = priority
        lead.source = source.isEmpty ? nil : source
        lead.stage = .identified
        lead.identifiedDate = Date()
        if !notes.isEmpty {
            lead.notes = notes
        }
        coordinator.jobAppStore.addToPipeline(lead)
    }
}

// MARK: - ApplicationStage Extensions

extension ApplicationStage {
    var icon: String {
        switch self {
        case .identified: return "eye"
        case .researching: return "magnifyingglass"
        case .applying: return "doc.text"
        case .applied: return "paperplane"
        case .interviewing: return "person.2"
        case .offer: return "gift"
        case .accepted: return "checkmark.seal"
        case .rejected: return "xmark.circle"
        case .withdrawn: return "arrow.uturn.left"
        }
    }

    var color: Color {
        switch self {
        case .identified: return .gray
        case .researching: return .blue
        case .applying: return .indigo
        case .applied: return .purple
        case .interviewing: return .orange
        case .offer: return .green
        case .accepted: return .mint
        case .rejected: return .red
        case .withdrawn: return .secondary
        }
    }

    var isTerminal: Bool {
        switch self {
        case .accepted, .rejected, .withdrawn: return true
        default: return false
        }
    }

    var canAdvance: Bool {
        !isTerminal
    }
}
