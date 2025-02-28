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
                nodeView(rootNode, refresher: $refresher)
                if selRes?.includeFonts ?? false { FontSizePanelView(refresher: $refresher).padding(10) }
            }
        }
    }

    @ViewBuilder
    func nodeView(_ node: TreeNode, refresher: Binding<Bool>) -> some View {
        if node.includeInEditor {
            if node.hasChildren {
                NodeWithChildrenView(
                    node: node,
                    isExpanded: node.parent == nil,
                    isWide: $isWide,
                    refresher: refresher
                )
            } else {
                NodeLeafView(node: node, refresher: refresher)
            }
        } else {
//            EmptyView()
            Text("pants")
        }
    }
}
