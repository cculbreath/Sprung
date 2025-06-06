//
//  RevisionReviewView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/9/24.
//  Refactored on 6/4/25 - Slimmed down to pure view with ViewModel delegation
//

import SwiftData
import SwiftUI

/// Clean, focused view for reviewing AI revision proposals
/// All business logic delegated to ResumeReviseViewModel and enhanced node classes
struct RevisionReviewView: View {
    @Bindable var viewModel: ResumeReviseViewModel
    @Binding var resume: Resume?
    @State private var showExitConfirmation = false
    @State private var eventMonitor: Any? = nil

    var body: some View {
        if let resume = resume {
            if viewModel.aiResubmit {
                // Loading state during AI resubmission
                VStack {
                    Text("Submitting Feedback to AI").padding()
                    ProgressView().padding()
                }
            } else {
                // Main review interface
                ScrollView {
                    VStack {
                        if let currentRevisionNode = viewModel.currentRevisionNode,
                           let currentFeedbackNode = viewModel.currentFeedbackNode {
                            
                            // Header
                            RevisionReviewHeader(
                                currentIndex: viewModel.feedbackIndex,
                                totalCount: viewModel.resumeRevisions.count,
                                onPrevious: viewModel.feedbackIndex > 0 ? {
                                    viewModel.navigateToPrevious()
                                } : nil,
                                onNext: viewModel.feedbackIndex < viewModel.resumeRevisions.count - 1 ? {
                                    viewModel.navigateToNext()
                                } : nil
                            )
                            
                            // Content panels
                            RevisionComparisonPanels(
                                revisionNode: currentRevisionNode,
                                feedbackNode: currentFeedbackNode,
                                updateNodes: viewModel.updateNodes,
                                isEditingResponse: $viewModel.isEditingResponse,
                                isCommenting: $viewModel.isCommenting,
                                isMoreCommenting: $viewModel.isMoreCommenting
                            )
                            
                            // Action buttons
                            RevisionActionButtons(viewModel: viewModel, resume: resume)
                            
                        } else {
                            Text("No revision to display").padding()
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .clipped()
                .padding(.top, 0)
                .padding(.bottom, 40)
                .padding(.horizontal, 20)
                .onAppear {
                    setupView(for: resume)
                }
                .onDisappear {
                    cleanupEventMonitor()
                }
                .onChange(of: viewModel.aiResubmit) { _, newValue in
                    if !newValue {
                        // Reset to first node when AI resubmission completes
                        resetToFirstNode()
                    }
                }
                .alert("Close Review?", isPresented: $showExitConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("Apply & Close", role: .destructive) {
                        closeReview()
                    }
                } message: {
                    Text("Closing will apply any accepted changes and discard pending revisions.")
                }
            }
        } else {
            Text("No valid Resume")
        }
    }
    
    // MARK: - View Setup and Cleanup
    
    private func setupView(for resume: Resume) {
        viewModel.initializeUpdateNodes(for: resume)
        setupKeyboardShortcuts()
    }
    
    private func setupKeyboardShortcuts() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape key
                showExitConfirmation = true
                return nil
            }
            return event
        }
    }
    
    private func cleanupEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    private func resetToFirstNode() {
        viewModel.currentRevisionNode = viewModel.resumeRevisions.first
        viewModel.feedbackIndex = 0
        viewModel.feedbackNodes = []
    }
    
    private func closeReview() {
        if let resume = resume {
            viewModel.feedbackNodes.applyAcceptedChanges(to: resume)
        }
        viewModel.resumeRevisions = []
        viewModel.feedbackNodes = []
        viewModel.showResumeRevisionSheet = false
    }
}

// MARK: - Subviews

