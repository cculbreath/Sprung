//
//  ReviewView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/9/24.
//

import SwiftData
import SwiftUI

struct ReviewView: View {
    @Environment(ResStore.self) private var resStore
    @Environment(\.modelContext) private var modelContext
    @Binding var revisionArray: [ProposedRevisionNode]
    @Binding var feedbackArray: [FeedbackNode]
    @State private var feedbackIndex: Int = 0
    @Binding var currentFeedbackNode: FeedbackNode?
    @Binding var currentRevNode: ProposedRevisionNode?
    @Binding var sheetOn: Bool
    @Binding var selRes: Resume?
    @State private var updateNodes: [[String: Any]] = []
    @Binding var aiResub: Bool
    @State var isEditingResponse: Bool = false
    @State var isCommenting: Bool = false
    @State var isMoreCommenting: Bool = false

    // Helper to supply original text especially for title nodes where oldValue may be empty
    private func originalText(for node: ProposedRevisionNode) -> String {
        let trimmedOld = node.oldValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedOld.isEmpty {
            return trimmedOld
        }

        // Fallback to updateNodes for original value if available
        if let dict = updateNodes.first(where: {
            ($0["id"] as? String) == node.id &&
                ($0["isTitleNode"] as? Bool) == node.isTitleNode
        }), let fallback = (dict["value"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
        !fallback.isEmpty {
            return fallback
        }
        // Fallback for title nodes: derive from treePath last component
        if node.isTitleNode {
            let parts = node.treePath.split(separator: ">").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let last = parts.last, !last.isEmpty {
                return last
            }
        }
        return "(no text)"
    }

    var body: some View {
        if let selRes = selRes {
            if aiResub {
                VStack {
                    Text("Submitting Feedback to AI").padding()
                    ProgressView().padding()
                }
            } else {
                ScrollView {
                    VStack {
                        if let currentRevNode = currentRevNode, let currentFeedbackNode = currentFeedbackNode {
                            VStack(spacing: 4) {
                                ZStack {
                                    LinearGradient(
                                        gradient: Gradient(colors: [.cyan, .blue]),
                                        startPoint: .top, endPoint: .bottom
                                    )
                                    .mask {
                                        RoundedRectangle(
                                            cornerRadius: 18, style: .continuous
                                        )
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
                                Text("Reviewing \(feedbackIndex + 1) of \(revisionArray.count)")
                                    .font(.caption2)
                                    .fontWeight(.light)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 60)
                            .padding(.bottom, 45)
                            VStack(alignment: .leading, spacing: 15) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Original Text")
                                            .font(.system(.headline, weight: .semibold))
                                            .transition(.move(edge: .trailing))
                                        Text(originalText(for: currentRevNode))
                                            .font(.system(.headline, weight: .light))
                                            .foregroundStyle(.secondary)
                                            .transition(.move(edge: .trailing))
                                    }
                                    .fixedSize(horizontal: false, vertical: true)
                                }
                                if currentRevNode.valueChanged {
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("Proposed Revision")
                                                .font(.system(.title2, weight: .semibold))
                                                .transition(.move(edge: .trailing))
                                            if isEditingResponse {
                                                HStack(spacing: 10) {
                                                    TextField(
                                                        "RevisedText",
                                                        text: Binding(
                                                            get: { currentFeedbackNode.proposedRevision },
                                                            set: { newValue in
                                                                self.currentFeedbackNode?.proposedRevision = newValue
                                                            }
                                                        ),
                                                        axis: .vertical
                                                    ).lineLimit(4 ... 10)
                                                    Spacer()
                                                    ImageButton(
                                                        systemName: "checkmark.circle",
                                                        imageSize: 20,
                                                        activeColor: Color.green,
                                                        action: {
                                                            saveAndNext(response: .acceptedWithChanges)
                                                        }
                                                    )
                                                    ImageButton(
                                                        systemName: "x.circle",
                                                        imageSize: 20,
                                                        activeColor: Color.red,
                                                        action: {
                                                            isEditingResponse = false
                                                        }
                                                    )
                                                }
                                                .frame(maxWidth: .infinity)
                                            } else {
                                                Text(currentRevNode.newValue)
                                                    .font(.system(.title2, weight: .light))
                                                    .transition(.move(edge: .trailing))
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                if currentRevNode.valueChanged {
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("Explanation")
                                                .font(.system(.headline, weight: .semibold))
                                                .transition(.move(edge: .trailing))
                                            Text(currentRevNode.why)
                                                .font(.system(.headline, weight: .light))
                                                .foregroundStyle(.secondary)
                                                .transition(.move(edge: .trailing))
                                        }
                                        .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .padding(.leading, 30)
                            .padding(.trailing, 30)
                            Text(currentRevNode.valueChanged ? "Accept proposed revision?" : "Accept original value unchanged?")
                                .padding()
                                .font(.title2)
                            HStack(spacing: 25) {
                                if currentRevNode.valueChanged {
                                    ImageButton(
                                        systemName: "hand.thumbsdown.circle",
                                        activeColor: Color.purple,
                                        action: { isCommenting = true }
                                    ).help("Reject Revision with comment.").popover(isPresented: $isCommenting) {
                                        ReviewCommentView(
                                            comment: Binding(
                                                get: { currentFeedbackNode.reviewerComments },
                                                set: { newValue in
                                                    self.currentFeedbackNode?.reviewerComments = newValue
                                                }
                                            ),
                                            isCommenting: $isCommenting,
                                            saveAction: {
                                                saveAndNext(response: .revise)
                                            }
                                        )
                                    }
                                    ImageButton(
                                        systemName: "trash.circle",
                                        activeColor: Color.red,
                                        action: {
                                            saveAndNext(response: .rewriteNoComment)
                                        }
                                    ).help("Try again. Reject Revision without comment.")
                                } else {
                                    ImageButton(
                                        systemName: "hand.thumbsdown.circle",
                                        activeColor: Color.purple,
                                        action: { isMoreCommenting = true }
                                    ).popover(isPresented: $isMoreCommenting) {
                                        ReviewCommentView(
                                            comment: Binding(
                                                get: { currentFeedbackNode.reviewerComments },
                                                set: { newValue in
                                                    self.currentFeedbackNode?.reviewerComments = newValue
                                                }
                                            ),
                                            isCommenting: $isCommenting,
                                            saveAction: {
                                                saveAndNext(response: .mandatedChange)
                                            }
                                        )
                                    }
                                    ImageButton(
                                        systemName: "trash.circle",
                                        activeColor: Color.red,
                                        action: {
                                            saveAndNext(response: .mandatedChangeNoComment)
                                        }
                                    )
                                }
                                if currentRevNode.valueChanged {
                                    ImageButton(
                                        name: "ai-rejected", imageSize: 43, activeColor: Color.indigo,
                                        action: { saveAndNext(response: .restored) }
                                    )
                                    ImageButton(
                                        systemName: "pencil.circle",
                                        action: { isEditingResponse = true }
                                    )
                                }
                                ImageButton(
                                    systemName: "hand.thumbsup.circle",
                                    activeColor: Color.green,
                                    action: {
                                        saveAndNext(response: currentRevNode.valueChanged ? .accepted : .noChange)
                                    }
                                ).help("Approve revision")
                            }
                        } else {
                            // Handle the case where currentRevNode or currentFeedbackNode is nil
                            Text("No revision to display").padding()
                        }
                    }
                } // Close ScrollView
                .frame(maxWidth: .infinity)
                .clipped()
                .padding(.top, 0)
                .padding(.bottom, 40)
                .padding(.horizontal, 20)
                .onChange(of: aiResub) { _, newValue in
                    if !newValue {
                        currentRevNode = revisionArray.first
                        feedbackIndex = 0
                        feedbackArray = []
                    }
                }
                .onAppear {
                    if updateNodes.isEmpty {
                        updateNodes = selRes.getUpdatableNodes()
                    }
                }
            }
        } else { Text("No valid Res") }
    }

    func saveAndNext(response: PostReviewAction) {
        if let currentFeedbackNode = currentFeedbackNode {
            currentFeedbackNode.actionRequested = response
            switch response {
            case .accepted:
                nextNode()
            case .acceptedWithChanges:
                isEditingResponse = false
                nextNode()
            case .restored:
                currentFeedbackNode.proposedRevision =
                    currentFeedbackNode.originalValue
                nextNode()
            case .revise:
                isCommenting = false
                nextNode()
            case .rewriteNoComment:
                nextNode()
            case .mandatedChangeNoComment:
                isCommenting = false
                nextNode()
            case .mandatedChange:
                nextNode()
            case .noChange:
                nextNode()
            default:
                print("Default, you should not be here!!")
            }
        }
    }

    func nextNode() {
        // Move the environment outside function body - will be captured from View's environment
        if let currentFeedbackNode = currentFeedbackNode {
            feedbackArray.append(currentFeedbackNode)
            feedbackIndex += 1
            print("Added node to feedbackArray. New index: \(feedbackIndex)/\(revisionArray.count)")
        }

        if feedbackIndex < revisionArray.count {
            print("Moving to next node at index \(feedbackIndex)")
            withAnimation(.easeInOut(duration: 0.5)) {
                currentRevNode = revisionArray[feedbackIndex]
                if let currentRevNode = currentRevNode {
                    currentFeedbackNode = FeedbackNode(
                        id: currentRevNode.id,
                        originalValue: currentRevNode.oldValue,
                        proposedRevision: currentRevNode.newValue,
                        actionRequested: .unevaluated,
                        reviewerComments: "",
                        isTitleNode: currentRevNode.isTitleNode
                    )
                }
            }
        } else {
            print("Reached end of revisionArray. Applying changes...")
            applyChanges()

            // Log stats about the feedback node categories
            print("\n===== FEEDBACK NODE STATISTICS =====")
            print("Total feedback nodes: \(feedbackArray.count)")

            let acceptedCount = feedbackArray.filter { $0.actionRequested == .accepted }.count
            let acceptedWithChangesCount = feedbackArray.filter { $0.actionRequested == .acceptedWithChanges }.count
            let noChangeCount = feedbackArray.filter { $0.actionRequested == .noChange }.count
            let restoredCount = feedbackArray.filter { $0.actionRequested == .restored }.count
            let reviseCount = feedbackArray.filter { $0.actionRequested == .revise }.count
            let rewriteNoCommentCount = feedbackArray.filter { $0.actionRequested == .rewriteNoComment }.count
            let mandatedChangeCount = feedbackArray.filter { $0.actionRequested == .mandatedChange }.count
            let mandatedChangeNoCommentCount = feedbackArray.filter { $0.actionRequested == .mandatedChangeNoComment }.count

            print("Accepted: \(acceptedCount)")
            print("Accepted with changes: \(acceptedWithChangesCount)")
            print("No change needed: \(noChangeCount)")
            print("Restored to original: \(restoredCount)")
            print("Revise (with comments): \(reviseCount)")
            print("Rewrite (no comments): \(rewriteNoCommentCount)")
            print("Mandated change (with comments): \(mandatedChangeCount)")
            print("Mandated change (no comments): \(mandatedChangeNoCommentCount)")
            print("==================================\n")

            let aiActions: Set<PostReviewAction> = [
                .revise, .mandatedChange, .mandatedChangeNoComment, .rewriteNoComment,
            ]

            // Filter feedbackArray to only include nodes that need AI intervention
            let nodesToResubmit = feedbackArray.filter { node in
                aiActions.contains(node.actionRequested)
            }

            print("Found \(nodesToResubmit.count) nodes requiring resubmission out of \(feedbackArray.count) total")

            if !nodesToResubmit.isEmpty {
                print("Resubmitting \(nodesToResubmit.count) nodes to AI...")
                // Only keep nodes that need AI intervention for the next round
                feedbackArray = nodesToResubmit

                // Log the exact nodes we're sending for revision
                for (index, node) in feedbackArray.enumerated() {
                    print("Node \(index + 1)/\(feedbackArray.count) for revision:")
                    print("  - ID: \(node.id)")
                    print("  - Action: \(node.actionRequested.rawValue)")
                    print("  - Original: \(node.originalValue.prefix(30))\(node.originalValue.count > 30 ? "..." : "")")
                    if !node.reviewerComments.isEmpty {
                        print("  - Comments: \(node.reviewerComments.prefix(50))\(node.reviewerComments.count > 50 ? "..." : "")")
                    }
                }

                aiResubmit()
            } else {
                print("No nodes need resubmission. All changes are applied, dismissing sheet...")
                // Simply dismiss the sheet - no need to create a duplicate
                sheetOn = false
            }
        }
    }

    func applyChanges() {
        for node in feedbackArray {
            if node.actionRequested == .accepted || node.actionRequested == .acceptedWithChanges {
                if let selRes = selRes {
                    if let treeNode = selRes.nodes.first(where: { $0.id == node.id }) {
                        // Apply the change based on whether it's a title node or value node
                        if node.isTitleNode {
                            treeNode.name = node.proposedRevision
                        } else {
                            treeNode.value = node.proposedRevision
                        }

                        // Ensure the isTitleNode property is set correctly for future rendering
                        // If this is a title node update, make sure the TreeNode knows it's a title node
                        if node.isTitleNode {
                            treeNode.isTitleNode = true
                        }
                    } else {
                        // Try to diagnose the issue by listing available node IDs
                        print("Could not find TreeNode with ID: \(node.id) to apply changes")
                    }
                }
            }
        }
        // After applying accepted changes, trigger a PDF refresh for the
        // currently selected resume so the new values are exported.
        selRes?.debounceExport()
    }

    func aiResubmit() {
        // Reset to original state before resubmitting to AI
        feedbackIndex = 0

        // First, immediately show the loading UI
        withAnimation {
            aiResub = true
        }

        // Apply any accepted changes to the resume
        applyChanges()

        // Print summary of what we're submitting for revision
        print("\n===== SUBMITTING REVISION REQUEST =====")
        print("Number of nodes to revise: \(feedbackArray.count)")

        // Count by feedback type
        let typeCount = feedbackArray.reduce(into: [PostReviewAction: Int]()) { counts, node in
            counts[node.actionRequested, default: 0] += 1
        }

        for (action, count) in typeCount.sorted(by: { $0.value > $1.value }) {
            print("  - \(action.rawValue): \(count) nodes")
        }

        // List node IDs being submitted
        let nodeIds = feedbackArray.map { $0.id }.joined(separator: ", ")
        print("Node IDs: \(nodeIds)")
        print("========================================\n")

        // Force PDF re-rendering to ensure up-to-date textRes
        if let selRes = selRes {
            print("Starting PDF re-rendering for AI resubmission...")
            Task {
                do {
                    // Await the PDF rendering completion
                    try await selRes.ensureFreshRenderedText()
                    print("PDF rendering complete for AI resubmission")

                    // After render completes, aiResub is already true, so the LLM call will happen automatically
                    // The AiCommsView watches for changes to aiResub, which triggers its chatAction
                } catch {
                    print("Error rendering resume for AI resubmission: \(error)")
                    await MainActor.run {
                        aiResub = false
                        // Show an error to the user?
                    }
                }
            }
        }

        // Safety timeout - if aiResub remains true for too long, auto-dismiss the sheet
        // as this likely indicates a communication issue with the AI service
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { // 2 minute timeout
            if aiResub {
                print("Timeout reached for AI resubmission. Auto-dismissing.")
                aiResub = false
                sheetOn = false
            }
        }
    }

    func fetchModelByID(id: String) -> TreeNode? {
        var descriptor = FetchDescriptor<TreeNode>()
        descriptor.predicate = #Predicate { $0.id == id }
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}
