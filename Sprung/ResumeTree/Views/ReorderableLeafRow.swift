//
//  ReorderableLeafRow.swift
//  Sprung
//
//  Created by Christopher Culbreath on 1/31/25.
//
import SwiftUI
struct ReorderableLeafRow: View {
    @Environment(DragInfo.self) private var dragInfo
    @Environment(AppEnvironment.self) private var appEnvironment: AppEnvironment
    let node: TreeNode
    var siblings: [TreeNode]
    @State private var isDropTargeted: Bool = false // Manage state locally
    var body: some View {
        let canReorder = node.parent?.schemaAllowsChildMutation ?? false
        ZStack(alignment: .top) {
            NodeLeafView(node: node)
                .scaleEffect(dragInfo.draggedNode == node ? 1.05 : 1.0) // Slightly enlarge the dragged node
                .animation(.easeInOut, value: dragInfo.draggedNode) // Smoothly animate the scale effect
                .background(Color.clear) // Highlight on drop
                .padding(.leading, CGFloat(node.viewDepth) * 20) // now O(1) stored Int
                .onDrag {
                    guard canReorder else {
                        dragInfo.draggedNode = nil
                        return NSItemProvider()
                    }
                    dragInfo.draggedNode = node
                    return NSItemProvider(object: node.id as NSString)
                }
            if dragInfo.dropTargetNode == node {
                if dragInfo.dropPosition == .above {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                        .transition(.opacity) // Add a fade animation
                        .animation(.easeInOut, value: dragInfo.dropTargetNode) // Animate the transition
                } else if dragInfo.dropPosition == .below {
                    GeometryReader { proxy in
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(height: 2)
                            .position(x: proxy.size.width / 2, y: proxy.size.height)
                            .transition(.opacity)
                            .animation(.easeInOut, value: dragInfo.dropTargetNode) // Animate the transition
                    }
                }
            }
        }
        .onDrop(
            of: [.plainText],
            delegate: LeafDropDelegate(
                node: node,
                siblings: siblings,
                dragInfo: dragInfo,
                appEnvironment: appEnvironment,
                isDropTargeted: $isDropTargeted,
                canReorder: canReorder
            )
        )
    }
}
/// Custom DropDelegate for handling drag-and-drop logic
struct LeafDropDelegate: DropDelegate {
    let node: TreeNode
    var siblings: [TreeNode]
    var dragInfo: DragInfo
    let appEnvironment: AppEnvironment
    @Binding var isDropTargeted: Bool // Accept the binding for isDropTargeted
    let canReorder: Bool
    func validateDrop(info _: DropInfo) -> Bool {
        guard canReorder,
              let dragged = dragInfo.draggedNode,
              dragged.parent?.schemaAllowsChildMutation ?? false,
              node.parent?.schemaAllowsChildMutation ?? false else { return false }
        return dragged != node && haveSameParent(dragged, node)
    }
    func dropEntered(info: DropInfo) {
        guard canReorder else { return }
        guard let dragged = dragInfo.draggedNode else { return }
        if dragged != node && haveSameParent(dragged, node) {
            DispatchQueue.main.async {
                if let dropTargetIndex = siblings.firstIndex(of: node) {
                    let dropLocationY = info.location.y
                    let isAbove = dropLocationY < getMidY(for: dropTargetIndex)
                    dragInfo.dropTargetNode = node
                    dragInfo.dropPosition = isAbove ? .above : .below
                    isDropTargeted = true // Highlight the drop target
                }
            }
        }
    }
    func dropUpdated(info _: DropInfo) -> DropProposal? {
        guard canReorder else { return nil }
        return DropProposal(operation: .move)
    }
    func performDrop(info _: DropInfo) -> Bool {
        guard canReorder,
              let dragged = dragInfo.draggedNode,
              dragged.parent?.schemaAllowsChildMutation ?? false,
              node.parent?.schemaAllowsChildMutation ?? false else { return false }
        reorder(draggedNode: dragged, overNode: node)
        // Reset drop feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isDropTargeted = false
        }
        dragInfo.draggedNode = nil
        dragInfo.dropTargetNode = nil
        dragInfo.dropPosition = .none
        return true
    }
    func dropExited(info _: DropInfo) {
        guard canReorder else { return }
        isDropTargeted = false // Remove drop highlight
        dragInfo.dropTargetNode = nil
        dragInfo.dropPosition = .none
    }
    private func reorder(draggedNode: TreeNode, overNode: TreeNode) {
        guard let parent = overNode.parent, var array = parent.children else { return }
        // Sort the array by `myIndex` before processing
        array.sort { $0.myIndex < $1.myIndex }
        guard let fromIndex = array.firstIndex(of: draggedNode),
              let toIndex = array.firstIndex(of: overNode) else { return }
        withAnimation(.easeInOut) {
            // Remove the dragged node from its original position
            array.remove(at: fromIndex)
            // Calculate the new insertion index
            let insertionIndex = (dragInfo.dropPosition == .above) ? toIndex : toIndex + 1
            let boundedIndex = max(0, min(insertionIndex, array.count))
            // Insert the dragged node at the new position
            array.insert(draggedNode, at: boundedIndex)
            // Adjust `myIndex` values incrementally based on the sorted order
            for (index, node) in array.enumerated() {
                node.myIndex = index // Update `myIndex` to match the new order
            }
            // Save the reordered array back to the parent
            parent.children = array
        }
        // Save changes to SwiftData
        do {
            try parent.resume.modelContext?.save()
        } catch {
            Logger.warning(
                "Failed to save reordered nodes: \(error.localizedDescription)",
                category: .storage
            )
        }
        // Notify the Resume model
        appEnvironment.resumeExportCoordinator.debounceExport(resume: parent.resume)
    }
    private func haveSameParent(_ n1: TreeNode, _ n2: TreeNode) -> Bool {
        return n1.parent?.id == n2.parent?.id
    }
    private func getMidY(for index: Int) -> CGFloat {
        let rowHeight: CGFloat = 50.0
        return CGFloat(index) * rowHeight + rowHeight / 2
    }
}
