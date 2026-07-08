//
//  DiscoverySettingsSection.swift
//  Sprung
//
//  Settings section for Search Operations module.
//  Model pickers have been moved to ModelsSettingsView.
//

import SwiftUI

struct DiscoverySettingsSection: View {
    @Bindable var coordinator: DiscoveryCoordinator

    @State private var showResetConfirmation = false

    var body: some View {
        Section {
            // Event Discovery
            eventDiscoverySettings

            Divider()
                .padding(.vertical, 4)

            // Job Scout
            jobScoutSettings

            Divider()
                .padding(.vertical, 4)

            // Actions
            actionButtons
        } header: {
            SettingsSectionHeader(title: "Discovery", systemImage: "magnifyingglass.circle.fill")
        }
    }

    // MARK: - Event Discovery Settings

    private var eventDiscoverySettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Discover networking events weekly", isOn: Binding(
                get: { coordinator.settingsStore.eventDiscoveryAutoRunEnabled },
                set: { newValue in
                    coordinator.settingsStore.eventDiscoveryAutoRunEnabled = newValue
                }
            ))

            TextField(
                "Optional standing guidance for automatic runs",
                text: Binding(
                    get: { coordinator.settingsStore.eventDiscoveryStandingGuidance },
                    set: { newValue in
                        coordinator.settingsStore.eventDiscoveryStandingGuidance = newValue
                    }
                ),
                axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .lineLimit(2...4)
            .padding(.leading, 20)

            Text("Runs about once a week in the background using the Discovery model. Guidance here steers every automatic run; manual runs from the Events view ask separately.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Job Scout Settings

    private var jobScoutSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Job Scout")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 16) {
                Text("Boards:")
                ForEach(JobScoutService.ScoutBoard.allCases) { board in
                    Toggle(board.displayName, isOn: scoutBoardBinding(board))
                        .toggleStyle(.checkbox)
                }
            }

            Picker("Automatic runs", selection: scoutCadenceBinding) {
                ForEach(DiscoverySettingsStore.ScoutCadence.allCases, id: \.self) { cadence in
                    Text(cadence.rawValue.capitalized).tag(cadence)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()

            TextField(
                "Optional standing guidance for scout runs",
                text: Binding(
                    get: { coordinator.settingsStore.scoutStandingGuidance },
                    set: { newValue in
                        coordinator.settingsStore.scoutStandingGuidance = newValue
                    }
                ),
                axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .lineLimit(2...4)
            .padding(.leading, 20)

            Stepper(
                "Recommendations per run: \(coordinator.settingsStore.scoutRecommendationCount)",
                value: Binding(
                    get: { coordinator.settingsStore.scoutRecommendationCount },
                    set: { newValue in
                        coordinator.settingsStore.scoutRecommendationCount = newValue
                    }
                ),
                in: 1...10
            )

            Toggle("Auto-import strong matches", isOn: Binding(
                get: { coordinator.settingsStore.scoutAutoImportStrongMatches },
                set: { newValue in
                    coordinator.settingsStore.scoutAutoImportStrongMatches = newValue
                }
            ))

            Text("Scout runs use the Discovery Anthropic model and share LinkedIn's 30-calls-per-hour budget with manual searches. Recommendations wait in the run's review sheet — you import the ones worth pursuing. With auto-import on, picks the agent rates a strong overall match land in the pipeline automatically; the rest still wait for review.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func scoutBoardBinding(_ board: JobScoutService.ScoutBoard) -> Binding<Bool> {
        Binding(
            get: { coordinator.settingsStore.scoutEnabledBoards.contains(board) },
            set: { enabled in
                var boards = coordinator.settingsStore.scoutEnabledBoards
                if enabled {
                    if !boards.contains(board) { boards.append(board) }
                } else {
                    boards.removeAll { $0 == board }
                }
                // Persist in canonical case order so the stored list is stable
                // regardless of toggle sequence.
                coordinator.settingsStore.scoutEnabledBoards =
                    JobScoutService.ScoutBoard.allCases.filter { boards.contains($0) }
            }
        )
    }

    private var scoutCadenceBinding: Binding<DiscoverySettingsStore.ScoutCadence> {
        Binding(
            get: { coordinator.settingsStore.scoutAutoRunCadence },
            set: { newValue in
                coordinator.settingsStore.scoutAutoRunCadence = newValue
            }
        )
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(role: .destructive) {
                showResetConfirmation = true
            } label: {
                Label("Reset Search Preferences", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
        }
        .alert("Reset Discovery Preferences?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                resetPreferences()
            }
        } message: {
            Text("This will clear your target sectors, location, and restart Discovery onboarding. Your job sources, tasks, and contacts will be preserved.")
        }
    }

    // MARK: - Actions

    private func resetPreferences() {
        var prefs = coordinator.preferencesStore.current()
        prefs.targetSectors = []
        prefs.primaryLocation = ""
        prefs.remoteAcceptable = false
        prefs.willingToRelocate = false
        prefs.relocationTargets = []
        prefs.updatedAt = Date()
        coordinator.preferencesStore.update(prefs)
        Logger.info("Search preferences reset", category: .appLifecycle)
    }
}
