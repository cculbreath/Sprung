//
//  ChipDropDelegate.swift
//  Sprung
//
//  Implements DropDelegate for chip reordering within a FlowStack.
//  Manages drop-target tracking via DragInfo, determines left/right
//  insertion position, mutates myIndex values on the parent's children
//  array, and persists the new order.
//

import SwiftUI

struct ChipDropDelegate: DropDelegate {
    let node: TreeNode
    let siblings: [TreeNode]
    let dragInfo: DragInfo
    let appEnvironment: AppEnvironment
    let canReorder: Bool

    func validateDrop(info: DropInfo) -> Bool {
        guard canReorder,
              let dragged = dragInfo.draggedNode,
              dragged != node,
              dragged.parent?.id == node.parent?.id else { return false }
        return true
    }

    func dropEntered(info: DropInfo) {
        guard canReorder,
              let dragged = dragInfo.draggedNode,
              dragged != node,
              dragged.parent?.id == node.parent?.id else { return }

        DispatchQueue.main.async {
            dragInfo.dropTargetNode = node
            // For chips in a flow layout, use left/right (mapped to above/below)
            let midX = info.location.x
            dragInfo.dropPosition = midX < 20 ? .above : .below
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard canReorder else { return nil }
        // Update left/right position as cursor moves within the chip
        if let dragged = dragInfo.draggedNode,
           dragged != node,
           dragged.parent?.id == node.parent?.id {
            let midX = info.location.x
            dragInfo.dropPosition = midX < 20 ? .above : .below
        }
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard canReorder,
              let dragged = dragInfo.draggedNode,
              dragged.parent?.id == node.parent?.id else { return false }

        reorder(draggedNode: dragged, overNode: node)

        dragInfo.draggedNode = nil
        dragInfo.dropTargetNode = nil
        dragInfo.dropPosition = .none
        return true
    }

    func dropExited(info: DropInfo) {
        guard canReorder else { return }
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
            Logger.warning("Failed to save reordered chips: \(error.localizedDescription)", category: .storage)
        }
        appEnvironment.resumeExportCoordinator.debounceExport(resume: parent.resume)
    }
}
