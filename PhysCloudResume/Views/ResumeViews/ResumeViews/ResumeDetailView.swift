import SwiftData
import SwiftUI

struct ResumeDetailView: View {
    @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
    @Binding var selRes: Resume?
    @Binding var tab: TabList
    let rootNode: TreeNode
    @Binding var isWide: Bool
    @State var dummypopup: Bool = false
    @State var refresher: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
//        ResRefView(
//          refPopup: $dummypopup,
//          isSourceExpanded: false,
//          tab: $tab
//        )
                nodeView(rootNode, refresher: $refresher)
            }
            .padding(.trailing, 16) // Add trailing padding to avoid overlap
        }
    }

    @ViewBuilder
    func nodeView(_ node: TreeNode, refresher: Binding<Bool>) -> some View {
        if node.hasChildren {
            NodeWithChildrenView(
                node: node,
                isExpanded: node.parent == nil,
                isWide: $isWide,
                refresher: refresher
            )
        } else {
            NodeLeafView(node: node, refresher: $refresher)
        }
    }
}

struct NodeWithChildrenView: View {
    let node: TreeNode
    @State var isExpanded: Bool
    @Binding var isWide: Bool
    @Binding var refresher: Bool
    @State private var isHoveringAdd: Bool = false // Track hover state for Add Child button

