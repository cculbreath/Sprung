//
//  DiscoverySettingsSection.swift
//  Sprung
//
//  Settings section for Search Operations module.
//  Add to SettingsView.swift with: DiscoverySettingsSection(coordinator: searchOpsCoordinator)
//

import SwiftUI
import SwiftOpenAI

struct DiscoverySettingsSection: View {
    @Bindable var coordinator: DiscoveryCoordinator

    @State private var isRefreshingSources = false
    @State private var showResetConfirmation = false
    @State private var sourceRefreshError: String?
    @State private var llmModelId: String = ""
    @State private var reasoningEffort: String = "low"

    @AppStorage("discoveryCoachingModelId") private var coachingModelId: String = ""
    @State private var openAIModels: [ModelObject] = []
    @State private var isLoadingModels = false
    @State private var modelError: String?

    @Environment(EnabledLLMStore.self) private var enabledLLMStore: EnabledLLMStore?

    private let reasoningOptions = [
        (value: "low", label: "Low"),
        (value: "medium", label: "Medium"),
        (value: "high", label: "High")
    ]

    private var openaiAPIKey: String {
        APIKeyManager.get(.openAI) ?? ""
    }

    private var hasOpenAIKey: Bool {
        !openaiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Filtered models: gpt-4o*, gpt-5*, gpt-6*, gpt-7* (for Responses API compatibility)
    private var filteredModels: [ModelObject] {
        openAIModels
            .filter { model in
                let id = model.id.lowercased()
                return id.hasPrefix("gpt-4o") || id.hasPrefix("gpt-5") || id.hasPrefix("gpt-6") || id.hasPrefix("gpt-7")
            }
            .sorted { $0.id < $1.id }
    }

    var body: some View {
        Section {
            // LLM Model Picker
            llmModelPicker

            // Coaching Model Picker
            coachingModelPicker

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
            SettingsSectionHeader(title: "Discovery", systemImage: "magnifyingglass.circle.fill")
        }
    }

    // MARK: - LLM Model Picker

    private var llmModelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !hasOpenAIKey {
                Label("Add OpenAI API key in API Keys settings first", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            } else if isLoadingModels {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading models...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else if let error = modelError {
                HStack {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                    Button("Retry") {
                        Task { await loadOpenAIModels() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else if filteredModels.isEmpty {
                HStack {
                    Text("No GPT-4o/5/6/7 models available")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Refresh") {
                        Task { await loadOpenAIModels() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                // AI Model picker
                Picker("AI Model", selection: $llmModelId) {
                    ForEach(filteredModels, id: \.id) { model in
                        Text(model.id).tag(model.id)
                    }
                }
                .pickerStyle(.menu)

                // Reasoning effort picker
                Picker("Reasoning Effort", selection: $reasoningEffort) {
                    ForEach(reasoningOptions, id: \.value) { option in
                        Text(option.label).tag(option.value)
                    }
                }
                .pickerStyle(.menu)

                Text("Model and reasoning effort for source discovery and daily tasks.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            let s = coordinator.settingsStore.current()
            llmModelId = s.llmModelId
            reasoningEffort = s.reasoningEffort
            if hasOpenAIKey && openAIModels.isEmpty {
                await loadOpenAIModels()
            }
        }
        .onChange(of: llmModelId) { _, newValue in
            guard !newValue.isEmpty else { return }
            var s = coordinator.settingsStore.current()
            guard s.llmModelId != newValue else { return }
            s.llmModelId = newValue
            coordinator.settingsStore.update(s)
        }
        .onChange(of: reasoningEffort) { _, newValue in
            var s = coordinator.settingsStore.current()
            guard s.reasoningEffort != newValue else { return }
            s.reasoningEffort = newValue
            coordinator.settingsStore.update(s)
        }
        .onReceive(NotificationCenter.default.publisher(for: .apiKeysChanged)) { _ in
            if hasOpenAIKey && openAIModels.isEmpty {
                Task { await loadOpenAIModels() }
            }
        }
    }

    private func loadOpenAIModels() async {
        guard hasOpenAIKey else { return }
        isLoadingModels = true
        modelError = nil
        defer { isLoadingModels = false }

        do {
            let service = OpenAIServiceFactory.service(apiKey: openaiAPIKey)
            let response = try await service.listModels()
            openAIModels = response.data
            // Validate current selection is still available
            if !filteredModels.contains(where: { $0.id == llmModelId }) {
                if let first = filteredModels.first {
                    llmModelId = first.id
                    var s = coordinator.settingsStore.current()
                    s.llmModelId = first.id
                    coordinator.settingsStore.update(s)
                }
            }
        } catch {
            modelError = error.localizedDescription
        }
    }

    // MARK: - Coaching Model Picker

    private var coachingModelPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let store = enabledLLMStore {
                let enabledModels = store.enabledModels.sorted { $0.displayName < $1.displayName }

                if enabledModels.isEmpty {
                    Text("No enabled models. Add models in LLM Settings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Coaching Model", selection: $coachingModelId) {
                        ForEach(enabledModels, id: \.modelId) { model in
                            Text(model.displayName).tag(model.modelId)
                        }
                    }
                    .pickerStyle(.menu)

                    Text("Model for daily coaching. Uses OpenRouter (different from Discovery which uses OpenAI direct).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("LLM store not available")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            // Auto-select first model if none selected
            if coachingModelId.isEmpty,
               let store = enabledLLMStore,
               let firstModel = store.enabledModels.sorted(by: { $0.displayName < $1.displayName }).first {
                coachingModelId = firstModel.modelId
            }
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
            Logger.info("✅ Job sources refreshed", category: .ai)
        } catch {
            sourceRefreshError = error.localizedDescription
            Logger.error("❌ Failed to refresh job sources: \(error)", category: .ai)
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
