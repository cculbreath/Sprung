//
//  OnboardingPhaseAdvanceDialog.swift
//  Sprung
//
//  Dialog for user approval when LLM requests phase advancement with incomplete objectives.
//  Implements the approval flow specified in next_phase_tool.md §4.
//
import SwiftUI
struct OnboardingPhaseAdvanceDialog: View {
    enum Decision: String, CaseIterable, Identifiable {
        case approved
        case denied
        case deniedWithFeedback
        var id: String { rawValue }
        var label: String {
            switch self {
            case .approved: return "Approve"
            case .denied: return "Deny"
            case .deniedWithFeedback: return "Deny & Tell"
            }
        }
        var systemImage: String {
            switch self {
            case .approved: return "checkmark.circle"
            case .denied: return "xmark.circle"
            case .deniedWithFeedback: return "exclamationmark.bubble"
            }
        }
    }
    let request: OnboardingPhaseAdvanceRequest
    let onSubmit: (Decision, String?) -> Void
    let onCancel: (() -> Void)?
    @State private var decision: Decision = .approved
    @State private var feedback: String = ""
    private var nextPhaseDisplayName: String {
        switch request.nextPhase {
        case .phase1CoreFacts:
            return "Phase 1: Core Facts"
        case .phase2DeepDive:
            return "Phase 2: Deep Dive"
        case .phase3WritingCorpus:
            return "Phase 3: Writing Corpus"
        case .complete:
            return "Complete"
        }
    }
    private var hasIncompleteObjectives: Bool {
        !request.missingObjectives.isEmpty
    }
    private var hasProposedOverrides: Bool {
        !request.proposedOverrides.isEmpty
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("Move to next phase?")
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            Divider()
            // Phase transition info
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Current Phase:")
                        .foregroundStyle(.secondary)
                    Text(currentPhaseDisplayName)
                        .fontWeight(.medium)
                }
                HStack {
                    Image(systemName: "arrow.down")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Spacer()
                }
                .padding(.leading, 8)
                HStack {
                    Text("Next Phase:")
                        .foregroundStyle(.secondary)
                    Text(nextPhaseDisplayName)
                        .fontWeight(.medium)
                        .foregroundStyle(.blue)
                }
            }
            .font(.callout)
            // Incomplete objectives warning
            if hasIncompleteObjectives {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Incomplete Objectives")
                            .font(.headline)
                            .foregroundStyle(.orange)
                    }
                    Text("The interviewer would like to proceed despite the following not being marked complete:")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(request.missingObjectives, id: \.self) { objective in
                            HStack(spacing: 8) {
                                Image(systemName: "circle")
                                    .font(.system(size: 6))
                                    .foregroundStyle(.orange)
                                Text(formatObjectiveName(objective))
                                    .font(.callout)
                            }
                            .padding(.leading, 8)
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.orange.opacity(0.1))
                )
            }
            if hasProposedOverrides {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "flag.fill")
                            .foregroundStyle(.blue)
                        Text("Proposed Overrides")
                            .font(.headline)
                            .foregroundStyle(.blue)
                    }
                    Text("The interviewer suggests bypassing the following objectives:")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(request.proposedOverrides, id: \.self) { objective in
                            HStack(spacing: 8) {
                                Image(systemName: "arrowshape.turn.up.right.circle")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.blue.opacity(0.7))
                                Text(formatObjectiveName(objective))
                                    .font(.callout)
                            }
                            .padding(.leading, 8)
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.blue.opacity(0.08))
                )
            }
            // Reason from LLM
            if let reason = request.reason, !reason.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "text.quote")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Interviewer's Reason:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    Text("\"\(reason)\"")
                        .font(.callout)
                        .italic()
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                }
            }
            Divider()
            // Decision prompt
            Text("Do you approve advancing to \(nextPhaseDisplayName)?")
                .font(.headline)
            // Decision picker
            Picker("Decision", selection: $decision) {
                ForEach(Decision.allCases) { option in
                    Label(option.label, systemImage: option.systemImage)
                        .tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 4)
            // Feedback field (conditional on Deny & Tell)
            if decision == .deniedWithFeedback {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Instructions for interviewer")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Tell the interviewer what to do next")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $feedback)
                        .font(.body)
                        .frame(minHeight: 100)
                        .padding(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            // Action buttons
            HStack(spacing: 12) {
                if let onCancel {
                    Button("Cancel", action: {
                        onCancel()
                    })
                    .keyboardShortcut(.cancelAction)
                }
                Spacer()
                Button(action: {
                    submitDecision()
                }, label: {
                    Label(
                        decision == .approved ? "Approve & Advance" : "Submit Decision",
                        systemImage: decision.systemImage
                    )
                })
                .buttonStyle(.borderedProminent)
                .tint(decision == .approved ? .blue : .gray)
                .keyboardShortcut(.defaultAction)
                .disabled(decision == .deniedWithFeedback && feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 540)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    // MARK: - Helpers
    private var currentPhaseDisplayName: String {
        switch request.currentPhase {
        case .phase1CoreFacts:
            return "Phase 1: Core Facts"
        case .phase2DeepDive:
            return "Phase 2: Deep Dive"
        case .phase3WritingCorpus:
            return "Phase 3: Writing Corpus"
        case .complete:
            return "Complete"
        }
    }
    private func formatObjectiveName(_ objective: String) -> String {
        objective
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
    private func submitDecision() {
        let feedbackText = decision == .deniedWithFeedback ? feedback.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        onSubmit(decision, feedbackText)
    }
}
