// Sprung/AI/Views/ResumeReviewSheet.swift
import PDFKit // Required for PDFDocument access if not already imported
import SwiftUI
import WebKit // Required for WKWebView used in MarkdownView
import Foundation
// Make sure we're using the right MarkdownView component
struct ResumeReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedResume: Resume?
    @State private var viewModel = ResumeReviewViewModel()
    @Environment(LLMFacade.self) private var llmFacade
    @Environment(KnowledgeCardStore.self) private var knowledgeCardStore
    @State private var selectedReviewType: ResumeReviewType = .assessQuality
    @State private var customOptions = CustomReviewOptions()
    // Model selection state with persistence
    @AppStorage("resumeReviewSelectedModel") private var selectedModel: String = ""
    // Computed property for the content view (remains the same)
    private var contentView: some View {
        Group {
            if viewModel.isProcessing {
                VStack(spacing: 16) {
                    Spacer()
                    ProgressView()
                    Text(viewModel.reviewResponseText.isEmpty || viewModel.reviewResponseText == "Submitting request..." ? "Analyzing resume..." : viewModel.reviewResponseText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !viewModel.reviewResponseText.isEmpty {
                MarkdownView(markdown: viewModel.reviewResponseText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
            } else if let error = viewModel.reviewError {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            } else {
                Text("Select a review type and submit your request.")
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
    }
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) { // Use spacing 0 for the outer VStack to control padding precisely
                // Header
                Text("AI Resume Review")
                    .font(.title)
                    .padding([.horizontal, .top]) // Add padding to header
                    .padding(.bottom, 8)
                // Scrollable content area
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Review type selection
                        Picker("Review Type", selection: $selectedReviewType) {
                            ForEach(ResumeReviewType.allCases) { type in
                                Text(type.rawValue).tag(type)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: selectedReviewType) { _, _ in
                            viewModel.resetOnReviewTypeChange()
                        }
                        // Custom options if custom type is selected
                        if selectedReviewType == .custom {
                            CustomReviewOptionsView(customOptions: $customOptions)
                        }
                        // AI Model Selection
                        DropdownModelPicker(
                            selectedModel: $selectedModel,
                            requiredCapability: nil,
                            title: "AI Model"
                        )
                        // Content area (GroupBox with contentView)
                        GroupBox(label: Text("AI Analysis").fontWeight(.medium)) {
                            contentView // This already handles its internal scrolling for MarkdownView
                                .frame(minHeight: 200, idealHeight: 280, maxHeight: 320) // Constrained max height for better layout
                        }
                        // Saved-review caption: shows when the displayed markdown is the
                        // last persisted review for this resume, with a clear run-again hint.
                        if !viewModel.isProcessing,
                           !viewModel.reviewResponseText.isEmpty,
                           let savedDate = viewModel.savedReviewDate {
                            Text(savedReviewCaption(date: savedDate, type: viewModel.savedReviewType))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal) // Padding for the scrollable content
                    .padding(.bottom) // Padding at the bottom of scrollable content
                } // End ScrollView
                // Button row - Pinned to the bottom
                HStack {
                    if viewModel.isProcessing {
                        Button("Stop") {
                            viewModel.cancelRequest()
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                        Button("Close") {
                            dismiss()
                        }
                    } else {
                        Button("Submit Request") {
                            handleSubmit()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedResume == nil)
                        Spacer()
                        Button("Close") {
                            dismiss()
                        }
                    }
                }
                .padding([.horizontal, .bottom]) // Padding for the button bar
                .padding(.top, 8) // Add some space above the button bar
                .background(Color(NSColor.windowBackgroundColor).opacity(0.8)) // Optional: background for button bar
            }
            // Note: Reasoning stream view is now displayed globally in the main app UI
        }
        .frame(width: 650, height: 600, alignment: .topLeading) // Increased sheet size for better content fit
        .onAppear {
            viewModel.initialize(llmFacade: llmFacade)
            if let resume = selectedResume {
                viewModel.loadStoredReview(from: resume)
            }
        }
    }

    /// Caption shown under the analysis box when a persisted review is displayed.
    private func savedReviewCaption(date: Date, type: String?) -> String {
        let stamp = date.formatted(date: .abbreviated, time: .shortened)
        let typeSuffix = type.map { " · \($0)" } ?? ""
        return "Saved \(stamp)\(typeSuffix) — Submit to run a fresh review."
    }
    // View for custom options (extracted for clarity) - Unchanged
    struct CustomReviewOptionsView: View {
        @Binding var customOptions: CustomReviewOptions
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("Custom Review Options")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Include Job Listing", isOn: $customOptions.includeJobListing)
                    Toggle("Include Resume Text", isOn: $customOptions.includeResumeText)
                    Toggle("Include Resume Image", isOn: $customOptions.includeResumeImage)
                }
                Text("Custom Prompt")
                    .font(.headline)
                    .padding(.top, 4)
                TextEditor(text: $customOptions.customPrompt)
                    .font(.body)
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .frame(minHeight: 100) // This TextEditor can grow
            }
            .padding(.vertical, 8)
        }
    }
    func handleSubmit() {
        guard let resume = selectedResume else { return }
        viewModel.handleSubmit(
            reviewType: selectedReviewType,
            resume: resume,
            selectedModel: selectedModel,
            knowledgeCards: knowledgeCardStore.approvedCards,
            customOptions: customOptions
        )
    }
}
