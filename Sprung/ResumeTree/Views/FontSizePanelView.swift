//
//  FontSizePanelView.swift
//  Sprung
//
//
import SwiftData
import SwiftUI
struct FontSizePanelView: View {
    @State var isExpanded: Bool = false
    @Environment(ResumeDetailVM.self) private var vm: ResumeDetailVM
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ToggleChevronView(isExpanded: $isExpanded)
                Text("Font Sizes")
                    .foregroundColor(.secondary)
                    .fontWeight(.regular)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation { isExpanded.toggle() }
            }
            .padding(.leading, 20)
            .padding(.vertical, 5)
            if isExpanded {
                VStack {
                    let nodes = vm.fontSizeNodes
                    if nodes.isEmpty {
                        Text("No font sizes available")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(nodes, id: \.id) { node in
                            FontNodeView(node: node)
                        }
                    }
                }
                .padding(.leading, 28)
                .padding(.trailing, 16)
            }
        }
    }
}
