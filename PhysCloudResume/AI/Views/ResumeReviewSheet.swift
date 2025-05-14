// PhysCloudResume/AI/Views/ResumeReviewSheet.swift

import PDFKit // Required for PDFDocument access if not already imported
import SwiftUI
import WebKit // Required for WKWebView used in MarkdownView
import Foundation

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
            } else if selectedReviewType == .reorderSkills {
                Text("Ready to reorder the 'Skills & Expertise' section for maximum relevance to the job position.")
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
                    Button(
                        selectedReviewType == .fixOverflow ? "Optimize Skills" :
                        selectedReviewType == .reorderSkills ? "Reorder Skills" : "Submit Request"
                    ) {
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
        } else if selectedReviewType == .reorderSkills {
            isProcessingFixOverflow = true
            fixOverflowStatusMessage = "Starting skills reordering..."
            Task {
                await performReorderSkills(resume: resume)
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
                            // Improved error display with more details
                            if let nsError = error as NSError? {
                                // Extract and display API errors
                                if nsError.domain == "OpenAIAPI" {
                                    generalError = "API Error: \(nsError.localizedDescription)"
                                } else if let errorInfo = nsError.userInfo[NSLocalizedDescriptionKey] as? String {
                                    // Specific handling for parameter errors
                                    generalError = "Error: \(errorInfo)\nPlease try again or select a different model in Settings."
                                } else {
                                    generalError = "Error: \(error.localizedDescription)"
                                }
                            } else {
                                generalError = "Error: \(error.localizedDescription)"
                            }
                            
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
        
        Logger.debug("FixOverflow: Starting performFixOverflow with max iterations: \(fixOverflowMaxIterations)")

        if resume.pdfData == nil {
            fixOverflowStatusMessage = "Generating initial PDF for analysis..."
            Logger.debug("FixOverflow: No PDF data, generating...")
            do {
                try await resume.ensureFreshRenderedText()
                guard resume.pdfData != nil else {
                    fixOverflowError = "Failed to generate initial PDF for Fix Overflow."
                    Logger.debug("FixOverflow: Failed to generate initial PDF")
                    isProcessingFixOverflow = false
                    return
                }
                Logger.debug("FixOverflow: Successfully generated initial PDF")
            } catch {
                fixOverflowError = "Error generating initial PDF: \(error.localizedDescription)"
                Logger.debug("FixOverflow: Error generating initial PDF: \(error.localizedDescription)")
                isProcessingFixOverflow = false
                return
            }
        } else {
            Logger.debug("FixOverflow: Using existing PDF data")
        }

        repeat {
            loopCount += 1
            Logger.debug("FixOverflow: Starting iteration \(loopCount) of \(fixOverflowMaxIterations)")
            fixOverflowStatusMessage = "Iteration \(loopCount)/\(fixOverflowMaxIterations): Analyzing skills section..."

            guard let currentPdfData = resume.pdfData,
                  let currentImageBase64 = ImageConversionService.shared.convertPDFToBase64Image(pdfData: currentPdfData)
            else {
                fixOverflowError = "Error converting current resume to image (Iteration \(loopCount))."
                Logger.debug("FixOverflow: Failed to convert PDF to image in iteration \(loopCount)")
                break
            }
            Logger.debug("FixOverflow: Successfully converted PDF to image")

            guard let skillsJsonString = reviewService.extractSkillsForLLM(resume: resume) else {
                fixOverflowError = "Error extracting skills from resume (Iteration \(loopCount))."
                Logger.debug("FixOverflow: Failed to extract skills from resume in iteration \(loopCount)")
                break
            }
            Logger.debug("FixOverflow: Successfully extracted skills JSON: \(skillsJsonString.prefix(100))...")

            if skillsJsonString == "[]" {
                fixOverflowStatusMessage = "No 'Skills and Expertise' items found to optimize or section is empty."
                Logger.debug("FixOverflow: No skills items found to optimize")
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
            var changedNodes: [(oldValue: String, newValue: String)] = []
            
            for revisedNode in fixFitsResponse.revisedSkillsAndExpertise {
                if let treeNode = findTreeNode(byId: revisedNode.id, in: resume) {
                    if revisedNode.isTitleNode {
                        if treeNode.name != revisedNode.newValue {
                            let oldValue = treeNode.name
                            treeNode.name = revisedNode.newValue
                            changesMadeInThisIteration = true
                            changedNodes.append((oldValue: oldValue, newValue: revisedNode.newValue))
                        }
                    } else {
                        if treeNode.value != revisedNode.newValue {
                            let oldValue = treeNode.value
                            treeNode.value = revisedNode.newValue
                            changesMadeInThisIteration = true
                            changedNodes.append((oldValue: oldValue, newValue: revisedNode.newValue))
                        }
                    }
                } else {
                    Logger.debug("Warning: TreeNode with ID \(revisedNode.id) not found for applying revision.")
                }
            }
            
            // Update status message with changes
            if !changedNodes.isEmpty {
                var changesSummary = "Iteration \(loopCount): \(changedNodes.count) node\(changedNodes.count > 1 ? "s" : "") updated:\n\n"
                
                for (index, change) in changedNodes.enumerated() {
                    // Truncate values if they're too long for display
                    let oldValueDisplay = change.oldValue.count > 50 ? change.oldValue.prefix(47) + "..." : change.oldValue
                    let newValueDisplay = change.newValue.count > 50 ? change.newValue.prefix(47) + "..." : change.newValue
                    
                    changesSummary += "\(index + 1). \"\(oldValueDisplay)\" → \"\(newValueDisplay)\"\n\n"
                }
                
                fixOverflowStatusMessage = changesSummary
            }

            if !changesMadeInThisIteration && loopCount > 1 {
                fixOverflowStatusMessage = "AI suggested no further changes. Assuming content fits or cannot be further optimized."
                operationSuccess = true
                break
            }

            // Store the changes summary to preserve it
            let changesSummary = fixOverflowStatusMessage
            
            // Update status while rendering but don't lose our changes summary
            fixOverflowStatusMessage = changesSummary + "\n\nRe-rendering resume with changes..."
            do {
                try await resume.ensureFreshRenderedText()
                guard resume.pdfData != nil else {
                    fixOverflowError = "Failed to re-render PDF after applying changes (Iteration \(loopCount))."
                    break
                }
                // Restore our changes summary after successful render
                fixOverflowStatusMessage = changesSummary
            } catch {
                fixOverflowError = "Error re-rendering PDF (Iteration \(loopCount)): \(error.localizedDescription)"
                break
            }

            guard let updatedPdfData = resume.pdfData,
                  let updatedImageBase64 = ImageConversionService.shared.convertPDFToBase64Image(pdfData: updatedPdfData)
            else {
                fixOverflowError = "Error converting updated resume to image (Iteration \(loopCount))."
                break
            }

            fixOverflowStatusMessage = "Iteration \(loopCount): Asking AI to check if content fits..."
            Logger.debug("FixOverflow: About to send contentsFit request in iteration \(loopCount)")
            let contentsFitResult: Result<ContentsFitResponse, Error> = await withCheckedContinuation { continuation in
                Logger.debug("FixOverflow: Inside continuation for contentsFit request")
                reviewService.sendContentsFitRequest(
                    resume: resume,
                    base64Image: updatedImageBase64
                ) { result in
                    Logger.debug("FixOverflow: Received contentsFit response: \(result)")
                    continuation.resume(returning: result)
                }
            }
            Logger.debug("FixOverflow: After contentsFit request in iteration \(loopCount)")

            guard case let .success(contentsFitResponse) = contentsFitResult else {
                if case let .failure(error) = contentsFitResult {
                    fixOverflowError = "Error checking content fit (Iteration \(loopCount)): \(error.localizedDescription)"
                } else {
                    fixOverflowError = "Unknown error checking content fit (Iteration \(loopCount))."
                }
                break
            }

            Logger.debug("FixOverflow: contentsFitResponse.contentsFit = \(contentsFitResponse.contentsFit)")
            if contentsFitResponse.contentsFit {
                fixOverflowStatusMessage = "AI confirms content fits after \(loopCount) iteration(s)."
                operationSuccess = true
                Logger.debug("FixOverflow: Content fits! Breaking loop.")
                break
            } else {
                Logger.debug("FixOverflow: Content does NOT fit. Will continue iterations if possible.")
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
    
    // MARK: - Reorder Skills Logic
    
    @MainActor
    func performReorderSkills(resume: Resume) async {
        Logger.debug("ReorderSkills: Starting performReorderSkills")
        fixOverflowStatusMessage = "Analyzing skills section..."
        
        if resume.jobApp == nil {
            fixOverflowError = "No job application associated with this resume. Add a job application first."
            isProcessingFixOverflow = false
            return
        }

        // Extract skills as JSON
        guard let skillsJsonString = reviewService.extractSkillsForLLM(resume: resume) else {
            fixOverflowError = "Error extracting skills from resume."
            Logger.debug("ReorderSkills: Failed to extract skills from resume")
            isProcessingFixOverflow = false
            return
        }
        
        Logger.debug("ReorderSkills: Successfully extracted skills JSON: \(skillsJsonString.prefix(100))...")

        if skillsJsonString == "[]" {
            fixOverflowStatusMessage = "No 'Skills and Expertise' items found to reorder or section is empty."
            Logger.debug("ReorderSkills: No skills items found to reorder")
            isProcessingFixOverflow = false
            return
        }

        fixOverflowStatusMessage = "Asking AI to analyze and reorder skills for the target job position..."

        // Send request to LLM to reorder skills
        let reorderResult: Result<ReorderSkillsResponseContainer, Error> = await withCheckedContinuation { continuation in
            reviewService.sendReorderSkillsRequest(
                resume: resume,
                skillsJsonString: skillsJsonString
            ) { result in
                continuation.resume(returning: result)
            }
        }

        // Handle LLM response
        guard case let .success(reorderResponse) = reorderResult else {
            if case let .failure(error) = reorderResult {
                fixOverflowError = "Error reordering skills: \(error.localizedDescription)"
            } else {
                fixOverflowError = "Unknown error while reordering skills."
            }
            isProcessingFixOverflow = false
            return
        }

        // Apply the new ordering
        fixOverflowStatusMessage = "Applying new skill order..."
        
        // Create a map of node IDs to their current positions for comparison
        var currentPositions: [String: Int] = [:]
        if let skillsSectionNode = resume.rootNode?.children?.first(where: { 
            $0.name.lowercased() == "skills-and-expertise" || $0.name.lowercased() == "skills and expertise" 
        }), let children = skillsSectionNode.children {
            for child in children {
                currentPositions[child.id] = child.myIndex
                
                // Also map subcategory children if they exist
                if let subChildren = child.children {
                    for subChild in subChildren {
                        currentPositions[subChild.id] = subChild.myIndex
                    }
                }
            }
        }
        
        // Format the reordering information for the status message
        var reasonsText = "Skills have been reordered for maximum relevance:\n\n"
        
        // Sort the nodes by their new position for display
        let sortedNodes = reorderResponse.reorderedSkillsAndExpertise.sorted { $0.newPosition < $1.newPosition }
        
        // Show position changes
        reasonsText += "Position changes:\n"
        for node in sortedNodes {
            let nodeText = node.isTitleNode ? "**\(node.originalValue)**" : node.originalValue
            let oldPosition = currentPositions[node.id] ?? -1
            
            // Skip nodes that didn't move or we couldn't find positions for
            if oldPosition == -1 || oldPosition == node.newPosition {
                continue
            }
            
            let changeIndicator = oldPosition < node.newPosition ? "↓" : "↑"
            reasonsText += "• \(nodeText) moved from position \(oldPosition) to \(node.newPosition) \(changeIndicator)\n"
        }
        
        reasonsText += "\n\nReordered skills with reasons:\n\n"
        for node in sortedNodes {
            let nodeText = node.isTitleNode ? "**\(node.originalValue)**" : node.originalValue
            reasonsText += "- \(nodeText)\n  _\(node.reasonForReordering)_\n\n"
        }
        
        // Apply the reordering to the actual tree nodes
        let success = TreeNodeExtractor.shared.applyReordering(resume: resume, reorderedNodes: reorderResponse.reorderedSkillsAndExpertise)
        
        if success {
            // Re-render the resume with the new order
            // Temporarily append the rendering status to the reasons text
            fixOverflowStatusMessage = reasonsText + "\n\nRe-rendering resume with new skill order..."
            do {
                try await resume.ensureFreshRenderedText()
                // Set back to just the reasons text after rendering completes
                fixOverflowStatusMessage = reasonsText
                
                // Make sure changes are saved
                resume.debounceExport()
            } catch {
                fixOverflowError = "Error re-rendering resume: \(error.localizedDescription)"
            }
        } else {
            fixOverflowError = "Error applying new skill order to resume."
        }
        
        isProcessingFixOverflow = false
    }
}
