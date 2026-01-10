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
    @Environment(CoverRefStore.self) private var coverRefStore
    @Environment(CandidateDossierStore.self) private var candidateDossierStore

    @State private var showingAddLead = false
    @State private var isChoosing = false
    @State private var selectionResult: JobSelectionsResult?
    @State private var selectionError: String?
    @State private var showingSelectionReport = false

    private var identifiedCount: Int {
        coordinator.jobAppStore.jobApps(forStatus: .new).count
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(Statuses.pipelineStatuses, id: \.self) { status in
                    PipelineStatusColumn(
                        status: status,
                        leads: coordinator.jobAppStore.jobApps(forStatus: status),
                        onAdvance: { lead in advanceLead(lead) },
                        onReject: { lead in rejectLead(lead) },
                        onSelect: { lead in selectLead(lead) }
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

            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await chooseBestJobs() }
                } label: {
                    if isChoosing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Choose Best", systemImage: "trophy")
                    }
                }
                .disabled(identifiedCount < 1 || isChoosing)
                .help("Select best \(min(5, identifiedCount)) jobs from \(identifiedCount) identified")
            }

            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    ForEach(Statuses.pipelineStatuses, id: \.self) { status in
                        let count = coordinator.jobAppStore.jobApps(forStatus: status).count
                        Text("\(status.displayName): \(count)")
                    }
                } label: {
                    Label("Summary", systemImage: "chart.bar")
                }
            }
        }
        .sheet(isPresented: $showingAddLead) {
            AddLeadView(coordinator: coordinator)
        }
        .sheet(isPresented: $showingSelectionReport) {
            if let result = selectionResult {
                SelectionReportSheet(result: result)
            } else if let error = selectionError {
                SelectionErrorSheet(error: error)
            }
        }
    }

    private func chooseBestJobs() async {
        isChoosing = true
        selectionError = nil

        // Build knowledge context from KnowledgeCards
        let knowledgeContext = knowledgeCardStore.knowledgeCards
            .map { card in
                let typeLabel = "[\(card.cardType?.rawValue ?? "general")]"
                return "\(typeLabel) \(card.title):\n\(card.narrative)"
            }
            .joined(separator: "\n\n")

        // Build dossier context from CandidateDossier + writing samples
        var dossierParts: [String] = []
        if let dossier = candidateDossierStore.dossier {
            dossierParts.append(dossier.exportForJobMatching())
        }
        // Append writing samples (CoverRefs) for additional context
        let writingSamples = coverRefStore.storedCoverRefs
            .filter { $0.type == .writingSample }
            .prefix(5)  // Limit to avoid overwhelming context
            .map { "<writing_sample name=\"\($0.name)\">\n\($0.content.prefix(500))...\n</writing_sample>" }
            .joined(separator: "\n\n")
        if !writingSamples.isEmpty {
            dossierParts.append(writingSamples)
        }
        let dossierContext = dossierParts.joined(separator: "\n\n")

        do {
            let result = try await coordinator.chooseBestJobs(
                knowledgeContext: knowledgeContext,
                dossierContext: dossierContext,
                count: 5
            )
            selectionResult = result
            showingSelectionReport = true
        } catch {
            selectionError = error.localizedDescription
            showingSelectionReport = true
        }

        isChoosing = false
    }

    private func advanceLead(_ lead: JobApp) {
        coordinator.jobAppStore.advanceStatus(lead)
    }

    private func rejectLead(_ lead: JobApp) {
        coordinator.jobAppStore.reject(lead, reason: nil)
    }

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

// MARK: - Status Column

struct PipelineStatusColumn: View {
    let status: Statuses
    let leads: [JobApp]
    let onAdvance: (JobApp) -> Void
    let onReject: (JobApp) -> Void
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
                            onReject: { onReject(lead) },
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
    let onReject: () -> Void
    let onSelect: () -> Void

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
            if isHovered && !status.isTerminal {
                HStack {
                    if status.canAdvance {
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
        .onTapGesture {
            onSelect()
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - Add Lead View

struct AddLeadView: View {
    let coordinator: DiscoveryCoordinator
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
        lead.status = .new
        lead.identifiedDate = Date()
        if !notes.isEmpty {
            lead.notes = notes
        }
        coordinator.jobAppStore.addToPipeline(lead)
    }
}


// MARK: - Selection Report Sheet

struct SelectionReportSheet: View {
    let result: JobSelectionsResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Top \(result.selections.count) Job Matches")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Selected and moved to Researching stage")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(.windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Selections
                    ForEach(Array(result.selections.enumerated()), id: \.element.jobId) { index, selection in
                        SelectionCard(selection: selection, rank: index + 1)
                    }

                    // Overall Analysis
                    if !result.overallAnalysis.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Analysis Summary")
                                .font(.headline)
                            Text(result.overallAnalysis)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(8)
                    }

                    // Considerations
                    if !result.considerations.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Things to Consider")
                                .font(.headline)
                            ForEach(result.considerations, id: \.self) { consideration in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "lightbulb")
                                        .foregroundStyle(.yellow)
                                    Text(consideration)
                                        .font(.body)
                                }
                            }
                        }
                        .padding()
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
        }
        .frame(width: 600, height: 700)
    }
}

struct SelectionCard: View {
    let selection: JobSelection
    let rank: Int

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Rank badge
            Text("#\(rank)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(rankColor)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 8) {
                // Company and role
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selection.company)
                            .font(.headline)
                        Text(selection.role)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    // Match score
                    Text("\(Int(selection.matchScore * 100))%")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(scoreColor)
                }

                // Reasoning
                Text(selection.reasoning)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var rankColor: Color {
        switch rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .orange
        default: return .blue
        }
    }

    private var scoreColor: Color {
        if selection.matchScore >= 0.9 { return .green }
        if selection.matchScore >= 0.7 { return .blue }
        return .orange
    }
}

struct SelectionErrorSheet: View {
    let error: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text("Selection Failed")
                .font(.title2)
                .fontWeight(.semibold)

            Text(error)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Dismiss") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .frame(width: 400)
    }
}
