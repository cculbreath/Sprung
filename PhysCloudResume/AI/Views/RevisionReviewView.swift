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
                                totalCount: viewModel.resumeRevisions.count
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
                    
                    if isEditingResponse {
                        TextEditor(text: $feedbackNode.proposedRevision)
                            .font(.system(.headline, weight: .light))
                            .padding(8)
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(8)
                            .frame(minHeight: 60)
                    } else {
                        Text(feedbackNode.proposedRevision)
                            .font(.system(.headline, weight: .light))
                            .foregroundStyle(.primary)
                            .padding()
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(8)
                    }
                }
            }
            
            // Reasoning section
            if !revisionNode.why.isEmpty {
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
            
            // Comments section
            if isCommenting || isMoreCommenting {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your Comments")
                        .font(.system(.headline, weight: .semibold))
                    TextEditor(text: $feedbackNode.reviewerComments)
                        .font(.system(.subheadline))
                        .padding(8)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(8)
                        .frame(minHeight: 80)
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
        VStack(spacing: 12) {
            // Primary action buttons
            HStack(spacing: 12) {
                Button("Accept") {
                    viewModel.saveAndNext(response: PostReviewAction.accepted, resume: resume)
                }
                .buttonStyle(.borderedProminent)
                
                Button("Accept with Changes") {
                    viewModel.saveAndNext(response: PostReviewAction.acceptedWithChanges, resume: resume)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.isEditingResponse)
                
                Button("Restore Original") {
                    viewModel.saveAndNext(response: PostReviewAction.restored, resume: resume)
                }
                .buttonStyle(.bordered)
            }
            
            // Secondary action buttons
            HStack(spacing: 12) {
                Button("Ask AI to Revise") {
                    viewModel.isCommenting = true
                    viewModel.saveAndNext(response: PostReviewAction.revise, resume: resume)
                }
                .buttonStyle(.bordered)
                
                Button("Reject & Request Rewrite") {
                    viewModel.saveAndNext(response: PostReviewAction.rewriteNoComment, resume: resume)
                }
                .buttonStyle(.bordered)
            }
            
            // Edit toggles
            HStack(spacing: 12) {
                Button(viewModel.isEditingResponse ? "Done Editing" : "Edit Response") {
                    viewModel.isEditingResponse.toggle()
                }
                .buttonStyle(.borderless)
                
                Button(viewModel.isCommenting ? "Done Commenting" : "Add Comments") {
                    viewModel.isCommenting.toggle()
                }
                .buttonStyle(.borderless)
            }
            .font(.caption)
        }
        .padding()
    }
}