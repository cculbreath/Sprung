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
    @FocusState private var focusedQuestionId: String?
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
                    ForEach(Array(questions.enumerated()), id: \.element.id) { index, question in
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
                            ),
                            isFocused: focusedQuestionId == question.id,
                            onTabPressed: {
                                // Move to next question
                                if index < questions.count - 1 {
                                    focusedQuestionId = questions[index + 1].id
                                } else {
                                    // If last question, move focus to submit button
                                    focusedQuestionId = nil
                                }
                            },
                            onShiftTabPressed: {
                                // Move to previous question
                                if index > 0 {
                                    focusedQuestionId = questions[index - 1].id
                                }
                            }
                        )
                        .focused($focusedQuestionId, equals: question.id)
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
        .onAppear {
            // Focus the first question when the sheet appears
            if let firstQuestion = questions.first {
                focusedQuestionId = firstQuestion.id
            }
        }
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
    let isFocused: Bool
    let onTabPressed: () -> Void
    let onShiftTabPressed: () -> Void
    
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
                TabNavigableTextEditor(
                    text: $answer,
                    onTabPressed: onTabPressed,
                    onShiftTabPressed: onShiftTabPressed
                )
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

// Custom TextEditor that handles Tab navigation
struct TabNavigableTextEditor: NSViewRepresentable {
    @Binding var text: String
    let onTabPressed: () -> Void
    let onShiftTabPressed: () -> Void
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.string = text
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.allowsUndo = true
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as! NSTextView
        if textView.string != text {
            textView.string = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TabNavigableTextEditor
        
        init(_ parent: TabNavigableTextEditor) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
        
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSStandardKeyBindingResponding.insertTab(_:)) {
                parent.onTabPressed()
                return true
            } else if commandSelector == #selector(NSStandardKeyBindingResponding.insertBacktab(_:)) {
                parent.onShiftTabPressed()
                return true
            }
            return false
        }
    }
}