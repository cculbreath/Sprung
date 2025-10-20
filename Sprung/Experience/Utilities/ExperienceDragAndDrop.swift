import SwiftUI

struct ExperienceReorderDropDelegate<Item: Identifiable & Equatable>: DropDelegate where Item.ID == UUID {
    let target: Item
    @Binding var items: [Item]
    @Binding var draggingID: UUID?
    var onChange: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingID = draggingID,
              draggingID != target.id,
              let fromIndex = items.firstIndex(where: { $0.id == draggingID }),
              let toIndex = items.firstIndex(of: target) else { return }

        if fromIndex != toIndex {
            withAnimation(.easeInOut(duration: 0.15)) {
                var updated = items
                let element = updated.remove(at: fromIndex)
                let adjustedIndex = fromIndex < toIndex ? toIndex - 1 : toIndex
                let targetIndex = max(min(adjustedIndex, updated.count), 0)
                updated.insert(element, at: targetIndex)
                items = updated
                onChange()
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }
}

struct ExperienceReorderTrailingDropDelegate<Item: Identifiable & Equatable>: DropDelegate where Item.ID == UUID {
    @Binding var items: [Item]
    @Binding var draggingID: UUID?
    var onChange: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingID = draggingID,
              let fromIndex = items.firstIndex(where: { $0.id == draggingID }) else { return }
        let lastIndex = max(items.count - 1, 0)
        guard lastIndex >= 0, fromIndex != lastIndex else { return }

        withAnimation(.easeInOut(duration: 0.15)) {
            var updated = items
            let element = updated.remove(at: fromIndex)
            updated.append(element)
            items = updated
            onChange()
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }
}
