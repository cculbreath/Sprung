import SwiftData
import SwiftUI

struct ResumeDetailView: View {
  @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
  @Binding var selRes: Resume?
  @Binding var tab: TabList
  let rootNode: TreeNode
  @Binding var isWide: Bool
  @State var dummypopup: Bool = false
  var body: some View {

    ScrollView {
      VStack(alignment: .leading, spacing: 10) {

        //        AiPanelView(res: $selRes)  // Pass the unwrapped Binding
        ResRefView(
          refPopup: $dummypopup,
          isSourceExpanded: false,
          selRes: $selRes,
          tab: $tab
        )  // Pass the unwrapped Binding
      }
      nodeView(rootNode)
    }

  }
  @ViewBuilder
  func nodeView(_ node: TreeNode) -> some View {
    if node.hasChildren {
      NodeWithChildrenView(
        node: node, isExpanded: node.parent == nil, isWide: $isWide)
    } else {
      NodeLeafView(node: node)
    }
  }
}

struct NodeWithChildrenView: View {
  let node: TreeNode
  @State var isExpanded: Bool
  @State var isHovering = false
  @Binding var isWide: Bool

  init(node: TreeNode, isExpanded: Bool, isWide: Binding<Bool>) {
    self.node = node
    self._isExpanded = State(initialValue: isExpanded)
    self._isWide = isWide
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
              if !isExpanded { isWide = false }
            }
          }
        if node.parent == nil {
          HeaderTextRow()
        } else {
          AlignedTextRow(
            leadingText: "\(node.name)", trailingText: nil,
            nodeStatus: node.status
          )
        }
        Spacer()

        // Add the badge for aiStatusChildren count
        if node.aiStatusChildren > 0
          && (!isExpanded || node.parent == nil
            || node.parent?.parent == nil)
        {
          Text("\(node.aiStatusChildren)")
            .font(.caption).fontWeight(.medium)
            .padding(.horizontal, 10)  // Increase horizontal padding for a wider shape
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.2))
            .foregroundColor(.blue)
            .cornerRadius(10)
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(isHovering ? Color.gray.opacity(0.3) : Color.clear)
      .cornerRadius(5)
      //            .onHover { hovering in
      //                isHovering = hovering
      //            }
      .onTapGesture {
        withAnimation {
          isExpanded.toggle()
          if isExpanded == false {
            isWide = false
          }
        }
      }

      if isExpanded, let children = node.children {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(
            children.sorted(by: { $0.myIndex < $1.myIndex }),
            id: \.self
          ) { child in

            Divider()
            nodeView(child).onAppear {
              if child.nodeDepth > 2 {
                isWide = true
              }
            }
            .transition(isWide ? .opacity : .move(edge: .top))
          }
        }
        .padding(.leading, 25)
      }

    }
  }
  @ViewBuilder
  func nodeView(_ node: TreeNode) -> some View {
    if node.hasChildren {
      NodeWithChildrenView(node: node, isExpanded: false, isWide: $isWide)
    } else {
      NodeLeafView(node: node)
    }
  }
}

