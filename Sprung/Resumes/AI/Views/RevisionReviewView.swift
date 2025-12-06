//
//  RevisionReviewView.swift
//  Sprung
//
//  Refactored on 6/19/25 - Enhanced for professional, polished appearance
//
import SwiftData
import SwiftUI
import AppKit
/// Clean, focused view for reviewing AI revision proposals with a professional, polished UI
/// All business logic delegated to ResumeReviseViewModel and enhanced node classes
struct RevisionReviewView: View {
    @Bindable var viewModel: ResumeReviseViewModel
    @Binding var resume: Resume?
    @State private var showExitConfirmation = false
    @State private var eventMonitor: Any?
    @Environment(AppEnvironment.self) private var appEnvironment: AppEnvironment
    private var maxContentHeight: CGFloat {
        let defaultHeight: CGFloat = 720
        if let screenHeight = NSScreen.main?.visibleFrame.height {
            return min(defaultHeight, screenHeight * 0.85)
        }
        return defaultHeight
    }
    // Computed property to check if reasoning modal should be used instead of loading sheet
    private var isUsingReasoningModal: Bool {
        guard let modelId = viewModel.currentModelId else { return false }
        let model = viewModel.openRouterService.findModel(id: modelId)
        return model?.supportsReasoning ?? false
    }
    var body: some View {
        VStack(spacing: 0) {
            if let resume = resume {
                if viewModel.aiResubmit && !isUsingReasoningModal {
                    // Loading state during AI resubmission (only for non-reasoning models)
                    VStack {
                        Text("Submitting Feedback to AI")
                            .font(.system(.title2, design: .rounded, weight: .medium))
                            .foregroundStyle(.primary)
                            .padding(.top, 20)
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 36))
                            .foregroundStyle(LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .symbolEffect(.pulse, options: .speed(1.2))
                            .padding(.vertical, 20)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .frame(maxWidth: 420)
                    .frame(maxHeight: maxContentHeight, alignment: .center)
                    .background(.background)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    // Main review interface
                    ScrollView {
                        VStack(spacing: 24) {
                            if let currentRevisionNode = viewModel.currentRevisionNode,
                               let currentFeedbackNode = viewModel.currentFeedbackNode {
                                // Header
                                RevisionReviewHeader(
                                    currentIndex: viewModel.feedbackIndex,
                                    totalCount: viewModel.resumeRevisions.count,
                                    onPrevious: viewModel.feedbackIndex > 0 ? {
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                            viewModel.navigateToPrevious()
                                        }
                                    } : nil,
                                    onNext: viewModel.feedbackIndex < viewModel.resumeRevisions.count - 1 ? {
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                            viewModel.navigateToNext()
                                        }
                                    } : nil
                                )
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                ))
                                // Content panels
                                RevisionComparisonPanels(
                                    revisionNode: currentRevisionNode,
                                    feedbackNode: currentFeedbackNode,
                                    updateNodes: viewModel.updateNodes,
                                    resume: resume,
                                    viewModel: viewModel,
                                    isEditingResponse: $viewModel.isEditingResponse,
                                    isCommenting: $viewModel.isCommenting,
                                    isMoreCommenting: $viewModel.isMoreCommenting
                                )
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                ))
                                // Action buttons
                                RevisionActionButtons(viewModel: viewModel, resume: resume)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            } else {
                                VStack(spacing: 16) {
                                    Image(systemName: "doc.text.magnifyingglass")
                                        .font(.system(size: 48))
                                        .foregroundStyle(.secondary)
                                        .symbolEffect(.pulse, options: .speed(0.8))
                                    Text("No revision to display")
                                        .font(.system(.title3, design: .rounded, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(40)
                                .background(.background)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .shadow(color: .black.opacity(0.05), radius: 8)
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.feedbackIndex)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: 820)
                    .frame(maxHeight: maxContentHeight)
                    .background(Color(NSColor.windowBackgroundColor))
                    .onAppear {
                        setupView(for: resume)
                    }
                    .onDisappear {
                        cleanupEventMonitor()
                    }
                    .onChange(of: viewModel.aiResubmit) { _, newValue in
                        if newValue, !isUsingReasoningModal {
                            // Close the sheet while we wait for the LLM to respond
                            viewModel.showResumeRevisionSheet = false
                        } else if !newValue {
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
                    .font(.system(.title3, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .frame(maxWidth: 860)
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
        Logger.debug("🔍 [RevisionReviewView] closeReview() called")
        Logger.debug("🔍 [RevisionReviewView] Current showResumeRevisionSheet: \(viewModel.showResumeRevisionSheet)")
        if let resume = resume {
            // Apply all feedback (both approved from previous rounds and current)
            let allFeedbackNodes = viewModel.approvedFeedbackNodes + viewModel.feedbackNodes
            allFeedbackNodes.applyAcceptedChanges(
                to: resume,
                exportCoordinator: appEnvironment.resumeExportCoordinator
            )
        }
        // Clear all state
        viewModel.resumeRevisions = []
        viewModel.feedbackNodes = []
        viewModel.approvedFeedbackNodes = []
        Logger.debug("🔍 [RevisionReviewView] Setting showResumeRevisionSheet = false")
        viewModel.showResumeRevisionSheet = false
        Logger.debug("🔍 [RevisionReviewView] After setting - showResumeRevisionSheet = \(viewModel.showResumeRevisionSheet)")
    }
}
// MARK: - Subviews
struct RevisionReviewHeader: View {
    let currentIndex: Int
    let totalCount: Int
    let onPrevious: (() -> Void)?
    let onNext: (() -> Void)?
    var body: some View {
        VStack(spacing: 16) {
            // Icon with modern gradient and subtle animation
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [.blue.opacity(0.9), .cyan.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 60, height: 60)
                    .shadow(color: .black.opacity(0.1), radius: 6)
                Image(systemName: "sparkles")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, options: .speed(1.0))
            }
            // Title with refined typography
            VStack(spacing: 8) {
                Text("Review AI Suggestions")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                Text("Revision \(currentIndex + 1) of \(totalCount)")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(.secondary.opacity(0.15))
                    .clipShape(Capsule())
            }
            // Navigation controls with modern styling
            HStack(spacing: 16) {
                NavigationButton(
                    systemName: "chevron.left",
                    isEnabled: onPrevious != nil,
                    action: { onPrevious?() },
                    helpText: "Previous revision"
                )
                NavigationButton(
                    systemName: "chevron.right",
                    isEnabled: onNext != nil,
                    action: { onNext?() },
                    helpText: "Next revision"
                )
            }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
    }
}
struct NavigationButton: View {
    let systemName: String
    let isEnabled: Bool
    let action: () -> Void
    let helpText: String
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isEnabled ? .blue : .secondary)
                .frame(width: 40, height: 40)
                .background(.background)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(isEnabled ? .blue.opacity(0.3) : .secondary.opacity(0.3), lineWidth: 1)
                }
        }
        .disabled(!isEnabled)
        .help(helpText)
        .buttonStyle(.plain)
        .scaleEffect(isEnabled ? 1.0 : 0.95)
        .animation(.easeOut(duration: 0.2), value: isEnabled)
    }
}
struct RevisionComparisonPanels: View {
    let revisionNode: ProposedRevisionNode
    @Bindable var feedbackNode: FeedbackNode
    let updateNodes: [[String: Any]]
    let resume: Resume
    let viewModel: ResumeReviseViewModel
    @Binding var isEditingResponse: Bool
    @Binding var isCommenting: Bool
    @Binding var isMoreCommenting: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if revisionNode.valueChanged {
                // Comparison for changed values
                VStack(alignment: .leading, spacing: 12) {
                    ComparisonPanel(
                        title: "Original Text",
                        content: revisionNode.originalText(using: updateNodes),
                        accentColor: .orange
                    )
                    if isEditingResponse {
                        EditableComparisonPanel(
                            title: "Proposed Revision (Editing)",
                            content: Binding(
                                get: { feedbackNode.proposedRevision },
                                set: { newValue in feedbackNode.proposedRevision = newValue }
                            ),
                            accentColor: .green,
                            onSave: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    viewModel.saveAndNext(response: .acceptedWithChanges, resume: resume)
                                }
                            },
                            onCancel: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    viewModel.isEditingResponse = false
                                }
                            }
                        )
                    } else {
                        ComparisonPanel(
                            title: "Proposed Revision",
                            content: feedbackNode.proposedRevision,
                            accentColor: .blue,
                            showEditButton: true,
                            onEdit: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    viewModel.isCommenting = false
                                    viewModel.isMoreCommenting = false
                                    viewModel.isEditingResponse = true
                                }
                            }
                        )
                    }
                }
            } else {
                // Single panel for unchanged values
                VStack(alignment: .center, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 20))
                        Text("No Changes Proposed")
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    UnchangedValuePanel(
                        title: "Current Value",
                        content: revisionNode.originalText(using: updateNodes),
                        showEditButton: false,
                        onEdit: nil
                    )
                    if !revisionNode.why.isEmpty {
                        ReasoningPanel(
                            title: "AI Analysis",
                            content: revisionNode.why
                        )
                    } else {
                        Text("AI determined this value doesn't need changes for the target job.")
                            .font(.system(.callout, design: .rounded))
                            .foregroundStyle(.secondary)
                            .italic()
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 500)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            // Reasoning section for changed values
            if revisionNode.valueChanged && !revisionNode.why.isEmpty {
                ReasoningPanel(
                    title: "AI Reasoning",
                    content: revisionNode.why
                )
            }
        }
        .padding(20)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 8)
    }
}
struct ComparisonPanel: View {
    let title: String
    let content: String
    let accentColor: Color
    let showEditButton: Bool
    let onEdit: (() -> Void)?
    @State private var isHovering = false
    init(title: String, content: String, accentColor: Color, showEditButton: Bool = false, onEdit: (() -> Void)? = nil) {
        self.title = title
        self.content = content
        self.accentColor = accentColor
        self.showEditButton = showEditButton
        self.onEdit = onEdit
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(accentColor)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(content)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.vertical, 8)
        }
        .padding(16)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(accentColor.opacity(0.2), lineWidth: 1)
        )
        .overlay(
            // Edit button overlay - positioned absolutely
            Group {
                if showEditButton, let onEdit = onEdit, isHovering {
                    Button(action: onEdit) {
                        Image(systemName: "pencil.circle")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                    .help("Edit Response")
                    .transition(.opacity.combined(with: .scale))
                }
            },
            alignment: .topTrailing
        )
        .frame(maxWidth: .infinity)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}
