//
//  DragInfo.swift
//  Sprung
//
//
import Observation
import SwiftUI
@Observable
class DragInfo {
    var draggedNode: TreeNode?
    var dropTargetNode: TreeNode?
    var dropPosition: DropPosition = .none
    enum DropPosition {
        case none
        case above
        case below
    }
}