struct RevisionReviewHeader: View {
    let currentIndex: Int
    let totalCount: Int
    let onPrevious: (() -> Void)?
    let onNext: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [.cyan, .blue]),
                    startPoint: .top, endPoint: .bottom
                )
                .mask {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                }
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                
                Image(systemName: "sparkles")
                    .imageScale(.large)
                    .foregroundStyle(.white)
                    .font(.system(.largeTitle, weight: .light))
                    .rotationEffect(.degrees(90), anchor: .center)
                    .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 3)
            }
            .frame(width: 50, height: 50)
            .clipped()
            .padding(.bottom, 8)
            
            Text("Evaluate Proposed Revisions")
                .font(.system(.title, weight: .semibold))
                .multilineTextAlignment(.center)
            
            Text("Reviewing \(currentIndex + 1) of \(totalCount)")
                .font(.caption2)
                .fontWeight(.light)
            
            // Navigation controls
            HStack(spacing: 20) {
                Button(action: { onPrevious?() }) {
                    Image(systemName: "chevron.left.circle")
                        .font(.title2)
                        .foregroundColor(onPrevious != nil ? .blue : .gray)
                }
                .disabled(onPrevious == nil)
                .help("Previous revision")
                
                Button(action: { onNext?() }) {
                    Image(systemName: "chevron.right.circle")
                        .font(.title2)
                        .foregroundColor(onNext != nil ? .blue : .gray)
                }
                .disabled(onNext == nil)
                .help("Next revision")
            }
            .padding(.top, 8)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 60)
        .padding(.bottom, 45)
    }
}

