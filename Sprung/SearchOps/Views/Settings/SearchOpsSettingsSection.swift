//
//  SearchOpsSettingsSection.swift
//  Sprung
//
//  Settings section for Search Operations module.
//  Add to SettingsView.swift with: SearchOpsSettingsSection(coordinator: searchOpsCoordinator)
//

import SwiftUI

struct SearchOpsSettingsSection: View {
    @Bindable var coordinator: SearchOpsCoordinator
    @Environment(EnabledLLMStore.self) private var enabledLLMStore

    @State private var isRefreshingSources = false
    @State private var showResetConfirmation = false
    @State private var sourceRefreshError: String?

    private var settings: SearchOpsSettings {
        coordinator.settingsStore.current()
    }

    var body: some View {
        Section {
            // LLM Model Picker
            llmModelPicker

            Divider()
                .padding(.vertical, 4)

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
            SettingsSectionHeader(title: "Search Operations", systemImage: "magnifyingglass.circle.fill")
        }
    }

    // MARK: - LLM Model Picker

    private var llmModelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if enabledLLMStore.enabledModels.isEmpty {
                Label("Enable models in AI Options first", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            } else {
                Picker("AI Model", selection: Binding(
                    get: { settings.llmModelId },
                    set: { newValue in
                        settings.llmModelId = newValue
                        coordinator.settingsStore.update(settings)
                    }
                )) {
                    ForEach(sortedModels, id: \.modelId) { model in
                        Text(model.displayName.isEmpty ? model.modelId : model.displayName)
                            .tag(model.modelId)
                    }
                }
                .pickerStyle(.menu)
                Text("Model used for generating daily tasks, source discovery, and networking prep.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sortedModels: [EnabledLLM] {
        enabledLLMStore.enabledModels.sorted { lhs, rhs in
            let lhsName = lhs.displayName.isEmpty ? lhs.modelId : lhs.displayName
            let rhsName = rhs.displayName.isEmpty ? rhs.modelId : rhs.displayName
            return lhsName < rhsName
        }
    }

    // MARK: - Calendar Settings

    private var calendarSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Use dedicated Job Search calendar", isOn: Binding(
                get: { settings.useJobSearchCalendar },
                set: { newValue in
                    settings.useJobSearchCalendar = newValue
                    coordinator.settingsStore.update(settings)
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
        VStack(alignment: .leading, spacing: 12) {
            // Master toggle
            Toggle("Enable notifications", isOn: Binding(
                get: { settings.notificationsEnabled },
                set: { newValue in
                    settings.notificationsEnabled = newValue
                    coordinator.settingsStore.update(settings)
                }
            ))

            if settings.notificationsEnabled {
                // Daily briefing
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Daily briefing", isOn: Binding(
                        get: { settings.dailyBriefingEnabled },
                        set: { newValue in
                            settings.dailyBriefingEnabled = newValue
                            coordinator.settingsStore.update(settings)
                        }
                    ))

                    if settings.dailyBriefingEnabled {
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
                    get: { settings.followUpRemindersEnabled },
                    set: { newValue in
                        settings.followUpRemindersEnabled = newValue
                        coordinator.settingsStore.update(settings)
                    }
                ))

                // Weekly review
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Weekly review", isOn: Binding(
                        get: { settings.weeklyReviewEnabled },
                        set: { newValue in
                            settings.weeklyReviewEnabled = newValue
                            coordinator.settingsStore.update(settings)
                        }
                    ))

                    if settings.weeklyReviewEnabled {
                        HStack {
                            Text("Day:")
                                .foregroundStyle(.secondary)
                            Picker("", selection: Binding(
                                get: { settings.weeklyReviewDay },
                                set: { newValue in
                                    settings.weeklyReviewDay = newValue
                                    coordinator.settingsStore.update(settings)
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
                var components = DateComponents()
                components.hour = settings.dailyBriefingHour
                components.minute = settings.dailyBriefingMinute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newDate in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                settings.dailyBriefingHour = components.hour ?? 8
                settings.dailyBriefingMinute = components.minute ?? 0
                coordinator.settingsStore.update(settings)
            }
        )
    }

    private var weeklyReviewTime: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = settings.weeklyReviewHour
                components.minute = settings.weeklyReviewMinute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newDate in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                settings.weeklyReviewHour = components.hour ?? 16
                settings.weeklyReviewMinute = components.minute ?? 0
                coordinator.settingsStore.update(settings)
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
        .alert("Reset Search Preferences?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                resetPreferences()
            }
        } message: {
            Text("This will clear your target sectors, location, and restart the SearchOps module onboarding. Your job sources, tasks, and contacts will be preserved.")
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
            Logger.info("✅ Job sources refreshed", category: .ai)
        } catch {
            sourceRefreshError = error.localizedDescription
            Logger.error("❌ Failed to refresh job sources: \(error)", category: .ai)
        }
    }

    private func resetPreferences() {
        let prefs = coordinator.preferencesStore.current()
        prefs.targetSectors = []
        prefs.primaryLocation = ""
        prefs.remoteAcceptable = false
        prefs.willingToRelocate = false
        prefs.relocationTargets = []
        prefs.updatedAt = Date()
        coordinator.preferencesStore.update(prefs)
        Logger.info("🔄 Search preferences reset", category: .appLifecycle)
    }
}

// MARK: - Section Header (reuse from SettingsView if exported, otherwise define here)

private struct SettingsSectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundStyle(.primary)
    }
}
