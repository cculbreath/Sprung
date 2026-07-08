//
//  WeeklyReviewView.swift
//  Sprung
//
//  Weekly review view for job search progress.
//  Shows goals progress, reflections, and insights for the week.
//

import SwiftUI

struct WeeklyReviewView: View {
    let coordinator: DiscoveryCoordinator

    @State private var reflectionText = ""
    @State private var winsText = ""
    @State private var challengesText = ""
    @State private var nextWeekFocusText = ""
    @State private var isGeneratingReflection = false
    @State private var reflectionError: String?
    @State private var showSaveConfirmation = false
    @State private var showTargetEditor = false
    @State private var editApplicationsTarget = 0
    @State private var editEventsTarget = 0
    @State private var editContactsTarget = 0

    private var currentGoal: WeeklyGoal? {
        coordinator.weeklyGoalStore.currentWeekGoal()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                headerSection

                Divider()

                // Goals Progress
                goalsProgressSection

                Divider()

                // Activity Summary
                activitySummarySection

                Divider()

                // Reflection
                reflectionSection

                // Actions
                actionButtonsSection
            }
            .padding()
        }
        .scrollEdgeEffect()
        .navigationTitle("")
        .alert("Review Saved", isPresented: $showSaveConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your weekly review has been saved.")
        }
        .onAppear { loadSavedNotes() }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Week of \(weekStartDate, style: .date)")
                .font(.title)
                .fontWeight(.bold)

            Text("Review your progress and plan for next week")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var weekStartDate: Date {
        let calendar = Calendar.current
        return calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        ) ?? Date()
    }

    // MARK: - Goals Progress

    private var goalsProgressSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("GOALS PROGRESS")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    beginEditingTargets()
                } label: {
                    Label("Edit Targets", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
                .popover(isPresented: $showTargetEditor, arrowEdge: .bottom) {
                    targetEditor
                }
            }

            if let goal = currentGoal {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    GoalProgressCard(
                        title: "Applications",
                        current: coordinator.weeklyGoalStore.applicationsSubmittedThisWeek(),
                        target: goal.applicationTarget,
                        icon: "doc.text",
                        color: .blue
                    )

                    GoalProgressCard(
                        title: "Events Attended",
                        current: goal.eventsAttendedActual,
                        target: goal.eventsAttendedTarget,
                        icon: "calendar",
                        color: .purple
                    )

                    GoalProgressCard(
                        title: "New Contacts",
                        current: goal.newContactsActual,
                        target: goal.newContactsTarget,
                        icon: "person.2",
                        color: .green
                    )
                }
            } else {
                Text("No goals set for this week")
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.windowBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
            }
        }
    }

    // MARK: - Target Editor

    /// Popover for editing the weekly targets. Saving writes the application
    /// and events targets through `SearchPreferences` — the source of truth
    /// new weeks are seeded from — and snapshots all three onto the current
    /// week's goal row so the change is visible immediately.
    private var targetEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Weekly Targets")
                .font(.headline)

            Stepper(value: $editApplicationsTarget, in: 1...20) {
                HStack {
                    Text("Applications")
                    Spacer()
                    Text("\(editApplicationsTarget)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Stepper(value: $editEventsTarget, in: 0...10) {
                HStack {
                    Text("Events")
                    Spacer()
                    Text("\(editEventsTarget)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Stepper(value: $editContactsTarget, in: 0...20) {
                HStack {
                    Text("New Contacts")
                    Spacer()
                    Text("\(editContactsTarget)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Text("Applies to this week and seeds every future week.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Save Targets") {
                    saveTargets()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 280)
    }

    private func beginEditingTargets() {
        let prefs = coordinator.preferencesStore.current()
        editApplicationsTarget = prefs.weeklyApplicationTarget
        editEventsTarget = prefs.weeklyNetworkingTarget
        editContactsTarget = coordinator.weeklyGoalStore.currentWeek().newContactsTarget
        showTargetEditor = true
    }

    private func saveTargets() {
        var prefs = coordinator.preferencesStore.current()
        prefs.weeklyApplicationTarget = editApplicationsTarget
        prefs.weeklyNetworkingTarget = editEventsTarget
        coordinator.preferencesStore.update(prefs)

        coordinator.weeklyGoalStore.applyTargetsToCurrentWeek(
            applications: editApplicationsTarget,
            events: editEventsTarget,
            contacts: editContactsTarget
        )
        showTargetEditor = false
    }

    // MARK: - Activity Summary

    private var activitySummarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ACTIVITY SUMMARY")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 24) {
                StatBlock(
                    label: "Tasks Completed",
                    value: "\(completedTasksThisWeek)",
                    icon: "checkmark.circle"
                )
            }
        }
    }

    private var completedTasksThisWeek: Int {
        coordinator.dailyTaskStore.completedThisWeek().count
    }

    // MARK: - Reflection

    private var reflectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("REFLECTION")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    Task { await generateReflection() }
                } label: {
                    if isGeneratingReflection {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Generate Reflection", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.tintedPill(tint: .indigo))
                .disabled(isGeneratingReflection)
            }

            if let reflectionError {
                Text(reflectionError)
                    .font(.caption)
                    .foregroundStyle(.statusFailed)
            }

            generatedReflectionCard

            VStack(alignment: .leading, spacing: 12) {
                ReflectionField(
                    title: "This Week's Wins",
                    placeholder: "What went well? What are you proud of?",
                    text: $winsText
                )

                ReflectionField(
                    title: "Challenges Faced",
                    placeholder: "What was difficult? What blocked progress?",
                    text: $challengesText
                )

                ReflectionField(
                    title: "Key Learnings",
                    placeholder: "What did you learn? Any insights?",
                    text: $reflectionText
                )

                ReflectionField(
                    title: "Next Week's Focus",
                    placeholder: "What will you prioritize next week?",
                    text: $nextWeekFocusText
                )
            }
        }
    }

    private var generatedReflectionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let goal = currentGoal, let reflection = goal.llmReflection, !reflection.isEmpty {
                Text(reflection)
                    .font(.body)

                if let generatedAt = goal.reflectionGeneratedAt {
                    Text("Generated \(generatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No reflection generated yet. Tap Generate Reflection for an AI-written summary of your week.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.windowBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }

    // MARK: - Actions

    private var actionButtonsSection: some View {
        HStack {
            Button("Reset Goals") {
                coordinator.weeklyGoalStore.resetCurrentWeek()
            }
            .buttonStyle(.bordered)

            Spacer()

            Button("Save Review") {
                saveReview()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.top)
    }

    // MARK: - Actions

    private func generateReflection() async {
        isGeneratingReflection = true
        reflectionError = nil
        defer { isGeneratingReflection = false }

        do {
            try await coordinator.generateWeeklyReflection()
        } catch {
            Logger.error("Failed to generate weekly reflection: \(error)", category: .ai)
            reflectionError = "Couldn't generate reflection — \(error.localizedDescription)"
        }
    }

    /// Load previously saved review notes back into the four fields so a
    /// revisit continues the review instead of starting blank. Skipped when
    /// the user has already typed something unsaved.
    private func loadSavedNotes() {
        guard winsText.isEmpty, challengesText.isEmpty,
              reflectionText.isEmpty, nextWeekFocusText.isEmpty,
              let saved = currentGoal?.userNotes else { return }

        let notes = ReflectionNotes(parsing: saved)
        winsText = notes.wins
        challengesText = notes.challenges
        reflectionText = notes.learnings
        nextWeekFocusText = notes.nextWeekFocus
    }

    private func saveReview() {
        let notes = ReflectionNotes(
            wins: winsText,
            challenges: challengesText,
            learnings: reflectionText,
            nextWeekFocus: nextWeekFocusText
        )

        // Blank saves are a no-op: never overwrite previously saved notes
        // with the empty template.
        if let composed = notes.composed {
            let goal = coordinator.weeklyGoalStore.currentWeek()
            goal.userNotes = composed
            coordinator.weeklyGoalStore.update(goal)
        }

        showSaveConfirmation = true
    }
}

// MARK: - Reflection Notes

/// The four Weekly Review reflection fields and their round-trip to the
/// labeled prose stored in `WeeklyGoal.userNotes` (read back by next week's
/// review, the weekly-reflection generation context, and the coaching
/// system prompt).
struct ReflectionNotes: Equatable {
    var wins = ""
    var challenges = ""
    var learnings = ""
    var nextWeekFocus = ""

    private static let fields: [(label: String, keyPath: WritableKeyPath<ReflectionNotes, String>)] = [
        ("Wins:", \.wins),
        ("Challenges:", \.challenges),
        ("Learnings:", \.learnings),
        ("Next Week:", \.nextWeekFocus)
    ]

    init(wins: String = "", challenges: String = "", learnings: String = "", nextWeekFocus: String = "") {
        self.wins = wins
        self.challenges = challenges
        self.learnings = learnings
        self.nextWeekFocus = nextWeekFocus
    }

    /// Parse notes previously produced by `composed` back into the fields.
    /// Lines that don't start a new labeled field continue the current one.
    init(parsing text: String) {
        var current: WritableKeyPath<ReflectionNotes, String>?
        for line in text.components(separatedBy: "\n") {
            if let field = Self.fields.first(where: { line.hasPrefix($0.label) }) {
                current = field.keyPath
                self[keyPath: field.keyPath] = String(line.dropFirst(field.label.count))
                    .trimmingCharacters(in: .whitespaces)
            } else if let current {
                let existing = self[keyPath: current]
                self[keyPath: current] = existing.isEmpty ? line : existing + "\n" + line
            }
        }
        for field in Self.fields {
            self[keyPath: field.keyPath] = self[keyPath: field.keyPath]
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// The labeled prose form stored in `WeeklyGoal.userNotes`, or nil when
    /// every field is blank — the caller's guard against wiping saved notes
    /// with an accidental empty save.
    var composed: String? {
        let values = [wins, challenges, learnings, nextWeekFocus]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard values.contains(where: { !$0.isEmpty }) else { return nil }
        return """
        Wins: \(values[0])
        Challenges: \(values[1])
        Learnings: \(values[2])
        Next Week: \(values[3])
        """
    }
}

// MARK: - Supporting Views

struct GoalProgressCard: View {
    let title: String
    let current: Int
    let target: Int
    let icon: String
    let color: Color

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(Double(current) / Double(target), 1.0)
    }

    private var isComplete: Bool {
        current >= target && target > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                if isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.statusSuccess)
                }
            }

            Text("\(current) / \(target)")
                .font(.title2)
                .fontWeight(.bold)

            ProgressView(value: progress)
                .tint(isComplete ? .statusSuccess : color)
        }
        .padding()
        .background(Color(.windowBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}

struct StatBlock: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title3)
                .fontWeight(.semibold)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.windowBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}

struct ReflectionField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)

            TextEditor(text: $text)
                .frame(minHeight: 60, maxHeight: 100)
                .font(.body)
                .padding(8)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
                .overlay {
                    if text.isEmpty {
                        Text(placeholder)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 12)
                            .padding(.top, 16)
                            .allowsHitTesting(false)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
        }
    }
}
