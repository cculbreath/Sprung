//
//  ApplicationReviewSheet.swift
//  PhysCloudResume
//

import SwiftUI

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

            Picker("Review Type", selection: $selectedType) {
                ForEach(ApplicationReviewType.allCases) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.menu)

            if selectedType == .custom {
                customOptionsView
            }

            // Response area
            Group {
                if isProcessing {
                    ScrollView { Text(responseText.isEmpty ? "Analyzing..." : responseText).frame(maxWidth: .infinity, alignment: .leading) }
                } else if !responseText.isEmpty {
                    ScrollView { Text(responseText).frame(maxWidth: .infinity, alignment: .leading) }
                } else if let error = errorMessage {
                    Text(error).foregroundColor(.red)
                }
            }
            .frame(minHeight: 200)

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
        .frame(width: 650, height: 520, alignment: .topLeading)
    }

    // MARK: - Custom Options View
    @ViewBuilder
    private var customOptionsView: some View {
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
            TextEditor(text: $customOptions.customPrompt)
                .frame(minHeight: 100)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.gray.opacity(0.3)))
        }
    }

    private func previewTitle(for cl: CoverLetter) -> String {
        let txt = cl.content
        return txt.isEmpty ? "Cover Letter" : String(txt.prefix(40)) + (txt.count > 40 ? "…" : "")
    }

    // MARK: - Submit
    private func submit() {
        isProcessing = true; responseText = ""; errorMessage = nil

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
            onProgress: { chunk in responseText += chunk },
            onComplete: { result in
                isProcessing = false
                if case .failure(let err) = result { errorMessage = err.localizedDescription }
            }
        )
    }
}
