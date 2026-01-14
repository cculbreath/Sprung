import AppKit
import SwiftUI

/// A lightweight "wrap-up" screen shown when onboarding completes.
/// Keeps the interview window open long enough for the user to review key assets.
struct OnboardingCompletionReviewSheet: View {
    let coordinator: OnboardingInterviewCoordinator
    let onFinish: () -> Void

    @Environment(CoverRefStore.self) private var coverRefStore
    @Environment(ExperienceDefaultsStore.self) private var experienceDefaultsStore

    @State private var selectedTab: Tab = .summary

    enum Tab: String, CaseIterable, Identifiable {
        case summary = "Summary"
        case knowledgeCards = "Knowledge Cards"
        case skills = "Skills"
        case writingContext = "Writing Context"
        case experienceDefaults = "Experience"
        case nextSteps = "Next Steps"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .summary: return "checkmark.circle"
            case .knowledgeCards: return "brain.head.profile"
            case .skills: return "star.fill"
            case .writingContext: return "doc.text"
            case .experienceDefaults: return "person.text.rectangle"
            case .nextSteps: return "arrow.right.circle"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 900, minHeight: 620)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Onboarding Complete")
                    .font(.title2.weight(.semibold))
                Text("Review your assets before closing the interview.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Finish") {
                onFinish()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var content: some View {
        VStack(spacing: 0) {
            // Tab bar with icons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Tab.allCases) { tab in
                        tabButton(tab)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 12)

            Divider()

            // Tab content
            Group {
                switch selectedTab {
                case .summary:
                    summaryTab
                case .knowledgeCards:
                    knowledgeCardsTab
                case .skills:
                    skillsTab
                case .writingContext:
                    writingContextTab
                case .experienceDefaults:
                    experienceDefaultsTab
                case .nextSteps:
                    nextStepsTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func tabButton(_ tab: Tab) -> some View {
        let isSelected = selectedTab == tab
        let count = countFor(tab)

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.caption)
                Text(tab.rawValue)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                if let count = count, count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(isSelected ? Color.white.opacity(0.25) : Color.secondary.opacity(0.15))
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func countFor(_ tab: Tab) -> Int? {
        switch tab {
        case .summary, .nextSteps:
            return nil
        case .knowledgeCards:
            return coordinator.allKnowledgeCards.count
        case .skills:
            return coordinator.skillStore.approvedSkills.count
        case .writingContext:
            return coverRefStore.storedCoverRefs.count
        case .experienceDefaults:
            let defaults = experienceDefaultsStore.currentDefaults()
            return defaults.work.count + defaults.education.count + defaults.projects.count
        }
    }

    // MARK: - Summary Tab

    private var summaryTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("What was created")
                    .font(.headline)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    summaryCard(
                        icon: "brain.head.profile",
                        title: "Knowledge Cards",
                        value: "\(coordinator.allKnowledgeCards.count)",
                        color: .purple
                    )
                    summaryCard(
                        icon: "star.fill",
                        title: "Skills",
                        value: "\(coordinator.skillStore.approvedSkills.count)",
                        color: .orange
                    )
                    summaryCard(
                        icon: "doc.text",
                        title: "Writing Sources",
                        value: "\(coverRefStore.storedCoverRefs.count)",
                        color: .blue
                    )

                    let defaults = experienceDefaultsStore.currentDefaults()
                    summaryCard(
                        icon: "briefcase",
                        title: "Work Entries",
                        value: "\(defaults.work.count)",
                        color: .green
                    )
                }

                // Primary CTA: Generate Experience Defaults
                VStack(spacing: 12) {
                    Text("Next Step")
                        .font(.headline)

                    Text("Generate professional descriptions for your work history, education, and projects using AI.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button {
                        NotificationCenter.default.post(name: .showSeedGeneration, object: nil)
                    } label: {
                        Label("Generate Experience Defaults", systemImage: "wand.and.stars")
                            .font(.headline)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .padding(.horizontal, 16)
                .background(Color.accentColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Text("Quick Actions")
                    .font(.headline)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 10) {
                    Button("Open Applicant Profile") {
                        Task { @MainActor in
                            NotificationCenter.default.post(name: .showApplicantProfile, object: nil)
                            _ = NSApp.sendAction(#selector(AppDelegate.showApplicantProfileWindow), to: nil, from: nil)
                        }
                    }
                    Button("Open Experience Editor") {
                        Task { @MainActor in
                            NotificationCenter.default.post(name: .showExperienceEditor, object: nil)
                            _ = NSApp.sendAction(#selector(AppDelegate.showExperienceEditorWindow), to: nil, from: nil)
                        }
                    }
                    Button("Browse Knowledge Cards") {
                        Task { @MainActor in
                            NotificationCenter.default.post(name: .toggleKnowledgeCards, object: nil)
                        }
                    }
                    Button("Browse Writing Context") {
                        Task { @MainActor in
                            NotificationCenter.default.post(name: .showWritingContextBrowser, object: nil)
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func summaryCard(icon: String, title: String, value: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title2.weight(.semibold).monospacedDigit())
            }

            Spacer()
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Knowledge Cards Tab

    private var knowledgeCardsTab: some View {
        CompletionKnowledgeCardsTab(coordinator: coordinator)
    }

    // MARK: - Skills Tab

    private var skillsTab: some View {
        SkillsBankBrowser(skillStore: coordinator.skillStore, llmFacade: coordinator.llmFacade)
    }

    // MARK: - Writing Context Tab

    private var writingContextTab: some View {
        WritingContextBrowserTab(coverRefStore: coverRefStore)
    }

    // MARK: - Experience Defaults Tab

    private var experienceDefaultsTab: some View {
        ExperienceDefaultsBrowserTab(store: experienceDefaultsStore)
    }

    // MARK: - Next Steps Tab

    private var nextStepsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Next steps")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 12) {
                    nextStepRow(
                        number: 1,
                        title: "Review your assets",
                        description: "Browse the tabs above to verify knowledge cards, skills, and writing context look correct."
                    )
                    nextStepRow(
                        number: 2,
                        title: "Edit your profile",
                        description: "Open Applicant Profile to update your name, email, phone, and other contact details."
                    )
                    nextStepRow(
                        number: 3,
                        title: "Create a job application",
                        description: "Start a new job application to generate a tailored resume and cover letter."
                    )
                    nextStepRow(
                        number: 4,
                        title: "Export and apply",
                        description: "Export your customized resume as PDF and submit your application."
                    )
                }

                Spacer()
            }
            .padding(20)
        }
    }

    private func nextStepRow(number: Int, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentColor))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
