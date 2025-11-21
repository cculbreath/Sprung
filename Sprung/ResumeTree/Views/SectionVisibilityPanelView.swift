import SwiftUI
struct SectionVisibilityPanelView: View {
    @State private var isExpanded: Bool = true
    @Environment(ResumeDetailVM.self) private var vm: ResumeDetailVM
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ToggleChevronView(isExpanded: $isExpanded)
                Text("Show Sections")
                    .font(.headline)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation { isExpanded.toggle() }
            }
            .padding(.vertical, 2)
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(vm.sectionVisibilityKeysOrdered(), id: \.self) { key in
                        Toggle(vm.sectionVisibilityLabel(for: key), isOn: vm.sectionVisibilityBinding(for: key))
                            .toggleStyle(.switch)
                    }
                }
                .padding(.leading, 4)
            }
        }
        .padding(.trailing, 12)
    }
}
