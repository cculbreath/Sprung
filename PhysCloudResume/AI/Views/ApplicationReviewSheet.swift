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
    @State private var customOptions = CustomApplicationReviewOptions()
    @State private var responseText: String = ""
    @State private var isProcessing = false
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AI Application Review")
                .font(.title)

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

            // Response area
            GroupBox(label: Text("AI Analysis").fontWeight(.medium)) {
                responseContent
                    .frame(minHeight: 200)
            }

            // Buttons
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
        }
        .padding()
        .frame(width: 700, height: 600, alignment: .topLeading)
    }

    // MARK: - Custom Options View

    @ViewBuilder
    private var customOptionsView: some View {
        GroupBox(label: Text("Custom Options").fontWeight(.medium)) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Include Cover Letter", isOn: $customOptions.includeCoverLetter)
                    .onChange(of: customOptions.includeCoverLetter) { _, newVal in
                        if newVal && customOptions.selectedCoverLetter == nil {
                            customOptions.selectedCoverLetter = availableCoverLetters.first
                        }
                    }

                if customOptions.includeCoverLetter {
                    Picker("Cover Letter", selection: Binding(
                        get: { customOptions.selectedCoverLetter ?? availableCoverLetters.first },
                        set: { customOptions.selectedCoverLetter = $0 }
                    )) {
                        ForEach(availableCoverLetters, id: \.self) { cl in
                            Text(previewTitle(for: cl)).tag(cl as CoverLetter?)
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
            VStack {
                Spacer()
                ProgressView {
                    Text(responseText.isEmpty ? "Analyzing application..." : responseText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if !responseText.isEmpty {
            // Use MarkdownView for rich text rendering
            MarkdownView(markdown: responseText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(8)
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
                return customOptions.selectedCoverLetter
            } else {
                return availableCoverLetters.first(where: { $0 == customOptions.selectedCoverLetter }) ?? availableCoverLetters.first
            }
        }()

        reviewService.sendReviewRequest(
            reviewType: selectedType,
            jobApp: jobApp,
            resume: resume,
            coverLetter: coverLetterToUse,
            customOptions: selectedType == .custom ? customOptions : nil,
            onProgress: { chunk in
                DispatchQueue.main.async {
                    // If we're just starting, clear any previous placeholder
                    if responseText == "Submitting request..." { responseText = "" }
                    responseText += chunk
                }
            },
            onComplete: { result in
                DispatchQueue.main.async {
                    isProcessing = false
                    if case let .failure(err) = result { errorMessage = err.localizedDescription }
                }
            }
        )
    }
}
