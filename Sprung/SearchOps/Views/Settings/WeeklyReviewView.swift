//
//  WeeklyReviewView.swift
//  Sprung
//
//  Weekly review view for job search progress.
//  Shows goals progress, reflections, and insights for the week.
//

import SwiftUI

struct WeeklyReviewView: View {
    let coordinator: SearchOpsCoordinator

    @State private var reflectionText = ""
    @State private var winsText = ""
    @State private var challengesText = ""
    @State private var nextWeekFocusText = ""
    @State private var isGeneratingReflection = false
    @State private var showSaveConfirmation = false

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
        .navigationTitle("Weekly Review")
        .alert("Review Saved", isPresented: $showSaveConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your weekly review has been saved.")
        }
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
            Text("GOALS PROGRESS")
                .font(.headline)
                .foregroundStyle(.secondary)

            if let goal = currentGoal {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    GoalProgressCard(
                        title: "Applications",
                        current: goal.applicationsSubmitted,
                        target: goal.applicationsTarget,
                        icon: "doc.text",
                        color: .blue
                    )

                    GoalProgressCard(
                        title: "Events Attended",
                        current: goal.eventsAttended,
                        target: goal.eventsTarget,
                        icon: "calendar",
                        color: .purple
                    )

                    GoalProgressCard(
                        title: "New Contacts",
                        current: goal.newContacts,
                        target: goal.newContactsTarget,
                        icon: "person.2",
                        color: .green
                    )

                    GoalProgressCard(
                        title: "Follow-ups Sent",
                        current: goal.followUpsSent,
                        target: goal.followUpsTarget,
                        icon: "envelope",
                        color: .orange
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

    // MARK: - Activity Summary

    private var activitySummarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ACTIVITY SUMMARY")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 24) {
                StatBlock(
                    label: "Time Invested",
                    value: formattedTimeInvested,
                    icon: "clock"
                )

                StatBlock(
                    label: "Tasks Completed",
                    value: "\(completedTasksThisWeek)",
                    icon: "checkmark.circle"
                )

                StatBlock(
                    label: "Sources Checked",
                    value: "\(sourcesCheckedThisWeek)",
                    icon: "link"
                )
            }
        }
    }

    private var formattedTimeInvested: String {
        let minutes = coordinator.timeEntryStore.totalMinutesThisWeek
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }

    private var completedTasksThisWeek: Int {
        coordinator.dailyTaskStore.completedThisWeek().count
    }

    private var sourcesCheckedThisWeek: Int {
        coordinator.jobSourceStore.checkedThisWeek().count
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
                        Label("Generate Insights", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isGeneratingReflection)
            }

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
        defer { isGeneratingReflection = false }

        // Generate insights based on the week's data
        let insights = buildWeeklyInsights()
        reflectionText = insights
    }

    private func buildWeeklyInsights() -> String {
        var insights: [String] = []

        if let goal = currentGoal {
            if goal.applicationsSubmitted >= goal.applicationsTarget {
                insights.append("Met application target - great consistency!")
            } else if goal.applicationsSubmitted > 0 {
                insights.append("Made progress on applications but didn't hit target.")
            }

            if goal.eventsAttended >= goal.eventsTarget {
                insights.append("Networking goal achieved!")
            }

            if goal.newContacts >= goal.newContactsTarget {
                insights.append("Expanded professional network as planned.")
            }
        }

        let timeMinutes = coordinator.timeEntryStore.totalMinutesThisWeek
        if timeMinutes >= 600 { // 10+ hours
            insights.append("Invested significant time in job search.")
        } else if timeMinutes >= 300 { // 5+ hours
            insights.append("Maintained consistent effort on job search.")
        }

        return insights.joined(separator: "\n")
    }

    private func saveReview() {
        // Save reflection to current goal
        if let goal = currentGoal {
            goal.reflectionNotes = """
            Wins: \(winsText)
            Challenges: \(challengesText)
            Learnings: \(reflectionText)
            Next Week: \(nextWeekFocusText)
            """
            coordinator.weeklyGoalStore.update(goal)
        }

        showSaveConfirmation = true
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
                        .foregroundStyle(.green)
                }
            }

            Text("\(current) / \(target)")
                .font(.title2)
                .fontWeight(.bold)

            ProgressView(value: progress)
                .tint(isComplete ? .green : color)
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
