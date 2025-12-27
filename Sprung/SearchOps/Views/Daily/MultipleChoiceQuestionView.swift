//
//  MultipleChoiceQuestionView.swift
//  Sprung
//
//  View for displaying coaching multiple choice questions.
//

import SwiftUI

struct MultipleChoiceQuestionView: View {
    let question: CoachingQuestion
    let questionNumber: Int
    let totalQuestions: Int
    let onSubmit: (Int, String) -> Void

    @State private var selectedOption: QuestionOption?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Progress indicator
            HStack {
                Text("Question \(questionNumber) of \(totalQuestions)+")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(question.questionType.displayName)
                    .font(.caption)
                    .foregroundStyle(.indigo)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.indigo.opacity(0.1))
                    .clipShape(Capsule())
            }

            // Question text
            Text(question.questionText)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

            // Options
            VStack(spacing: 8) {
                ForEach(question.options) { option in
                    OptionButton(
                        option: option,
                        isSelected: selectedOption?.id == option.id,
                        onSelect: { selectedOption = option }
                    )
                }
            }

            // Continue button
            if let selected = selectedOption {
                Button {
                    onSubmit(selected.value, selected.label)
                } label: {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .padding(.top, 8)
            }
        }
    }
}

struct OptionButton: View {
    let option: QuestionOption
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Emoji if present
                if let emoji = option.emoji {
                    Text(emoji)
                        .font(.title3)
                }

                // Label
                Text(option.label)
                    .font(.body)
                    .foregroundStyle(.primary)

                Spacer()

                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .indigo : .secondary)
                    .font(.title3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isSelected ? Color.indigo.opacity(0.1) : Color(.windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.indigo : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
