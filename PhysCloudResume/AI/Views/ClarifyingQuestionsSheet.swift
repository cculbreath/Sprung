//
//  ClarifyingQuestionsSheet.swift
//  PhysCloudResume
//
//  Created by Claude on 5/23/25.
//

import SwiftUI

struct ClarifyingQuestionsSheet: View {
    let questions: [ClarifyingQuestion]
    @Binding var isPresented: Bool
    let onSubmit: ([QuestionAnswer]) -> Void
    
    @State private var answers: [String: String] = [:]
    @State private var declinedQuestions: Set<String> = []
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "questionmark.bubble")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                    .symbolRenderingMode(.hierarchical)
                
                Text("Clarifying Questions")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("The AI has some questions to help create better resume modifications")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top)
            
            // Questions
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(questions) { question in
                        QuestionView(
                            question: question,
                            answer: Binding(
                                get: { answers[question.id] ?? "" },
                                set: { answers[question.id] = $0 }
                            ),
                            isDeclined: Binding(
                                get: { declinedQuestions.contains(question.id) },
                                set: { isDeclined in
                                    if isDeclined {
                                        declinedQuestions.insert(question.id)
                                        answers[question.id] = ""
                                    } else {
                                        declinedQuestions.remove(question.id)
                                    }
                                }
                            )
                        )
                    }
                }
                .padding()
            }
            
            // Buttons
            HStack(spacing: 16) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Submit Answers") {
                    submitAnswers()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!isValidToSubmit)
            }
            .padding()
        }
        .frame(minWidth: 600, idealWidth: 700, minHeight: 400)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var isValidToSubmit: Bool {
        // At least one question must be answered (not declined)
        questions.contains { question in
            !declinedQuestions.contains(question.id) && !(answers[question.id] ?? "").isEmpty
        }
    }
    
    private func submitAnswers() {
        let questionAnswers = questions.map { question in
            QuestionAnswer(
                questionId: question.id,
                answer: declinedQuestions.contains(question.id) ? nil : answers[question.id]
            )
        }
        
        onSubmit(questionAnswers)
        dismiss()
    }
}

struct QuestionView: View {
    let question: ClarifyingQuestion
    @Binding var answer: String
    @Binding var isDeclined: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Question header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(question.question)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    if let context = question.context {
                        Text(context)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                Spacer()
                
                Toggle("Decline", isOn: $isDeclined)
                    .toggleStyle(.checkbox)
                    .help("Check to skip this question")
            }
            
            // Answer field
            if !isDeclined {
                TextEditor(text: $answer)
                    .font(.body)
                    .frame(minHeight: 80, maxHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    .disabled(isDeclined)
            } else {
                Text("Question declined")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .italic()
                    .frame(minHeight: 40)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .padding()
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(8)
    }
}

// Preview
struct ClarifyingQuestionsSheet_Previews: PreviewProvider {
    static var previews: some View {
        ClarifyingQuestionsSheet(
            questions: [
                ClarifyingQuestion(
                    id: "q1",
                    question: "What specific technologies or frameworks did you use in your shape memory alloy research?",
                    context: "This will help tailor your technical skills section"
                ),
                ClarifyingQuestion(
                    id: "q2",
                    question: "Can you describe a specific achievement or metric from your automation work?",
                    context: nil
                )
            ],
            isPresented: .constant(true),
            onSubmit: { _ in }
        )
    }
}