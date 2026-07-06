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
