//
//  CoachingSectionView.swift
//  Sprung
//
//  Main coaching section view for the DailyView.
//  Displays coaching questions, recommendations, or get coaching button.
//

import SwiftUI

struct CoachingSectionView: View {
    let coordinator: SearchOpsCoordinator

    @State private var isProcessing = false

    private var coachingService: CoachingService? {
        coordinator.coachingService
    }

    private func markdownAttributedString(_ string: String) -> AttributedString {
        (try? AttributedString(markdown: string, options: .init(interpretedSyntax: .full))) ?? AttributedString(string)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "figure.mind.and.body")
                    .font(.largeTitle)
                Text("Career Coach")
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.indigo)

            // Content based on state
            if let service = coachingService {
                coachingContent(service: service)
            } else {
                unavailableContent
            }
        }
        .padding()
        .background(Color.indigo.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func coachingContent(service: CoachingService) -> some View {
        switch service.state {
        case .idle:
            if let session = service.todaysSession, session.isComplete {
                TodaysRecommendationsView(
                    session: session,
                    onRegenerate: {
                        Task {
                            isProcessing = true
                            defer { isProcessing = false }
                            try? await service.regenerateRecommendations()
                        }
                    }
                )
            } else {
                GetCoachingButton(
                    isProcessing: isProcessing,
                    onStart: {
                        Task {
                            isProcessing = true
                            defer { isProcessing = false }
                            try? await service.startSession()
                        }
                    }
                )
            }

        case .generatingReport:
            AnimatedThinkingText(statusMessage: "Analyzing your activity...")

        case .askingQuestion(let question, let index, let total):
            MultipleChoiceQuestionView(
                question: question,
                questionNumber: index,
                totalQuestions: total,
                onSubmit: { value, label in
                    Task {
                        try? await service.submitAnswer(value: value, label: label)
                    }
                }
            )

        case .waitingForAnswer:
            AnimatedThinkingText(statusMessage: "Thinking...")

        case .generatingRecommendations:
            AnimatedThinkingText(statusMessage: "Preparing your coaching...")

        case .showingRecommendations(let recommendations):
            VStack(alignment: .leading, spacing: 12) {
                // Show recommendations while loading follow-up
                Text(markdownAttributedString(recommendations))
                    .font(.body)
                    .lineSpacing(4)
                    .textSelection(.enabled)

                AnimatedThinkingText(statusMessage: "Preparing follow-up options...")
            }

        case .askingFollowUp(let question):
            VStack(alignment: .leading, spacing: 12) {
                // Show recommendations
                if let session = service.currentSession {
                    Text(markdownAttributedString(session.recommendations))
                        .font(.body)
                        .lineSpacing(4)
                        .textSelection(.enabled)

                    Divider()
                }

                // Show follow-up question
                MultipleChoiceQuestionView(
                    question: question,
                    questionNumber: nil,
                    totalQuestions: nil,
                    onSubmit: { value, label in
                        Task {
                            try? await service.submitFollowUpAnswer(value: value, label: label)
                        }
                    }
                )
            }

        case .executingFollowUp(let action):
            VStack(alignment: .leading, spacing: 12) {
                if let session = service.currentSession {
                    Text(markdownAttributedString(session.recommendations))
                        .font(.body)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                }

                AnimatedThinkingText(statusMessage: "Executing: \(action.displayName)...")
            }

        case .complete(let sessionId):
            if let session = coordinator.coachingSessionStore?.session(byId: sessionId) {
                TodaysRecommendationsView(
                    session: session,
                    onRegenerate: {
                        Task {
                            isProcessing = true
                            defer { isProcessing = false }
                            try? await service.regenerateRecommendations()
                        }
                    }
                )
            }

        case .error(let message):
            ErrorStateView(
                message: message,
                onRetry: {
                    Task {
                        try? await service.startSession()
                    }
                }
            )
        }
    }

    private var unavailableContent: some View {
        Text("Coaching service is not available. Please configure LLM settings.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Supporting Views

struct GetCoachingButton: View {
    let isProcessing: Bool
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Get personalized coaching based on your recent activity and goals.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button(action: onStart) {
                HStack {
                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text("Get Today's Coaching")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .disabled(isProcessing)
        }
    }
}

struct TodaysRecommendationsView: View {
    let session: CoachingSession
    let onRegenerate: () -> Void

    @State private var isExpanded = true

    private func markdownAttributedString(_ string: String) -> AttributedString {
        (try? AttributedString(markdown: string, options: .init(interpretedSyntax: .full))) ?? AttributedString(string)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Q&A Summary (collapsed by default)
            if !session.answers.isEmpty {
                DisclosureGroup("Your Responses", isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(session.answers.indices, id: \.self) { index in
                            let answer = session.answers[index]
                            if let question = session.questions.first(where: { $0.id == answer.questionId }) {
                                HStack(alignment: .top) {
                                    Text(question.questionType.displayName + ":")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(answer.selectedLabel)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.subheadline)
            }

            // Recommendations (render markdown with paragraph spacing)
            Text(markdownAttributedString(session.recommendations))
                .font(.body)
                .lineSpacing(4)
                .textSelection(.enabled)

            // Footer with regenerate button
            HStack {
                if let model = session.llmModel {
                    Text("via \(model)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Button(action: onRegenerate) {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

struct ErrorStateView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button(action: onRetry) {
                Label("Try Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }
}
