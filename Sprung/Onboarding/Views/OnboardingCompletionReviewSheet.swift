import AppKit
import SwiftUI

/// A lightweight “wrap-up” screen shown when onboarding completes.
/// Keeps the interview window open long enough for the user to review key assets.
struct OnboardingCompletionReviewSheet: View {
    let coordinator: OnboardingInterviewCoordinator
    let onFinish: () -> Void

    @State private var selectedTab: Tab = .summary

    enum Tab: String, CaseIterable, Identifiable {
        case summary = "Summary"
        case nextSteps = "Next Steps"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 860, minHeight: 560)
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
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            Group {
                switch selectedTab {
                case .summary:
                    summaryTab
                case .nextSteps:
                    nextStepsTab
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var summaryTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What was created")
                .font(.headline)

            let knowledgeCardCount = coordinator.allKnowledgeCards.count

            VStack(alignment: .leading, spacing: 10) {
                summaryRow(title: "Knowledge Cards", value: "\(knowledgeCardCount)")
                summaryRow(title: "Writing Context", value: "Dossier + writing samples")
            }

            Text("Open and review")
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
                Button("Browse Writing Context (Dossier & Samples)") {
                    Task { @MainActor in
                        NotificationCenter.default.post(name: .showWritingContextBrowser, object: nil)
                    }
                }
            }

            Spacer()

            Text("If you want changes, leave the interview open and tell me what to adjust; we’ll add editing tools in this review flow next.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var nextStepsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Next steps")
                .font(.headline)

            Text("1. Review and edit any assets (profile, experience defaults, cards, writing context).")
            Text("2. Generate a cover letter and pick sources from Writing Context.")
            Text("3. Customize a resume for a target job and export.")

            Spacer()

            Text("This screen is a first pass to avoid abrupt endings; we can expand it into a tabbed, per-asset feedback workflow.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func summaryRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
