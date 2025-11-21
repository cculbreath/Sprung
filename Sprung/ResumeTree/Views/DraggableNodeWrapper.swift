//
//  DraggableNodeWrapper.swift
//  Sprung
//
//  Created by Christopher Culbreath on 2/27/25.
//
import SwiftUI
struct DraggableNodeWrapper<Content: View>: View {
    let node: TreeNode
    let siblings: [TreeNode]
    let content: Content

    @Environment(DragInfo.self) private var dragInfo
    @Environment(AppEnvironment.self) private var appEnvironment: AppEnvironment
    @State private var isDropTargeted: Bool = false

    init(node: TreeNode, siblings: [TreeNode], @ViewBuilder content: () -> Content) {
        self.node = node
        self.siblings = siblings
        self.content = content()
    }

    private var isDraggable: Bool {
        // Only allow dragging if not a direct child of root node
        guard let parent = node.parent else { return false }
        return parent.parent != nil // Has a grandparent, so not direct child of root
    }

    var body: some View {
        ZStack(alignment: .top) {
            content
                .scaleEffect(dragInfo.draggedNode == node ? 1.02 : 1.0)
                .animation(.easeInOut, value: dragInfo.draggedNode)
                .background(Color.clear)
                .onDrag {
                    if isDraggable {
                        dragInfo.draggedNode = node
                        return NSItemProvider(object: node.id as NSString)
                    } else {
                        return NSItemProvider()
                    }
                }

            if dragInfo.dropTargetNode == node {
                if dragInfo.dropPosition == .above {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                        .transition(.opacity)
                        .animation(.easeInOut, value: dragInfo.dropTargetNode)
                } else if dragInfo.dropPosition == .below {
                    GeometryReader { proxy in
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(height: 2)
                            .position(x: proxy.size.width / 2, y: proxy.size.height)
                            .transition(.opacity)
                            .animation(.easeInOut, value: dragInfo.dropTargetNode)
                    }
                }
            }
        }
        .onDrop(of: [.plainText], delegate: NodeDropDelegate(
            node: node,
            siblings: siblings,
            dragInfo: dragInfo,
            appEnvironment: appEnvironment,
            isDropTargeted: $isDropTargeted,
            isDraggable: isDraggable
        ))
    }
}
struct NodeDropDelegate: DropDelegate {
    let node: TreeNode
    var siblings: [TreeNode]
    var dragInfo: DragInfo
    let appEnvironment: AppEnvironment
    @Binding var isDropTargeted: Bool
    let isDraggable: Bool

    func validateDrop(info: DropInfo) -> Bool {
        guard let dragged = dragInfo.draggedNode else { return false }
        return isDraggable && dragged != node && haveSameParent(dragged, node)
    }

    func dropEntered(info: DropInfo) {
        guard let dragged = dragInfo.draggedNode else { return }

        if isDraggable && dragged != node && haveSameParent(dragged, node) {
            DispatchQueue.main.async {
                if let dropTargetIndex = siblings.firstIndex(of: node) {
                    let dropLocationY = info.location.y
                    let isAbove = dropLocationY < getMidY(for: dropTargetIndex)
                    dragInfo.dropTargetNode = node
                    dragInfo.dropPosition = isAbove ? .above : .below
                    isDropTargeted = true
                }
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let dragged = dragInfo.draggedNode else { return false }
        guard isDraggable else { return false }

        reorder(draggedNode: dragged, overNode: node)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isDropTargeted = false
        }

        dragInfo.draggedNode = nil
        dragInfo.dropTargetNode = nil
        dragInfo.dropPosition = .none

        return true
    }

    func dropExited(info: DropInfo) {
        isDropTargeted = false
        dragInfo.dropTargetNode = nil
        dragInfo.dropPosition = .none
    }

    private func reorder(draggedNode: TreeNode, overNode: TreeNode) {
        guard let parent = overNode.parent, var array = parent.children else { return }

        array.sort { $0.myIndex < $1.myIndex }

        guard let fromIndex = array.firstIndex(of: draggedNode),
              let toIndex = array.firstIndex(of: overNode) else { return }

        withAnimation(.easeInOut) {
            array.remove(at: fromIndex)

            let insertionIndex = (dragInfo.dropPosition == .above) ? toIndex : toIndex + 1
            let boundedIndex = max(0, min(insertionIndex, array.count))

            array.insert(draggedNode, at: boundedIndex)

            for (index, node) in array.enumerated() {
                node.myIndex = index
            }

            parent.children = array
        }

        do {
            try parent.resume.modelContext?.save()
        } catch {
            Logger.warning(
                "Failed to persist dragged node reorder: \(error.localizedDescription)",
                category: .storage
            )
        }

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
