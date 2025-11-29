//
//  BestJobModelSelectionSheet.swift
//  Sprung
//
//  Specialized model selection sheet for Find Best Job operation with background toggles
//
import SwiftUI
/// Specialized model selection sheet for Find Best Job operation
/// Includes toggles for resume background and cover letter background facts
struct BestJobModelSelectionSheet: View {
    // MARK: - Properties
    @Binding var isPresented: Bool
    let onModelSelected: (String, Bool, Bool) -> Void
    // MARK: - Environment
    // MARK: - State
    @State private var selectedModel: String = ""
    @AppStorage("includeResumeBackground_best_job") private var includeResumeBackground: Bool = false
    @AppStorage("includeCoverLetterBackground_best_job") private var includeCoverLetterBackground: Bool = false
    @AppStorage("lastSelectedModel_best_job") private var lastSelectedModel: String = ""
    // MARK: - Body
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Choose Model for Job Recommendation")
                    .font(.headline)
                    .padding(.top)
                DropdownModelPicker(
                    selectedModel: $selectedModel,
                    requiredCapability: .structuredOutput,
                    title: "AI Model"
                )
                VStack(alignment: .leading, spacing: 12) {
                    Text("Background Information")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Toggle("Include resume background", isOn: $includeResumeBackground)
                        .help("Include background sources from resume for job recommendation analysis")
                    Toggle("Include cover letter background facts", isOn: $includeCoverLetterBackground)
                        .help("Include background facts from cover letters for job recommendation analysis")
                }
                .padding(.horizontal)
                HStack(spacing: 12) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .buttonStyle(.bordered)
                    Button("Continue") {
                        // Save the selected model for future use
                        lastSelectedModel = selectedModel
                        isPresented = false
                        onModelSelected(selectedModel, includeResumeBackground, includeCoverLetterBackground)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedModel.isEmpty)
                }
                Spacer()
            }
            .padding()
            .frame(width: 450, height: 320)
            .onAppear {
                // Load the last selected model
                if !lastSelectedModel.isEmpty {
                    selectedModel = lastSelectedModel
                }
            }
        }
    }
}