struct NodeLeafView: View {
  @Environment(\.modelContext) private var context
  @State var node: TreeNode
  @State private var isHoveringSparkles = false
  @State private var isHoveringEdit = false
  @State private var isEditing = false
  @State private var tempValue: String = ""
  init(
    node: TreeNode,
    isHoveringSparkles: Bool = false,
    isHoveringEdit: Bool = false,
    isEditing: Bool = false
  ) {
    self.node = node
    self.isHoveringSparkles = isHoveringSparkles
    self.isHoveringEdit = isHoveringEdit
    self.isEditing = isEditing
    self.tempValue = ""
  }
  var body: some View {
    HStack(spacing: 5) {

      if node.value.isEmpty {
        Spacer().frame(width: 50)
        Text(node.name)
          .foregroundColor(.gray)
      } else {
        if node.status != LeafStatus.disabled {
          Button(action: {
            toggleNodeStatus()
          }) {
            Image(systemName: "sparkles")
              .foregroundColor(
                node.status == LeafStatus.saved
                  ? .gray : .accentColor
              )
              .font(.system(size: 14))
              .padding(2)
              .background(
                isHoveringSparkles
                  ? (node.status == LeafStatus.saved
                    ? Color.gray.opacity(0.3)
                    : Color.accentColor.opacity(0.3))
                  : Color.clear
              )
              .cornerRadius(5)
          }
          .buttonStyle(PlainButtonStyle())
          //                    .onHover { hovering in
          //                        isHoveringSparkles = hovering
          //                    }
        }
        if node.status == LeafStatus.disabled {
          Image(systemName: "lock.fill")
            .foregroundColor(.gray)
            .font(.system(size: 12))
        }

        if isEditing {
          HStack(spacing: 10){
            Button(action: {deleteNode(node: node)}){Image(systemName: "trash")}
              .buttonStyle(PlainButtonStyle())
            TextField("", text: $tempValue)
              .textFieldStyle(PlainTextFieldStyle()).lineLimit(1...5)
              .padding(5)
              .background(Color.primary.opacity(0.1))
              .cornerRadius(5)
              .frame(maxWidth: .infinity)
          }
          HStack(spacing: 10) {
            Button(action: {
              saveChanges()
            }) {
              Image(systemName: "checkmark.circle.fill")
                .foregroundColor(
                  isHoveringEdit ? .green : .secondary
                )
                .font(.system(size: 14))
            }
            .buttonStyle(PlainButtonStyle())
            //                        .onHover { hovering in
            //                            isHoveringEdit = hovering
            //                        }

            Button(action: {
              cancelChanges()
            }) {
              Image(systemName: "xmark.circle.fill")
                .foregroundColor(
                  isHoveringEdit ? .red : .secondary
                )
                .font(.system(size: 14))
            }
            .buttonStyle(PlainButtonStyle())
            //                        .onHover { hovering in
            //                            isHoveringEdit = hovering
            //                        }
          }
        } else {
          AlignedTextRow(
            leadingText: "\(node.myIndex) \(node.name)", trailingText: node.value,
            nodeStatus: node.status)

          Spacer()

          if node.status != LeafStatus.disabled {
            HStack(spacing: 10) {
              Button(action: {
                startEditing()
              }) {
                Image(systemName: "square.and.pencil")
                  .foregroundColor(
                    isHoveringEdit
                      ? node.status
                        == LeafStatus.aiToReplace
                        ? .primary : .accentColor
                      : (node.status
                        == LeafStatus.aiToReplace
                        ? .accentColor : .secondary)
                  )
                  .font(.system(size: 14))
                  .padding(5)
              }
              .buttonStyle(PlainButtonStyle())
              //                            .onHover { hovering in
              //                                isHoveringEdit = hovering
              //                            }
            }
          }
        }
      }
    }.onChange(of: node.value) {
      node.resume.debounceExport()
    }
    .padding(.vertical, 4)
    .background(
      node.status == LeafStatus.aiToReplace
        ? Color.accentColor.opacity(0.3) : Color.clear
    )
    .cornerRadius(5)
  }
  private func deleteNode(node: TreeNode) {

      TreeNode.deleteTreeNode(node: node, context: context)  // Call the deletion function on the node

  }
  private func startEditing() {
    tempValue = node.value
    isEditing = true
  }

  private func saveChanges() {
    node.value = tempValue
    node.status = .saved
    isEditing = false
  }

  private func cancelChanges() {
    isEditing = false
  }

  private func toggleNodeStatus() {
    if node.status == LeafStatus.saved {
      node.status = LeafStatus.aiToReplace
    } else if node.status == LeafStatus.aiToReplace {
      node.status = LeafStatus.saved
    }
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
  nodeStatus: LeafStatus  // Pass the status as a parameter
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
        alignment: .leading)

    if let trailingText = trailingText, !trailingText.isEmpty {
      Text(trailingText)
        .foregroundColor(
          nodeStatus == .aiToReplace ? .accentColor : .secondary
        )
        .fontWeight(.regular)
        .frame(
          minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }
  }
  .cornerRadius(5)
  .padding(.vertical, 2)
}
