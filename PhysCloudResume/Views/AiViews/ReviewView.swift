import SwiftData
import SwiftUI

struct ReviewView: View {
    @Environment(ResStore.self) private var resStore
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
                                        Text(currentRevNode.oldValue)
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
                .onChange(of: aiResub) { oldValue, newValue in
                    print("aiResub changed from \(oldValue ? "true" : "false") to \(newValue ? "true" : "false")")
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
                print("default")
            }
        }
    }

    func nextNode() {
        @Environment(\.modelContext) var context: ModelContext

        if let currentFeedbackNode = currentFeedbackNode {
            feedbackArray.append(currentFeedbackNode)
            print(feedbackArray.count)
            feedbackIndex += 1
        }
        if feedbackIndex < revisionArray.count {
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
            applyChanges()
            let aiActions: Set<PostReviewAction> = [
                .revise, .mandatedChange, .mandatedChangeNoComment, .rewriteNoComment,
            ]

            if feedbackArray.contains(where: { node in
                aiActions.contains(node.actionRequested)
            }) {
                for fb in feedbackArray {
                    print(fb.proposedRevision)
                    print("Action: \(String(describing: fb.actionRequested))")
                }
                aiResubmit()
            } else {
                if var selRes = selRes {
                    if var selRes = resStore.createDuplicate(originalResume: selRes, context: context) {
                        selRes.debounceExport()
                    }
                }
                sheetOn = false
            }
        }
    }

    func applyChanges() {
        for node in feedbackArray {
            if node.actionRequested == .accepted || node.actionRequested == .acceptedWithChanges {
                if let selRes = selRes {
                    if let treeNode = selRes.nodes.first(where: { $0.id == node.id }) {
                        // Debug logging to help diagnose issues
                        print("Processing node ID: \(node.id)")
                        print("isTitleNode value: \(node.isTitleNode)")

                        if node.isTitleNode {
                            print("Updating NAME to: \(node.proposedRevision)")
                            treeNode.name = node.proposedRevision
                        } else {
                            print("Updating VALUE to: \(node.proposedRevision)")
                            treeNode.value = node.proposedRevision
                        }
                    } else {
                        print("❌ ERROR: Node not found with ID: \(node.id)")

                        // Try to diagnose the issue by listing available node IDs
                        print("Available node IDs:")
                        for treeNode in selRes.nodes.prefix(10) {
                            print("- \(treeNode.id)")
                        }
                        if selRes.nodes.count > 10 {
                            print("... and \(selRes.nodes.count - 10) more")
                        }
                    }
                }
            }
        }
        // After applying accepted changes, trigger a PDF refresh for the
        // currently selected resume so the new values are exported.
        selRes?.debounceExport()
    }

    func aiResubmit() {
        feedbackIndex = 0
        aiResub = true
    }

    func fetchModelByID(id: String, context: ModelContext) -> TreeNode? {
        var descriptor = FetchDescriptor<TreeNode>()
        descriptor.predicate = #Predicate { $0.id == id }
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
