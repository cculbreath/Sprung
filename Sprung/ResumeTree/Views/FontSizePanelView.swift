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
        HStack {
            ToggleChevronView(isExpanded: $isExpanded)
            Text("Font Sizes")
                .font(.headline)
        }
        .onTapGesture {
            withAnimation { isExpanded.toggle() }
        }
        .cornerRadius(5)
        .padding(.vertical, 2)
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
            .padding(.trailing, 16) // Avoid overlap on trailing side.
        }
    }
}
