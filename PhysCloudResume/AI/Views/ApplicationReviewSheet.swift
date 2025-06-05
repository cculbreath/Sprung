//
//  ApplicationReviewSheet.swift
//  PhysCloudResume
//

import SwiftUI
import WebKit // Required for the MarkdownView

struct ApplicationReviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let jobApp: JobApp
    let resume: Resume
    let availableCoverLetters: [CoverLetter]

    // MARK: State

    @State private var reviewService = ApplicationReviewService()
    @State private var selectedType: ApplicationReviewType = .assessQuality
    @State private var customOptions: CustomApplicationReviewOptions
    @State private var responseText: String = ""
    @State private var isProcessing = false
    @State private var errorMessage: String? = nil

    init(jobApp: JobApp, resume: Resume, availableCoverLetters: [CoverLetter]) {
        self.jobApp = jobApp
        self.resume = resume
        self.availableCoverLetters = availableCoverLetters

        // Initialize customOptions with the jobApp's selectedCover if available
        let initialCoverLetter = jobApp.selectedCover
        _customOptions = State(initialValue: CustomApplicationReviewOptions(
            includeCoverLetter: true,
            includeResumeText: true,
            includeResumeImage: true,
            includeBackgroundDocs: false,
            selectedCoverLetter: initialCoverLetter,
            customPrompt: ""
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Fixed header
            Text("AI Application Review")
                .font(.title)
                .padding(.bottom, 16)
            
            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Application context section with information about what's being analyzed
                    GroupBox(label: Text("Analysis Context").fontWeight(.medium)) {
                VStack(alignment: .leading, spacing: 12) {
                    // Job information
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Position:")
                                .fontWeight(.semibold)
                                .frame(width: 80, alignment: .leading)
                            Text(jobApp.jobPosition)
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("Company:")
                                .fontWeight(.semibold)
                                .frame(width: 80, alignment: .leading)
                            Text(jobApp.companyName)
                                .foregroundColor(.secondary)
                        }
                    }

                    Divider()

                    // Documents being analyzed
                    HStack(alignment: .top, spacing: 16) {
                        // Resume information
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Resume:")
                                .fontWeight(.semibold)
                            Text("Created at \(resume.createdDateString)")
                                .foregroundColor(.secondary)
                                .font(.callout)
                        }

                        Spacer()

                        // Cover Letter information if available
                        if !availableCoverLetters.isEmpty, let selectedCover = jobApp.selectedCover {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Cover Letter:")
                                    .fontWeight(.semibold)
                                Text(selectedCover.sequencedName)
                                    .foregroundColor(.secondary)
                                    .font(.callout)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // Review type selection
            GroupBox(label: Text("Review Type").fontWeight(.medium)) {
                Picker("Select review type", selection: $selectedType) {
                    ForEach(ApplicationReviewType.allCases) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden() // Hide the redundant label
                .padding(.vertical, 4)
            }

            if selectedType == .custom {
                customOptionsView
            }
            
                    // AI Model Selection
                    DropdownModelPicker(
                        selectedModel: $preferredLLMModel,
                        title: "AI Model"
                    )

                    // Response area
                    GroupBox(label: Text("AI Analysis").fontWeight(.medium)) {
                        responseContent
                            .frame(minHeight: 200)
                    }
                    
                    // Debug info
                    if !responseText.isEmpty {
                        Text("Debug: Response has \(responseText.count) characters")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.bottom, 16)
            }
            
            // Fixed buttons at bottom
            HStack {
                if isProcessing {
                    Button("Stop") { reviewService.cancelRequest(); isProcessing = false }
                    Spacer()
                    Button("Close") { dismiss() }
                } else {
                    Button("Submit Request") { submit() }
                        .buttonStyle(.borderedProminent)
                    Spacer()
                    Button("Close") { dismiss() }
                }
            }
            .padding(.top, 8)
        }
        .padding()
        .frame(width: 700)
        .frame(minHeight: 600, maxHeight: 800)
    }

    // Persisted preferred model across the app
    @AppStorage("preferredLLMModel") private var preferredLLMModel: String = ""

    // MARK: - Custom Options View

    @ViewBuilder
    private var customOptionsView: some View {
        GroupBox(label: Text("Custom Options").fontWeight(.medium)) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Include Cover Letter", isOn: $customOptions.includeCoverLetter)
                    .onChange(of: customOptions.includeCoverLetter) { _, newVal in
                        if newVal && customOptions.selectedCoverLetter == nil {
                            // Default to the job app's selected cover letter
                            customOptions.selectedCoverLetter = jobApp.selectedCover
                        }
                    }

                if customOptions.includeCoverLetter {
                    Picker("Cover Letter", selection: Binding(
                        get: { customOptions.selectedCoverLetter ?? jobApp.selectedCover },
                        set: { customOptions.selectedCoverLetter = $0 }
                    )) {
                        ForEach(availableCoverLetters, id: \.self) { cl in
                            // Add a marker to indicate which is the current cover letter
                            Text(previewTitle(for: cl) + (cl.id == jobApp.selectedCover?.id ? " (Current)" : ""))
                                .tag(cl as CoverLetter?)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Toggle("Include Resume Text", isOn: $customOptions.includeResumeText)
                Toggle("Include Resume Image", isOn: $customOptions.includeResumeImage)
                Toggle("Include Background Docs", isOn: $customOptions.includeBackgroundDocs)

                Text("Custom Prompt")
                    .font(.headline)
                    .padding(.top, 4)
                TextEditor(text: $customOptions.customPrompt)
                    .frame(minHeight: 100)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.gray.opacity(0.3)))
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Response Content

    // A computed property for the response content to keep the main view clean
    @ViewBuilder
    private var responseContent: some View {
        if isProcessing {
            VStack(spacing: 16) {
                Spacer()
                ProgressView()
                Text(responseText.isEmpty ? "Analyzing application..." : responseText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if !responseText.isEmpty {
            // Use selectable text for the response
            ScrollView {
                Text(responseText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxHeight: 400) // Limit height to ensure it doesn't overflow
        } else if let error = errorMessage {
            Text(error)
                .foregroundColor(.red)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
        } else {
            Text("Select a review type above and click 'Submit Request' to analyze this application.")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
        }
    }

    private func previewTitle(for cl: CoverLetter) -> String {
        let txt = cl.content
        return txt.isEmpty ? "Cover Letter" : String(txt.prefix(40)) + (txt.count > 40 ? "…" : "")
    }

    // MARK: - Submit

    private func submit() {
        isProcessing = true
        responseText = "Submitting request..."
        errorMessage = nil

        let coverLetterToUse: CoverLetter? = {
            if selectedType == .custom {
                // For custom reviews, use the cover letter specifically selected in the UI picker
                return customOptions.selectedCoverLetter
            } else {
                // For standard reviews, always use the job app's selected cover letter
                return jobApp.selectedCover
            }
        }()

        Logger.debug("🚀 [ApplicationReviewSheet] Submitting review request")
        Logger.debug("🚀 [ApplicationReviewSheet] Review type: \(selectedType.rawValue)")
        Logger.debug("🚀 [ApplicationReviewSheet] Has custom options: \(selectedType == .custom)")
        
        Task { @MainActor in
            reviewService.sendReviewRequest(
                reviewType: selectedType,
                jobApp: jobApp,
                resume: resume,
                coverLetter: coverLetterToUse,
                customOptions: selectedType == .custom ? customOptions : nil,
                onProgress: { chunk in
                    Logger.debug("📝 [ApplicationReviewSheet] Progress callback - chunk length: \(chunk.count)")
                    Task { @MainActor in
                        // If we're just starting, clear any previous placeholder
                        if self.responseText == "Submitting request..." { 
                            self.responseText = "" 
                        }
                        self.responseText += chunk
                        Logger.debug("📝 [ApplicationReviewSheet] Updated response text length: \(self.responseText.count)")
                    }
                },
                onComplete: { result in
                    Logger.debug("✅ [ApplicationReviewSheet] Complete callback")
                    Task { @MainActor in
                        self.isProcessing = false
                        if case let .failure(err) = result { 
                            self.errorMessage = err.localizedDescription
                            Logger.error("x [ApplicationReviewSheet] Error: \(err)")
                        } else {
                            Logger.debug("✅ [ApplicationReviewSheet] Success")
                            Logger.debug("✅ [ApplicationReviewSheet] Final responseText: \(self.responseText.prefix(100))...")
                            Logger.debug("✅ [ApplicationReviewSheet] isProcessing: \(self.isProcessing)")
                        }
                    }
                }
            )
        }
    }
}
