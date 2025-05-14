// PhysCloudResume/AI/Views/ResumeReviewSheet.swift

import PDFKit // Required for PDFDocument access if not already imported
import SwiftUI
import WebKit // Required for WKWebView used in MarkdownView

// Make sure we're using the right MarkdownView component

struct ResumeReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext // For finding TreeNodes

    @Binding var selectedResume: Resume?
    // Use the existing reviewService, it now has the new methods
    private let reviewService = ResumeReviewService()

    @State private var selectedReviewType: ResumeReviewType = .assessQuality
    @State private var customOptions = CustomReviewOptions() // For .custom type

    // State for general review text response (used by other review types)
    @State private var reviewResponseText = ""

    // State specific to Fix Overflow feature
    @State private var fixOverflowStatusMessage: String = ""
    @State private var isProcessingFixOverflow: Bool = false
    @State private var fixOverflowError: String? = nil

    // General processing and error state (can be shared or separated)
    @State private var isProcessingGeneral: Bool = false
    @State private var generalError: String? = nil

    // AppStorage for max iterations
    @AppStorage("fixOverflowMaxIterations") private var fixOverflowMaxIterations: Int = 3

    // Computed property for the content view (remains the same)
    private var contentView: some View {
        Group {
            if isProcessingGeneral {
                VStack(spacing: 16) {
                    Spacer()
                    ProgressView()
                    Text(reviewResponseText.isEmpty || reviewResponseText == "Submitting request..." ? "Analyzing resume..." : reviewResponseText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isProcessingFixOverflow {
                VStack(spacing: 16) {
                    Spacer()
                    ProgressView()
                    Text(fixOverflowStatusMessage.isEmpty ? "Optimizing skills section..." : fixOverflowStatusMessage)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !reviewResponseText.isEmpty {
                MarkdownView(markdown: reviewResponseText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
            } else if !fixOverflowStatusMessage.isEmpty {
                ScrollView {
                    Text(fixOverflowStatusMessage)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
            } else if let error = generalError ?? fixOverflowError {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            } else if selectedReviewType == .fixOverflow {
                Text("Ready to optimize the 'Skills & Expertise' section to prevent text overflow.")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                Text("Select a review type and submit your request.")
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
    }

    var body: some View {
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
                        // Reset states when review type changes
                        reviewResponseText = ""
                        fixOverflowStatusMessage = ""
                        isProcessingGeneral = false
                        isProcessingFixOverflow = false
                        generalError = nil
                        fixOverflowError = nil
                    }

                    // Custom options if custom type is selected
                    if selectedReviewType == .custom {
                        CustomReviewOptionsView(customOptions: $customOptions)
                    }

                    // Content area (GroupBox with contentView)
                    GroupBox(label: Text("AI Analysis").fontWeight(.medium)) {
                        contentView // This already handles its internal scrolling for MarkdownView
                            .frame(minHeight: 200, idealHeight: 300, maxHeight: .infinity) // Allow it to expand
                    }
                }
                .padding(.horizontal) // Padding for the scrollable content
                .padding(.bottom) // Padding at the bottom of scrollable content
            } // End ScrollView

            // Button row - Pinned to the bottom
            HStack {
                if isProcessingGeneral || isProcessingFixOverflow {
                    Button("Stop") {
                        reviewService.cancelRequest() // General cancel
                        isProcessingGeneral = false
                        isProcessingFixOverflow = false
                        fixOverflowStatusMessage = "Optimization stopped by user."
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Button("Close") { dismiss() }
                } else {
                    Button(selectedReviewType == .fixOverflow ? "Optimize Skills" : "Submit Request") {
                        handleSubmit()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedResume == nil)
                    Spacer()
                    Button("Close") { dismiss() }
                }
            }
            .padding([.horizontal, .bottom]) // Padding for the button bar
            .padding(.top, 8) // Add some space above the button bar
            .background(Color(NSColor.windowBackgroundColor).opacity(0.8)) // Optional: background for button bar
        }
        .frame(width: 600, height: 500, alignment: .topLeading) // Original fixed sheet size
        .onAppear {
            reviewService.initialize()
        }
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

    // Main submission handler - Unchanged
    func handleSubmit() {
        guard let resume = selectedResume else {
            generalError = "No resume selected."
            return
        }

        reviewResponseText = ""
        fixOverflowStatusMessage = ""
        generalError = nil
        fixOverflowError = nil

        if selectedReviewType == .fixOverflow {
            isProcessingFixOverflow = true
            fixOverflowStatusMessage = "Starting skills optimization..."
            Task {
                await performFixOverflow(resume: resume)
            }
        } else {
            isProcessingGeneral = true
            reviewResponseText = "Submitting request..."
            reviewService.sendReviewRequest(
                reviewType: selectedReviewType,
                resume: resume,
                customOptions: selectedReviewType == .custom ? customOptions : nil,
                onProgress: { contentChunk in
                    DispatchQueue.main.async {
                        if reviewResponseText == "Submitting request..." { reviewResponseText = "" }
                        reviewResponseText += contentChunk
                    }
                },
                onComplete: { result in
                    DispatchQueue.main.async {
                        isProcessingGeneral = false
                        switch result {
                        case let .success(finalMessage):
                            if reviewResponseText == "Submitting request..." || reviewResponseText.isEmpty {
                                reviewResponseText = finalMessage
                            }
                            if reviewResponseText.isEmpty {
                                reviewResponseText = "Review complete. No specific feedback provided."
                            }
                        case let .failure(error):
                            generalError = "Error: \(error.localizedDescription)"
                            if reviewResponseText == "Submitting request..." || !reviewResponseText.isEmpty {
                                reviewResponseText = ""
                            }
                        }
                    }
                }
            )
        }
    }

    // MARK: - Fix Overflow Logic (Unchanged)

    @MainActor
    func performFixOverflow(resume: Resume) async {
        var loopCount = 0
        var operationSuccess = false

        if resume.pdfData == nil {
            fixOverflowStatusMessage = "Generating initial PDF for analysis..."
            do {
                try await resume.ensureFreshRenderedText()
                guard resume.pdfData != nil else {
                    fixOverflowError = "Failed to generate initial PDF for Fix Overflow."
                    isProcessingFixOverflow = false
                    return
                }
            } catch {
                fixOverflowError = "Error generating initial PDF: \(error.localizedDescription)"
                isProcessingFixOverflow = false
                return
            }
        }

        repeat {
            loopCount += 1
            fixOverflowStatusMessage = "Iteration \(loopCount)/\(fixOverflowMaxIterations): Analyzing skills section..."

            guard let currentPdfData = resume.pdfData,
                  let currentImageBase64 = reviewService.convertPDFToBase64Image(pdfData: currentPdfData)
            else {
                fixOverflowError = "Error converting current resume to image (Iteration \(loopCount))."
                break
            }

            guard let skillsJsonString = reviewService.extractSkillsForLLM(resume: resume) else {
                fixOverflowError = "Error extracting skills from resume (Iteration \(loopCount))."
                break
            }

            if skillsJsonString == "[]" {
                fixOverflowStatusMessage = "No 'Skills and Expertise' items found to optimize or section is empty."
                operationSuccess = true
                break
            }

            fixOverflowStatusMessage = "Iteration \(loopCount): Asking AI to revise skills..."

            let fixFitsResult: Result<FixFitsResponseContainer, Error> = await withCheckedContinuation { continuation in
                reviewService.sendFixFitsRequest(
                    resume: resume,
                    skillsJsonString: skillsJsonString,
                    base64Image: currentImageBase64
                ) { result in
                    continuation.resume(returning: result)
                }
            }

            guard case let .success(fixFitsResponse) = fixFitsResult else {
                if case let .failure(error) = fixFitsResult {
                    fixOverflowError = "Error getting skill revisions (Iteration \(loopCount)): \(error.localizedDescription)"
                } else {
                    fixOverflowError = "Unknown error getting skill revisions (Iteration \(loopCount))."
                }
                break
            }

            fixOverflowStatusMessage = "Iteration \(loopCount): Applying suggested revisions..."
            var changesMadeInThisIteration = false
            for revisedNode in fixFitsResponse.revisedSkillsAndExpertise {
                if let treeNode = findTreeNode(byId: revisedNode.id, in: resume) {
                    if revisedNode.isTitleNode {
                        if treeNode.name != revisedNode.newValue {
                            treeNode.name = revisedNode.newValue
                            changesMadeInThisIteration = true
                        }
                    } else {
                        if treeNode.value != revisedNode.newValue {
                            treeNode.value = revisedNode.newValue
                            changesMadeInThisIteration = true
                        }
                    }
                } else {
                    Logger.debug("Warning: TreeNode with ID \(revisedNode.id) not found for applying revision.")
                }
            }

            if !changesMadeInThisIteration && loopCount > 1 {
                fixOverflowStatusMessage = "AI suggested no further changes. Assuming content fits or cannot be further optimized."
                operationSuccess = true
                break
            }

            fixOverflowStatusMessage = "Iteration \(loopCount): Re-rendering resume with changes..."
            do {
                try await resume.ensureFreshRenderedText()
                guard resume.pdfData != nil else {
                    fixOverflowError = "Failed to re-render PDF after applying changes (Iteration \(loopCount))."
                    break
                }
            } catch {
                fixOverflowError = "Error re-rendering PDF (Iteration \(loopCount)): \(error.localizedDescription)"
                break
            }

            guard let updatedPdfData = resume.pdfData,
                  let updatedImageBase64 = reviewService.convertPDFToBase64Image(pdfData: updatedPdfData)
            else {
                fixOverflowError = "Error converting updated resume to image (Iteration \(loopCount))."
                break
            }

            fixOverflowStatusMessage = "Iteration \(loopCount): Asking AI to check if content fits..."
            let contentsFitResult: Result<ContentsFitResponse, Error> = await withCheckedContinuation { continuation in
                reviewService.sendContentsFitRequest(
                    resume: resume,
                    base64Image: updatedImageBase64
                ) { result in
                    continuation.resume(returning: result)
                }
            }

            guard case let .success(contentsFitResponse) = contentsFitResult else {
                if case let .failure(error) = contentsFitResult {
                    fixOverflowError = "Error checking content fit (Iteration \(loopCount)): \(error.localizedDescription)"
                } else {
                    fixOverflowError = "Unknown error checking content fit (Iteration \(loopCount))."
                }
                break
            }

            if contentsFitResponse.contentsFit {
                fixOverflowStatusMessage = "AI confirms content fits after \(loopCount) iteration(s)."
                operationSuccess = true
                break
            }

            if loopCount >= fixOverflowMaxIterations {
                fixOverflowStatusMessage = "Reached maximum iterations (\(fixOverflowMaxIterations)). Manual review of skills section recommended."
                operationSuccess = false
                break
            }

            fixOverflowStatusMessage = "Iteration \(loopCount): Content still overflowing. Preparing for next iteration..."
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay

        } while true

        if fixOverflowError != nil {
            // Error message is already set
        } else if operationSuccess {
            if !fixOverflowStatusMessage.lowercased().contains("fits") {
                fixOverflowStatusMessage = "Skills section optimization complete."
            }
        } else if loopCount >= fixOverflowMaxIterations {
            // Message for max iterations already set
        } else {
            fixOverflowStatusMessage = "Fix Overflow operation did not complete as expected. Please review."
        }

        isProcessingFixOverflow = false
        resume.debounceExport()
    }

    // Helper to find TreeNode by ID - Unchanged
    func findTreeNode(byId id: String, in resume: Resume) -> TreeNode? {
        return resume.nodes.first { $0.id == id }
    }
}
