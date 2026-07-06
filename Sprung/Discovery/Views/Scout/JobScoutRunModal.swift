//
//  JobScoutRunModal.swift
//  Sprung
//
//  Per-run configuration sheet for the Job Scout agent. Boards pre-fill from
//  DiscoverySettingsStore.scoutEnabledBoards, keywords from
//  SearchPreferences.targetSectors, guidance from the standing guidance —
//  every field is a one-run override, never written back to settings.
//  LinkedIn participates only behind the one-time risk consent
//  (LinkedInConsentDialog); declining drops LinkedIn from this run and
//  proceeds with the remaining boards.
//

import SwiftUI

struct JobScoutRunModal: View {
    let coordinator: DiscoveryCoordinator
    /// Invoked immediately after `jobScout.start(config:)` so the presenting
    /// view can mark the run as manually launched (for the report
    /// auto-present) before this sheet dismisses.
    let onRunStarted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(LinkedInMCPServerService.self) private var linkedInServer

    @State private var selectedBoards: Set<JobScoutService.ScoutBoard> = []
    @State private var keywordsText = ""
    @State private var location = ""
    @State private var guidance = ""
    @State private var recommendationCount = 5
    @State private var showingLinkedInConsent = false
    @State private var showingLastReport = false
    /// Sheet state survives SwiftUI re-presentation; only seed the fields once.
    @State private var hasLoadedDefaults = false

    private var parsedKeywords: [String] {
        ScoutKeywordsParser.parse(keywordsText)
    }

    private var canRun: Bool {
        !selectedBoards.isEmpty && !parsedKeywords.isEmpty && !coordinator.jobScout.isActive
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Scout Job Boards")
                .font(.headline)
            Text("The Discovery agent searches the selected boards for new postings and imports its best matches as high-priority leads.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            boardsRow
            keywordsField
            locationField
            guidanceField

            Stepper("Recommendations: \(recommendationCount)", value: $recommendationCount, in: 1...10)

            lastRunLine

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Run Scout") {
                    runTapped()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canRun)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear(perform: loadDefaults)
        .sheet(isPresented: $showingLinkedInConsent) {
            // One-time risk consent gates LinkedIn's first automated call.
            // Accepting persists the flag and starts the run as configured;
            // declining drops LinkedIn from this run and proceeds with the
            // remaining boards (staying open if LinkedIn was the only one).
            LinkedInConsentDialog(
                onAccept: {
                    linkedInServer.acceptConsent()
                    showingLinkedInConsent = false
                    startRun()
                },
                onDecline: {
                    showingLinkedInConsent = false
                    selectedBoards.remove(.linkedIn)
                    if !selectedBoards.isEmpty {
                        startRun()
                    }
                }
            )
        }
        .sheet(isPresented: $showingLastReport) {
            if let report = coordinator.settingsStore.lastScoutReport {
                JobScoutReportSheet(report: report)
            }
        }
    }

    // MARK: - Fields

    private var boardsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Boards")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 16) {
                ForEach(JobScoutService.ScoutBoard.allCases) { board in
                    Toggle(board.displayName, isOn: boardBinding(board))
                        .toggleStyle(.checkbox)
                }
            }
        }
    }

    private var keywordsField: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Role keywords (comma-separated)", text: $keywordsText)
                .textFieldStyle(.roundedBorder)
            Text("Pre-filled from your target sectors; edit for this run only.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var locationField: some View {
        TextField("Location", text: $location)
            .textFieldStyle(.roundedBorder)
    }

    private var guidanceField: some View {
        TextField("Optional guidance for this run", text: $guidance, axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .lineLimit(2...4)
    }

    @ViewBuilder
    private var lastRunLine: some View {
        if let report = coordinator.settingsStore.lastScoutReport {
            HStack(spacing: 8) {
                Text(
                    "Last run \(report.startedAt.formatted(date: .abbreviated, time: .shortened)) — "
                    + "found \(report.resultsFound), recommended \(report.recommendations.count)"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Button("View Report") {
                    showingLastReport = true
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
    }

    // MARK: - Actions

    private func loadDefaults() {
        guard !hasLoadedDefaults else { return }
        hasLoadedDefaults = true
        selectedBoards = Set(coordinator.settingsStore.scoutEnabledBoards)
        let prefs = coordinator.preferencesStore.current()
        keywordsText = ScoutKeywordsParser.join(prefs.targetSectors)
        location = prefs.primaryLocation
        guidance = coordinator.settingsStore.scoutStandingGuidance
        recommendationCount = min(max(coordinator.settingsStore.scoutRecommendationCount, 1), 10)
    }

    private func boardBinding(_ board: JobScoutService.ScoutBoard) -> Binding<Bool> {
        Binding(
            get: { selectedBoards.contains(board) },
            set: { enabled in
                if enabled {
                    selectedBoards.insert(board)
                } else {
                    selectedBoards.remove(board)
                }
            }
        )
    }

    private func runTapped() {
        if selectedBoards.contains(.linkedIn) && !linkedInServer.consentAccepted {
            showingLinkedInConsent = true
            return
        }
        startRun()
    }

    private func startRun() {
        let config = JobScoutService.ScoutRunConfig(
            boards: selectedBoards,
            keywords: parsedKeywords,
            location: location.trimmingCharacters(in: .whitespacesAndNewlines),
            guidance: guidance.trimmingCharacters(in: .whitespacesAndNewlines),
            recommendationCount: recommendationCount
        )
        coordinator.jobScout.start(config: config)
        onRunStarted()
        dismiss()
    }
}
