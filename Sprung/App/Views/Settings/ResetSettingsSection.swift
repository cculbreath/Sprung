//
//  ResetSettingsSection.swift
//  Sprung
//
//
import SwiftUI
import SwiftData

struct ResetSettingsSection: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ExperienceDefaultsStore.self) private var experienceDefaultsStore
    @Environment(InferenceGuidanceStore.self) private var inferenceGuidanceStore
    @State private var showFactoryResetConfirmation = false
    @State private var showFinalResetConfirmation = false
    @State private var showClearArtifactsConfirmation = false
    @State private var showClearKnowledgeCardsConfirmation = false
    @State private var showClearWritingSamplesConfirmation = false
    @State private var showClearSGMContentConfirmation = false
    @State private var clearResultMessage: String?
    @State private var resetError: String?
    @State private var isResetting = false

    private let dataResetService = DataResetService()

    var body: some View {
        Form {
            Section {
                granularClearingSection
                Divider()
                    .padding(.vertical, 8)
                factoryResetSection
            } header: {
                SettingsSectionHeader(title: "Data Management", systemImage: "arrow.counterclockwise")
            }
        }
        .formStyle(.grouped)
        .alert("Factory Reset", isPresented: $showFactoryResetConfirmation) {
            Button("Cancel", role: .cancel) {
                showFactoryResetConfirmation = false
            }
            Button("Continue", role: .destructive) {
                showFinalResetConfirmation = true
            }
        } message: {
            Text("This will permanently delete all resumes, cover letters, job applications, user profile data, and settings. This action cannot be undone.")
        }
        .alert("Confirm Factory Reset", isPresented: $showFinalResetConfirmation) {
            Button("Cancel", role: .cancel) {
                showFinalResetConfirmation = false
            }
            Button("Reset Everything", role: .destructive) {
                Task {
                    await performReset()
                }
            }
        } message: {
            Text("This is your final chance to cancel. Once confirmed, all data will be deleted and the app will restart.")
        }
        .alert("Clear Artifact Records", isPresented: $showClearArtifactsConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                clearArtifactRecords()
            }
        } message: {
            Text("This will delete all uploaded documents and their extracted content. This cannot be undone.")
        }
        .alert("Clear Knowledge Cards", isPresented: $showClearKnowledgeCardsConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                clearKnowledgeCards()
            }
        } message: {
            Text("This will delete all knowledge cards generated during onboarding. This cannot be undone.")
        }
        .alert("Clear Writing Samples", isPresented: $showClearWritingSamplesConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                clearWritingSamples()
            }
        } message: {
            Text("This will delete all writing samples used for cover letter generation. This cannot be undone.")
        }
        .alert("Reset Generated Content", isPresented: $showClearSGMContentConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                clearSGMContent()
            }
        } message: {
            Text("This will clear all AI-generated resume content (summaries, highlights, skill groupings, job titles, objective) while preserving timeline facts (names, dates, locations). You can then re-run Seed Generation.")
        }
    }

    private var granularClearingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Clear specific data types without a full reset:")
                .font(.callout)

            HStack(spacing: 12) {
                Button(role: .destructive) {
                    showClearArtifactsConfirmation = true
                } label: {
                    Label("Clear Artifacts", systemImage: "doc.badge.ellipsis")
                }
                .buttonStyle(.bordered)
                .disabled(isResetting)

                Button(role: .destructive) {
                    showClearKnowledgeCardsConfirmation = true
                } label: {
                    Label("Clear Knowledge Cards", systemImage: "rectangle.stack.badge.minus")
                }
                .buttonStyle(.bordered)
                .disabled(isResetting)

                Button(role: .destructive) {
                    showClearWritingSamplesConfirmation = true
                } label: {
                    Label("Clear Writing Samples", systemImage: "text.badge.minus")
                }
                .buttonStyle(.bordered)
                .disabled(isResetting)

                Button(role: .destructive) {
                    showClearSGMContentConfirmation = true
                } label: {
                    Label("Reset Generated Content", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                .disabled(isResetting)
            }

            if let message = clearResultMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var factoryResetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Factory reset will permanently delete all your data:")
                .font(.callout)
            VStack(alignment: .leading, spacing: 6) {
                Label("Resumes, cover letters, and templates", systemImage: "doc.fill")
                Label("Job application records", systemImage: "briefcase.fill")
                Label("Interview data and artifacts", systemImage: "wand.and.stars.inverse")
                Label("User profile information", systemImage: "person.fill")
                Label("All settings and preferences", systemImage: "gear")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Button(role: .destructive) {
                showFactoryResetConfirmation = true
            } label: {
                Label("Factory Reset", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            .disabled(isResetting)

            if let error = resetError, !error.isEmpty {
                Text("Error: \(error)")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private func performReset() async {
        isResetting = true
        defer { isResetting = false }
        do {
            try await dataResetService.performFactoryReset()
            resetError = ""
            try await Task.sleep(nanoseconds: 500_000_000)
            NSApplication.shared.terminate(nil)
        } catch {
            resetError = error.localizedDescription
        }
    }

    private func clearArtifactRecords() {
        do {
            let count = try dataResetService.clearArtifactRecords(context: modelContext)
            clearResultMessage = "Cleared \(count) artifact record\(count == 1 ? "" : "s")"
        } catch {
            clearResultMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func clearKnowledgeCards() {
        do {
            let count = try dataResetService.clearKnowledgeCards()
            clearResultMessage = "Cleared \(count) knowledge card file\(count == 1 ? "" : "s")"
        } catch {
            clearResultMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func clearWritingSamples() {
        do {
            let count = try dataResetService.clearWritingSamples(context: modelContext)
            clearResultMessage = "Cleared \(count) writing sample\(count == 1 ? "" : "s")"
        } catch {
            clearResultMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func clearSGMContent() {
        // Clear generated content from ExperienceDefaults (summaries, highlights, skills)
        experienceDefaultsStore.clearGeneratedContent()

        // Clear auto-generated inference guidance (title sets, objective)
        inferenceGuidanceStore.deleteAutoGenerated()

        clearResultMessage = "Reset generated content. You can now re-run Seed Generation."
    }
}