    init(node: TreeNode, isExpanded: Bool, isWide: Binding<Bool>, refresher: Binding<Bool>) {
        self.node = node
        _isExpanded = State(initialValue: isExpanded)
        _isWide = isWide
        _refresher = refresher
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.1), value: isExpanded)
                    .foregroundColor(.primary)
                    .onTapGesture {
                        withAnimation {
                            isExpanded.toggle()
                            if !isExpanded {
                                refresher.toggle()
                            }
                        }
                    }

                if node.parent == nil {
                    HeaderTextRow()
                } else {
                    AlignedTextRow(
                        leadingText: "\(node.name)",
                        trailingText: nil,
                        nodeStatus: node.status
                    )
                }

                Spacer()

                // Add Button aligned with parent node, not for the root node
                if isExpanded && node.parent != nil {
                    Button(action: {
                        addChild(to: node)
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(isHoveringAdd ? .green : .secondary)
                                .font(.system(size: 14))
                            Text("Add child")
                                .font(.caption)
                                .foregroundColor(isHoveringAdd ? .green : .secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(isHoveringAdd ? Color.white.opacity(0.4) : Color.clear)
                        .cornerRadius(10)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onHover { hovering in
                        isHoveringAdd = hovering
                    }
                }

                // Badge for `aiStatusChildren`
                if node.aiStatusChildren > 0 &&
                    (!isExpanded || node.parent == nil || node.parent?.parent == nil)
                {
                    Text("\(node.aiStatusChildren)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.2))
                        .foregroundColor(.blue)
                        .cornerRadius(10)
                }
            }
            .padding(.horizontal, 10)
            .padding(.leading, CGFloat(node.depth * 20)) // Adjust indentation based on depth
            .padding(.vertical, 5)
            .background(Color.clear)
            .cornerRadius(5)

            // Child nodes
            if isExpanded, let children = node.children?.sorted(by: { $0.myIndex < $1.myIndex }) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(children.enumerated()), id: \.1.id) { index, child in
                        Divider()
                        if child.hasChildren {
                            NodeWithChildrenView(
                                node: child,
                                isExpanded: false,
                                isWide: $isWide,
                                refresher: $refresher
                            )
                        } else {
                            ReorderableLeafRow(
                                node: child,
                                siblings: children,
                                currentIndex: index,
                                refresher: $refresher
                            )
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
    }

    private func addChild(to parent: TreeNode) {
        // Create a new child node
        let newNode = TreeNode(
            name: "",
            value: "New Child",
            status: .saved,
            resume: parent.resume
        )
        newNode.isEditing = true // Set isEditing to true for the new node
        print("new child")
        // Add the new child to the parent's children array
        parent.addChild(newNode)

        // Refresh the view to reflect the changes
        DispatchQueue.main.async {
            refresher.toggle()
        }
    }
}

import SwiftData
import SwiftUI

import SwiftData
import SwiftUI

struct NodeLeafView: View {
    @Environment(\.modelContext) private var context
    @State var node: TreeNode
    @Binding var refresher: Bool

    // New State Variables for Editing and Hovering
    @State private var isEditing: Bool = false
    @State private var tempValue: String = ""
    @State private var tempName: String = ""
    @State private var isHoveringEdit: Bool = false
    @State private var isHoveringSparkles: Bool = false // ✅ Add this missing state variable

    var body: some View {
        HStack(spacing: 5) {
            if node.value.isEmpty {
                Spacer().frame(width: 50)
                Text(node.name)
                    .foregroundColor(.gray)
            } else {
                if node.status != LeafStatus.disabled {
                    // Use SparkleButton
                    SparkleButton(
                        node: $node,
                        isHovering: $isHoveringSparkles, // ✅ Now, it's defined
                        toggleNodeStatus: toggleNodeStatus
                    )
                }

                if node.status == LeafStatus.disabled {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.gray)
                        .font(.system(size: 12))
                }

                if isEditing {
                    // Use EditingControls
                    EditingControls(
                        isEditing: $isEditing,
                        tempName: $tempName,
                        tempValue: $tempValue,
                        saveChanges: saveChanges,
                        cancelChanges: cancelChanges,
                        deleteNode: { deleteNode(node: node) }
                    )
                } else {
                    // Display Text Rows
                    if !node.name.isEmpty && !node.value.isEmpty {
                        StackedTextRow(
                            title: node.name,
                            description: node.value,
                            nodeStatus: node.status
                        )
                        Spacer()
                    } else {
                        AlignedTextRow(
                            leadingText: node.name,
                            trailingText: node.value,
                            nodeStatus: node.status
                        )
                        Spacer()
                    }

                    if node.status != LeafStatus.disabled {
                        // Edit Button
                        Button(action: {
                            startEditing()
                        }) {
                            Image(systemName: "square.and.pencil")
                                .foregroundColor(
                                    isHoveringEdit
                                        ? (node.status == LeafStatus.aiToReplace ? .primary : .accentColor)
                                        : (node.status == LeafStatus.aiToReplace ? .accentColor : .secondary)
                                )
                                .font(.system(size: 14))
                                .padding(5)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .onHover { hovering in
                            isHoveringEdit = hovering
                        }
                    }
                }
            }
        }
        .onChange(of: node.value) { _ in
            node.resume.debounceExport()
        }
        .onChange(of: node.name) { _ in
            node.resume.debounceExport()
        }
        .padding(.vertical, 4)
        .background(
            node.status == LeafStatus.aiToReplace
                ? Color.accentColor.opacity(0.3) : Color.clear
        )
        .cornerRadius(5)
    }

    // MARK: - Actions

    private func toggleNodeStatus() {
        if node.status == LeafStatus.saved {
            node.status = .aiToReplace
        } else if node.status == LeafStatus.aiToReplace {
            node.status = .saved
        }
    }

    private func startEditing() {
        tempValue = node.value
        tempName = node.name
        isEditing = true
    }

    private func saveChanges() {
        node.value = tempValue
        node.name = tempName
        node.status = .saved
        isEditing = false

        // Persist changes if needed
        try? context.save()
    }

    private func cancelChanges() {
        isEditing = false
    }

    private func deleteNode(node: TreeNode) {
        let resume = node.resume
        TreeNode.deleteTreeNode(node: node, context: context)
        resume.debounceExport()
        refresher.toggle()
    }
}

@ViewBuilder
func HeaderTextRow() -> some View {
    let leadingText = "Résumé Field Values"
    HStack {
        Text(leadingText).font(.headline)
    }
    .cornerRadius(5)
    .padding(.vertical, 2)
}

@ViewBuilder
func AlignedTextRow(
    leadingText: String,
    trailingText: String?,
    nodeStatus: LeafStatus // Pass the status as a parameter
) -> some View {
    let indent: CGFloat = 100.0
    @State var isHovering = false

    HStack {
        Text(leadingText)
            .foregroundColor(
                nodeStatus == .aiToReplace ? .accentColor : .secondary
            )
            .fontWeight(nodeStatus == .aiToReplace ? .medium : .regular)
            .frame(
                width: (trailingText == nil || trailingText!.isEmpty)
                    ? nil : leadingText == "" ? 15 : indent,
                alignment: .leading
            )

        if let trailingText = trailingText, !trailingText.isEmpty {
            Text(trailingText)
                .foregroundColor(
                    nodeStatus == .aiToReplace ? .accentColor : .secondary
                )
                .fontWeight(.regular)
                .frame(
                    minWidth: 0, maxWidth: .infinity, alignment: .leading
                )
        }
    }
    .cornerRadius(5)
    .padding(.vertical, 2)
}

@ViewBuilder
func StackedTextRow(
    title: String,
    description: String,
    nodeStatus: LeafStatus // Pass the status as a parameter
) -> some View {
    let indent: CGFloat = 100.0

    VStack(alignment: .leading) { // Added alignment for better layout
        Text(title)
            .foregroundColor(
                nodeStatus == .aiToReplace ? .accentColor : .secondary
            )
            .fontWeight(nodeStatus == .aiToReplace ? .semibold : .medium)
            .frame(minWidth: indent, maxWidth: .infinity, alignment: .leading)

        Text(description)
            .foregroundColor(
                nodeStatus == .aiToReplace ? .accentColor : .secondary
            )
            .fontWeight(
                nodeStatus == .aiToReplace ? .regular

                    : .light) // Simplified since both cases are .medium
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    } // Correctly closes VStack
    .cornerRadius(5)
    .padding(.vertical, 2)
}
