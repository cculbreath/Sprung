//
//  ResumeReviewSheet.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 5/11/25.
//

import SwiftUI

struct ResumeReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @Binding var selectedResume: Resume?
    @State private var reviewService = ResumeReviewService()
    @State private var selectedReviewType: ResumeReviewType = .assessQuality
    @State private var customOptions = CustomReviewOptions()
    @State private var responseText = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text("AI Resume Review")
                .font(.title)
                .padding(.bottom, 8)
            
            // Review type selection
            Picker("Review Type", selection: $selectedReviewType) {
                ForEach(ResumeReviewType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.menu)
            
            // Custom options if custom type is selected
            if selectedReviewType == .custom {
                customOptionsView
            }
            
            // Response area
            Group {
                if isProcessing {
                    ScrollView {
                        Text(responseText.isEmpty ? "Analyzing resume..." : responseText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                } else if !responseText.isEmpty {
                    ScrollView {
                        Text(responseText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                } else if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            .frame(minHeight: 200)
            
            // Button row
            HStack {
                Button("Cancel") {
                    if isProcessing {
                        reviewService.cancelRequest()
                    }
                    dismiss()
                }
                
                Spacer()
                
                if isProcessing {
                    Button("Stop") {
                        reviewService.cancelRequest()
                        isProcessing = false
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Submit Request") {
                        submitReviewRequest()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedResume == nil)
                }
            }
        }
        .padding()
        .frame(width: 600, height: 500)
    }
    
    // Custom options view for custom review type
    private var customOptionsView: some View {
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
                .frame(minHeight: 100)
        }
        .padding(.vertical, 8)
    }
    
    // Submit the review request to the LLM
    private func submitReviewRequest() {
        guard let resume = selectedResume else { return }
        
        isProcessing = true
        responseText = ""
        errorMessage = nil
        
        Task { @MainActor in
            do {
                // Use the review service to send the request
                reviewService.sendReviewRequest(
                    reviewType: selectedReviewType,
                    resume: resume,
                    customOptions: selectedReviewType == .custom ? customOptions : nil,
                    onProgress: { content in
                        responseText += content
                    },
                    onComplete: { result in
                        isProcessing = false
                        
                        switch result {
                        case .success:
                            // Already handled in onProgress
                            break
                        case .failure(let error):
                            errorMessage = "Error: \(error.localizedDescription)"
                        }
                    }
                )
            }
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var mockResume: Resume? = nil
        
        var body: some View {
            ResumeReviewSheet(selectedResume: $mockResume)
        }
    }
    
    return PreviewWrapper()
}