struct UnchangedValuePanel: View {
    let title: String
    let content: String
    let showEditButton: Bool
    let onEdit: (() -> Void)?
    @State private var isHovering = false
    init(title: String, content: String, showEditButton: Bool = false, onEdit: (() -> Void)? = nil) {
        self.title = title
        self.content = content
        self.showEditButton = showEditButton
        self.onEdit = onEdit
    }
    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            HStack {
                Spacer()
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(content)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(16)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.blue.opacity(0.2), lineWidth: 1)
                )
        }
        .frame(maxWidth: 500)
        .overlay(
            // Edit button overlay - positioned absolutely
            Group {
                if showEditButton, let onEdit = onEdit, isHovering {
                    Button(action: onEdit) {
                        Image(systemName: "pencil.circle")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                    .help("Manually edit")
                    .transition(.opacity.combined(with: .scale))
                }
            },
            alignment: .topTrailing
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}
struct ReasoningPanel: View {
    let title: String
    let content: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(.purple)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(content)
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        }
        .padding(16)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.purple.opacity(0.2), lineWidth: 1)
        )
    }
}
struct EditableComparisonPanel: View {
    let title: String
    @Binding var content: String
    let accentColor: Color
    let onSave: () -> Void
    let onCancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(accentColor)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            // Text editor with enhanced border
            TextEditor(text: $content)
                .font(.system(.body, design: .rounded))
                .frame(minHeight: 120)
                .padding(8)
                .background(.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(accentColor, lineWidth: 2.5)
                )
                .cornerRadius(8)
            // Save/Cancel buttons directly below the editor
            HStack(spacing: 12) {
                Button("Save Changes") {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.regular)
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                Spacer()
            }
        }
        .padding(16)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(accentColor.opacity(0.4), lineWidth: 2)
                .shadow(color: accentColor.opacity(0.2), radius: 6, x: 0, y: 0)
        )
        .frame(maxWidth: .infinity)
    }
}
struct RevisionActionButtons: View {
    @Bindable var viewModel: ResumeReviseViewModel
    let resume: Resume
    var body: some View {
        VStack(spacing: 16) {
            // Commenting interface - moved above action buttons
            if viewModel.isCommenting || viewModel.isMoreCommenting,
               let currentFeedbackNode = viewModel.currentFeedbackNode {
                VStack(spacing: 12) {
                    Text("Add your comments for the AI:")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.primary)
                    TextEditor(text: Binding(
                        get: { currentFeedbackNode.reviewerComments },
                        set: { newValue in currentFeedbackNode.reviewerComments = newValue }
                    ))
                    .font(.system(.body, design: .rounded))
                    .frame(minHeight: 100)
                    .padding(8)
                    .background(.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.blue.opacity(0.3), lineWidth: 1.5)
                    )
                    .cornerRadius(8)
                    HStack(spacing: 12) {
                        Button("Submit with Comments") {
                            let response: PostReviewAction = viewModel.isCommenting ? .revise : .mandatedChange
                            viewModel.isCommenting = false
                            viewModel.isMoreCommenting = false
                            viewModel.saveAndNext(response: response, resume: resume)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .controlSize(.large)
                        Button("Cancel") {
                            viewModel.isCommenting = false
                            viewModel.isMoreCommenting = false
                            if let feedbackNode = viewModel.currentFeedbackNode {
                                feedbackNode.reviewerComments = ""
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }
                .padding()
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.05), radius: 6)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.isCommenting || viewModel.isMoreCommenting)
            }
            if currentRevNode?.valueChanged == true {
                Text("Accept proposed revision?")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                HStack(spacing: 16) {
                    ImageButton(
                        systemName: "hand.thumbsdown.circle",
                        activeColor: .purple,
                        isActive: viewModel.isCommenting || viewModel.isNodeRejectedWithComments(viewModel.currentFeedbackNode),
                        action: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                viewModel.isEditingResponse = false
                                viewModel.isMoreCommenting = false
                                viewModel.isCommenting = true
                            }
                        }
                    )
                    .help("Reject Revision with comment")
                    ImageButton(
                        systemName: "trash.circle",
                        activeColor: .red,
                        isActive: viewModel.isNodeRejectedWithoutComments(viewModel.currentFeedbackNode),
                        action: {
                            viewModel.isCommenting = false
                            viewModel.isEditingResponse = false
                            viewModel.isMoreCommenting = false
                            viewModel.saveAndNext(response: .rewriteNoComment, resume: resume)
                        }
                    )
                    .help("Try again. Reject Revision without comment")
                    ImageButton(
                        name: "ai-rejected",
                        imageSize: 40,
                        activeColor: .indigo,
                        isActive: viewModel.isNodeRestored(viewModel.currentFeedbackNode),
                        action: {
                            viewModel.isCommenting = false
                            viewModel.isEditingResponse = false
                            viewModel.isMoreCommenting = false
                            viewModel.saveAndNext(response: .restored, resume: resume)
                        }
                    )
                    .help("Restore Original")
                    ImageButton(
                        systemName: "pencil.circle",
                        activeColor: .green,
                        isActive: viewModel.isEditingResponse || viewModel.isNodeEdited(viewModel.currentFeedbackNode),
                        action: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                viewModel.isCommenting = false
                                viewModel.isMoreCommenting = false
                                viewModel.isEditingResponse = true
                            }
                        }
                    )
                    .help("Edit Response")
                    ImageButton(
                        systemName: "hand.thumbsup.circle",
                        activeColor: .green,
                        isActive: viewModel.isNodeAccepted(viewModel.currentFeedbackNode),
                        action: {
                            viewModel.isCommenting = false
                            viewModel.isEditingResponse = false
                            viewModel.isMoreCommenting = false
                            viewModel.saveAndNext(response: .accepted, resume: resume)
                        }
                    )
                    .help("Accept this revision")
                }
            } else {
                Text("Accept current value?")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                HStack(spacing: 16) {
                    ImageButton(
                        systemName: "hand.thumbsdown.circle",
                        activeColor: .purple,
                        isActive: viewModel.isCommenting || viewModel.isNodeRejectedWithComments(viewModel.currentFeedbackNode),
                        action: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                viewModel.isEditingResponse = false
                                viewModel.isMoreCommenting = false
                                viewModel.isCommenting = true
                            }
                        }
                    )
                    .help("Reject with comment")
                    ImageButton(
                        systemName: "hand.thumbsup.circle",
                        activeColor: .green,
                        isActive: viewModel.isNodeAccepted(viewModel.currentFeedbackNode),
                        action: {
                            viewModel.isCommenting = false
                            viewModel.isEditingResponse = false
                            viewModel.isMoreCommenting = false
                            viewModel.saveAndNext(response: .noChange, resume: resume)
                        }
                    )
                    .help("Accept current value")
                }
            }
        }
        .padding(.vertical, 16)
    }
    private var currentRevNode: ProposedRevisionNode? {
        viewModel.currentRevisionNode
    }
}