struct RevisionComparisonPanels: View {
    let revisionNode: ProposedRevisionNode
    @Bindable var feedbackNode: FeedbackNode
    let updateNodes: [[String: Any]]
    @Binding var isEditingResponse: Bool
    @Binding var isCommenting: Bool
    @Binding var isMoreCommenting: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            if revisionNode.valueChanged {
                // Show comparison for changed values
                HStack(alignment: .top) {
                    // Original text panel
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Original Text")
                            .font(.system(.headline, weight: .semibold))
                        Text(revisionNode.originalText(using: updateNodes))
                            .font(.system(.headline, weight: .light))
                            .foregroundStyle(.secondary)
                            .padding()
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(8)
                    }
                    
                    Spacer()
                    
                    // Proposed revision panel
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Proposed Revision")
                            .font(.system(.headline, weight: .semibold))
                        
                        Text(feedbackNode.proposedRevision)
                            .font(.system(.headline, weight: .light))
                            .foregroundStyle(.primary)
                            .padding()
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(8)
                    }
                }
            } else {
                // Show single panel for unchanged values - centered
                VStack(alignment: .center, spacing: 12) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title2)
                        Text("No Changes Proposed")
                            .font(.system(.title2, weight: .semibold))
                    }
                    
                    VStack(alignment: .center, spacing: 8) {
                        Text("Current Value")
                            .font(.system(.headline, weight: .semibold))
                        Text(revisionNode.originalText(using: updateNodes))
                            .font(.system(.headline, weight: .light))
                            .foregroundStyle(.primary)
                            .padding()
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(8)
                            .frame(maxWidth: 400)
                    }
                    
                    if !revisionNode.why.isEmpty {
                        VStack(alignment: .center, spacing: 8) {
                            Text("AI Analysis")
                                .font(.system(.subheadline, weight: .semibold))
                            Text(revisionNode.why)
                                .font(.system(.subheadline, weight: .light))
                                .foregroundStyle(.secondary)
                                .padding()
                                .background(Color(.controlBackgroundColor))
                                .cornerRadius(8)
                                .frame(maxWidth: 400)
                        }
                    } else {
                        Text("AI determined this value doesn't need changes for the target job.")
                            .font(.system(.subheadline))
                            .foregroundStyle(.secondary)
                            .italic()
                            .frame(maxWidth: 400)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            
            // Reasoning section for changed values
            if revisionNode.valueChanged && !revisionNode.why.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("AI Reasoning")
                        .font(.system(.headline, weight: .semibold))
                    Text(revisionNode.why)
                        .font(.system(.subheadline, weight: .light))
                        .foregroundStyle(.secondary)
                        .padding()
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

struct RevisionActionButtons: View {
    @Bindable var viewModel: ResumeReviseViewModel
    let resume: Resume
    
    var body: some View {
        VStack(spacing: 20) {
            if currentRevNode?.valueChanged == true {
                Text("Accept proposed revision?")
                    .padding()
                    .font(.title2)
                
                HStack(spacing: 25) {
                    // Buttons for when there's a proposed change
                    ImageButton(
                        systemName: "hand.thumbsdown.circle",
                        activeColor: Color.purple,
                        isActive: viewModel.isCommenting || viewModel.isNodeRejectedWithComments(viewModel.currentFeedbackNode),
                        action: { 
                            viewModel.isCommenting = true
                        }
                    )
                    .help("Reject Revision with comment.")
                    
                    ImageButton(
                        systemName: "trash.circle",
                        activeColor: Color.red,
                        isActive: viewModel.isNodeRejectedWithoutComments(viewModel.currentFeedbackNode),
                        action: {
                            viewModel.saveAndNext(response: .rewriteNoComment, resume: resume)
                        }
                    )
                    .help("Try again. Reject Revision without comment.")
                    
                    ImageButton(
                        name: "ai-rejected", 
                        imageSize: 43, 
                        activeColor: Color.indigo,
                        isActive: viewModel.isNodeRestored(viewModel.currentFeedbackNode),
                        action: { 
                            viewModel.saveAndNext(response: .restored, resume: resume)
                        }
                    )
                    .help("Restore Original")
                    
                    ImageButton(
                        systemName: "pencil.circle",
                        isActive: viewModel.isEditingResponse || viewModel.isNodeEdited(viewModel.currentFeedbackNode),
                        action: { 
                            viewModel.isEditingResponse.toggle()
                        }
                    )
                    .help("Edit Response")
                    
                    // Accept button
                    ImageButton(
                        systemName: "hand.thumbsup.circle",
                        activeColor: Color.green,
                        isActive: viewModel.isNodeAccepted(viewModel.currentFeedbackNode),
                        action: {
                            viewModel.saveAndNext(response: .accepted, resume: resume)
                        }
                    )
                    .help("Accept this revision")
                }
            } else {
                // Interface for unchanged values - matching the style of changed values
                Text("Keep current value or request a change?")
                    .padding()
                    .font(.title2)
                
                HStack(spacing: 25) {
                    // Request change button (left side, matching reject position)
                    ImageButton(
                        systemName: "pencil.circle",
                        activeColor: Color.blue,
                        isActive: viewModel.isMoreCommenting || viewModel.isChangeRequested(viewModel.currentFeedbackNode),
                        action: { 
                            viewModel.isMoreCommenting = true
                        }
                    )
                    .help("Request change")
                    
                    // Keep as-is button (right side, matching accept position)
                    ImageButton(
                        systemName: "checkmark.circle",
                        activeColor: Color.green,
                        isActive: viewModel.isNodeAccepted(viewModel.currentFeedbackNode),
                        action: {
                            viewModel.saveAndNext(response: .noChange, resume: resume)
                        }
                    )
                    .help("Keep as is")
                }
            }
            
            // Editing interface when in edit mode
            if viewModel.isEditingResponse, let currentFeedbackNode = viewModel.currentFeedbackNode {
                HStack(spacing: 10) {
                    TextEditor(text: Binding(
                        get: { currentFeedbackNode.proposedRevision },
                        set: { newValue in
                            currentFeedbackNode.proposedRevision = newValue
                        }
                    ))
                    .font(.system(.body))
                    .frame(minHeight: 60)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
                    
                    VStack(spacing: 8) {
                        ImageButton(
                            systemName: "checkmark.circle",
                            imageSize: 20,
                            activeColor: Color.green,
                            action: {
                                viewModel.saveAndNext(response: .acceptedWithChanges, resume: resume)
                            }
                        )
                        
                        ImageButton(
                            systemName: "x.circle",
                            imageSize: 20,
                            activeColor: Color.red,
                            action: {
                                viewModel.isEditingResponse = false
                            }
                        )
                    }
                }
                .padding()
                .background(Color(.windowBackgroundColor))
                .cornerRadius(12)
            }
            
            // Commenting interface
            if viewModel.isCommenting || viewModel.isMoreCommenting,
               let currentFeedbackNode = viewModel.currentFeedbackNode {
                VStack(spacing: 8) {
                    Text("Add your comments for the AI:")
                        .font(.headline)
                    
                    TextEditor(text: Binding(
                        get: { currentFeedbackNode.reviewerComments },
                        set: { newValue in
                            currentFeedbackNode.reviewerComments = newValue
                        }
                    ))
                    .font(.system(.body))
                    .frame(minHeight: 80)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
                    
                    HStack(spacing: 12) {
                        Button("Submit with Comments") {
                            let response: PostReviewAction = viewModel.isCommenting ? .revise : .mandatedChange
                            viewModel.isCommenting = false
                            viewModel.isMoreCommenting = false
                            viewModel.saveAndNext(response: response, resume: resume)
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button("Cancel") {
                            viewModel.isCommenting = false
                            viewModel.isMoreCommenting = false
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .background(Color(.windowBackgroundColor))
                .cornerRadius(12)
            }
        }
        .padding()
    }
    
    private var currentRevNode: ProposedRevisionNode? {
        viewModel.currentRevisionNode
    }
}