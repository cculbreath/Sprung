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

    @State private var isRefreshingSources = false
    @State private var showResetConfirmation = false
    @State private var sourceRefreshError: String?

    var body: some View {
        Section {
            // Calendar Integration
            calendarSettings

            Divider()
                .padding(.vertical, 4)

            // Notifications
            notificationSettings

            Divider()
                .padding(.vertical, 4)

            // Actions
            actionButtons
        } header: {
            SettingsSectionHeader(title: "Discovery", systemImage: "magnifyingglass.circle.fill")
        }
    }

    // MARK: - Calendar Settings

    private var calendarSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Use dedicated Job Search calendar", isOn: Binding(
                get: { coordinator.settingsStore.current().useJobSearchCalendar },
                set: { newValue in
                    var s = coordinator.settingsStore.current()
                    s.useJobSearchCalendar = newValue
                    coordinator.settingsStore.update(s)
                    if newValue {
                        // TODO: Create/find job search calendar
                    }
                }
            ))
            Text("Creates a separate calendar for networking events and interview prep.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Notification Settings

    private var notificationSettings: some View {
        let currentSettings = coordinator.settingsStore.current()
        return VStack(alignment: .leading, spacing: 12) {
            // Master toggle
            Toggle("Enable notifications", isOn: Binding(
                get: { coordinator.settingsStore.current().notificationsEnabled },
                set: { newValue in
                    var s = coordinator.settingsStore.current()
                    s.notificationsEnabled = newValue
                    coordinator.settingsStore.update(s)
                }
            ))

            if currentSettings.notificationsEnabled {
                // Daily briefing
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Daily briefing", isOn: Binding(
                        get: { coordinator.settingsStore.current().dailyBriefingEnabled },
                        set: { newValue in
                            var s = coordinator.settingsStore.current()
                            s.dailyBriefingEnabled = newValue
                            coordinator.settingsStore.update(s)
                        }
                    ))

                    if currentSettings.dailyBriefingEnabled {
                        HStack {
                            Text("Time:")
                                .foregroundStyle(.secondary)
                            DatePicker(
                                "",
                                selection: dailyBriefingTime,
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()
                        }
                        .padding(.leading, 20)
                    }
                }

                // Follow-up reminders
                Toggle("Follow-up reminders", isOn: Binding(
                    get: { coordinator.settingsStore.current().followUpRemindersEnabled },
                    set: { newValue in
                        var s = coordinator.settingsStore.current()
                        s.followUpRemindersEnabled = newValue
                        coordinator.settingsStore.update(s)
                    }
                ))

                // Weekly review
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Weekly review", isOn: Binding(
                        get: { coordinator.settingsStore.current().weeklyReviewEnabled },
                        set: { newValue in
                            var s = coordinator.settingsStore.current()
                            s.weeklyReviewEnabled = newValue
                            coordinator.settingsStore.update(s)
                        }
                    ))

                    if currentSettings.weeklyReviewEnabled {
                        HStack {
                            Text("Day:")
                                .foregroundStyle(.secondary)
                            Picker("", selection: Binding(
                                get: { coordinator.settingsStore.current().weeklyReviewDay },
                                set: { newValue in
                                    var s = coordinator.settingsStore.current()
                                    s.weeklyReviewDay = newValue
                                    coordinator.settingsStore.update(s)
                                }
                            )) {
                                Text("Sunday").tag(1)
                                Text("Monday").tag(2)
                                Text("Tuesday").tag(3)
                                Text("Wednesday").tag(4)
                                Text("Thursday").tag(5)
                                Text("Friday").tag(6)
                                Text("Saturday").tag(7)
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()

                            Text("at")
                                .foregroundStyle(.secondary)

                            DatePicker(
                                "",
                                selection: weeklyReviewTime,
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()
                        }
                        .padding(.leading, 20)
                    }
                }
            }
        }
    }

    // Time binding helpers
    private var dailyBriefingTime: Binding<Date> {
        Binding(
            get: {
                let s = coordinator.settingsStore.current()
                var components = DateComponents()
                components.hour = s.dailyBriefingHour
                components.minute = s.dailyBriefingMinute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newDate in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                var s = coordinator.settingsStore.current()
                s.dailyBriefingHour = components.hour ?? 8
                s.dailyBriefingMinute = components.minute ?? 0
                coordinator.settingsStore.update(s)
            }
        )
    }

    private var weeklyReviewTime: Binding<Date> {
        Binding(
            get: {
                let s = coordinator.settingsStore.current()
                var components = DateComponents()
                components.hour = s.weeklyReviewHour
                components.minute = s.weeklyReviewMinute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newDate in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                var s = coordinator.settingsStore.current()
                s.weeklyReviewHour = components.hour ?? 16
                s.weeklyReviewMinute = components.minute ?? 0
                coordinator.settingsStore.update(s)
            }
        )
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    Task { await refreshJobSources() }
                } label: {
                    if isRefreshingSources {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Refresh Job Sources", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshingSources)

                if let error = sourceRefreshError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }

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

    private func refreshJobSources() async {
        isRefreshingSources = true
        sourceRefreshError = nil
        defer { isRefreshingSources = false }

        do {
            // TODO: Call LLM to discover new job sources
            try await Task.sleep(for: .seconds(1))
            Logger.info("Job sources refreshed", category: .ai)
        } catch {
            sourceRefreshError = error.localizedDescription
            Logger.error("Failed to refresh job sources: \(error)", category: .ai)
        }
    }

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
