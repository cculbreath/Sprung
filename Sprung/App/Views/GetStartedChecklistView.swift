//
//  GetStartedChecklistView.swift
//  Sprung
//
//  First-run "Get Started" checklist. Points a brand-new user at the core data
//  pipeline (Onboarding Interview → Knowledge Cards + Skill Bank → Experience
//  Defaults → template → first captured job → tailored resume). Each row derives
//  its done/not-done state from real store state and routes to the existing
//  surface via app-level notifications. Dismissable, and it stops showing once
//  the essentials exist.
//

import SwiftUI

/// Immutable snapshot of first-run progress across the four essential setup
/// steps. Kept separate from the view so the derivation is unit-testable.
struct GetStartedProgress: Equatable {
    var interviewDone: Bool = false
    var experienceDefaultsDone: Bool = false
    var templateInstalled: Bool = false
    var jobCaptured: Bool = false

    /// True once every essential step is satisfied — the checklist hides itself.
    var allComplete: Bool {
        interviewDone && experienceDefaultsDone && templateInstalled && jobCaptured
    }
}

extension GetStartedProgress {
    /// Derive progress from real store state. `templateInstalled` and
    /// `jobCaptured` are passed as flags because their sources (the template
    /// store surfaced via `AppEnvironment.requiresTemplateSetup`, and the
    /// `JobAppStore`) live outside the two lightweight stores this reads.
    @MainActor
    static func evaluate(
        knowledgeCardStore: KnowledgeCardStore,
        skillStore: SkillStore,
        experienceDefaultsStore: ExperienceDefaultsStore,
        templateInstalled: Bool,
        jobCaptured: Bool
    ) -> GetStartedProgress {
        GetStartedProgress(
            interviewDone: !knowledgeCardStore.knowledgeCards.isEmpty || !skillStore.skills.isEmpty,
            experienceDefaultsDone: experienceDefaultsStore.isSeedCreated,
            templateInstalled: templateInstalled,
            jobCaptured: jobCaptured
        )
    }
}

/// Small floating checklist that guides a new user through the essential setup
/// steps. Purely presentational — the caller supplies the derived `progress`
/// and the action closures that route to each existing surface.
struct GetStartedChecklistView: View {
    let progress: GetStartedProgress
    let onRunInterview: () -> Void
    let onOpenExperience: () -> Void
    let onOpenTemplateEditor: () -> Void
    let onCaptureJob: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            VStack(spacing: 0) {
                row(
                    done: progress.interviewDone,
                    title: "Run the Onboarding Interview",
                    subtitle: "Builds your Knowledge Cards and Skill Bank.",
                    actionLabel: "Start",
                    action: onRunInterview
                )
                row(
                    done: progress.experienceDefaultsDone,
                    title: "Set up Experience Defaults",
                    subtitle: "Your reusable, un-tailored resume baseline.",
                    actionLabel: "Open",
                    action: onOpenExperience
                )
                row(
                    done: progress.templateInstalled,
                    title: "Install a resume template",
                    subtitle: "Required to render a resume.",
                    actionLabel: "Open",
                    action: onOpenTemplateEditor
                )
                row(
                    done: progress.jobCaptured,
                    title: "Capture your first job",
                    subtitle: "Paste a posting to tailor against.",
                    actionLabel: "Add",
                    action: onCaptureJob
                )
            }
            .padding(.bottom, 6)
        }
        .frame(width: 360)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.separator.opacity(0.4))
        )
        .shadow(radius: 18, y: 8)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Get Started")
                    .font(.headline)
                Text("A few steps to your first tailored resume.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(12)
    }

    private func row(
        done: Bool,
        title: String,
        subtitle: String,
        actionLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(done ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .strikethrough(done, color: .secondary)
                    .foregroundStyle(done ? Color.secondary : Color.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !done {
                Button(actionLabel, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
