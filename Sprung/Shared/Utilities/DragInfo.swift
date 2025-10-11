//
//  DragInfo.swift
//  Sprung
//
//  Created by Christopher Culbreath on 1/31/25.
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
