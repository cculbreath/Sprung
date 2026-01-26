//
//  DebugSettingsView.swift
//  Sprung
//
//
import SwiftUI
struct DebugSettingsView: View {
    @Environment(DebugSettingsStore.self) private var debugSettings
    @Environment(SkillStore.self) private var skillStore
    @Environment(JobAppStore.self) private var jobAppStore
    @State private var showClearSkillsConfirmation = false
    @State private var isReprocessing = false
    @State private var totalQueued = 0
    @State private var progressTimer: Timer?

    private var saveDebugPromptsBinding: Binding<Bool> {
        Binding(
            get: { debugSettings.saveDebugPrompts },
            set: { debugSettings.saveDebugPrompts = $0 }
        )
    }

    private var logLevelBinding: Binding<DebugSettingsStore.LogLevelSetting> {
        Binding(
            get: { debugSettings.logLevelSetting },
            set: { debugSettings.logLevelSetting = $0 }
        )
    }

    private var showDebugButtonBinding: Binding<Bool> {
        Binding(
            get: { debugSettings.showOnboardingDebugButton },
            set: { debugSettings.showOnboardingDebugButton = $0 }
        )
    }

    private var forceQueryUserExperienceToolBinding: Binding<Bool> {
        Binding(
            get: { debugSettings.forceQueryUserExperienceTool },
            set: { debugSettings.forceQueryUserExperienceTool = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Save debug files to Downloads", isOn: saveDebugPromptsBinding)
                .help("When enabled, key debug transcripts and payloads are written to ~/Downloads for later analysis.")

            Toggle("Show debug button in onboarding interview", isOn: showDebugButtonBinding)
                .help("When enabled, shows the ladybug button in the bottom-right corner of the onboarding interview window for viewing event logs.")

            Toggle("Force QueryUserExperienceTool in resume customization", isOn: forceQueryUserExperienceToolBinding)
                .help("When enabled, forces the LLM to use the QueryUserExperienceTool as its first response during round 2 of the customize resume workflow.")

            VStack(alignment: .leading, spacing: 8) {
                Picker("Log Level", selection: logLevelBinding) {
                    ForEach(DebugSettingsStore.LogLevelSetting.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
                .pickerStyle(.menu)
                Text("Controls diagnostic output verbosity. Debug files can include sensitive request payloads.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                Button("Clear Skills") {
                    showClearSkillsConfirmation = true
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(skillStore.skills.isEmpty)
                .alert("Clear all skills?", isPresented: $showClearSkillsConfirmation) {
                    Button("Clear Skills", role: .destructive) {
                        let skills = skillStore.skills
                        if !skills.isEmpty {
                            skillStore.deleteAll(skills)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This removes every skill from the local store, including onboarding and approved skills.")
                }

                Text("Deletes all skills from the local store.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Button {
                        rerunPreprocessingOnActiveApps()
                    } label: {
                        Text("Re-run Preprocessing")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isReprocessing || activeJobAppsCount == 0)

                    if isReprocessing {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("\(pendingCount) of \(totalQueued) remaining")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }

                Text("Re-runs skill matching and requirement extraction on \(activeJobAppsCount) active job applications. Runs 8 jobs in parallel.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .onDisappear {
                progressTimer?.invalidate()
            }
        }
    }

    /// Job apps not in terminal states (submitted, withdrawn, rejected, accepted)
    private var activeJobApps: [JobApp] {
        jobAppStore.jobApps.filter { app in
            app.status != .submitted && app.status != .withdrawn && app.status != .rejected && app.status != .accepted
        }
    }

    private var activeJobAppsCount: Int {
        activeJobApps.count
    }

    /// Count of active apps still waiting for preprocessing (extractedRequirements is nil)
    private var pendingCount: Int {
        activeJobApps.filter { $0.extractedRequirements == nil }.count
    }

    private func rerunPreprocessingOnActiveApps() {
        let apps = activeJobApps
        guard !apps.isEmpty else { return }

        // Clear existing data and queue for reprocessing
        totalQueued = apps.count
        isReprocessing = true

        for app in apps {
            jobAppStore.rerunPreprocessing(for: app)
        }

        // Start polling for completion
        startProgressTracking()
    }

    private func startProgressTracking() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] timer in
            Task { @MainActor in
                let remaining = pendingCount
                if remaining == 0 {
                    timer.invalidate()
                    progressTimer = nil
                    isReprocessing = false
                }
            }
        }
    }
}
