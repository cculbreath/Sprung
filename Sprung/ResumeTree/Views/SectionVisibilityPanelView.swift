import SwiftUI
struct SectionVisibilityPanelView: View {
    @State private var isExpanded: Bool = false
    @Environment(ResumeDetailVM.self) private var vm: ResumeDetailVM
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ToggleChevronView(isExpanded: $isExpanded)
                Text("Show Sections")
                    .font(.body)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation { isExpanded.toggle() }
            }
            .padding(.vertical, 2)
            if isExpanded {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    ForEach(vm.sectionVisibilityKeysOrdered(), id: \.self) { key in
                        GridRow {
                            Text(vm.sectionVisibilityLabel(for: key))
                                .font(.subheadline)
                                .gridColumnAlignment(.leading)
                            Toggle("", isOn: vm.sectionVisibilityBinding(for: key))
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .labelsHidden()
                                .gridColumnAlignment(.trailing)
                        }
                    }
                }
                .padding(.leading, 8)
                .padding(.top, 4)
            }
        }
        .padding(.trailing, 12)
    }
}
